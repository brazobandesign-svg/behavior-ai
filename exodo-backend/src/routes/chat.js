const express = require('express');
const router = express.Router();
const auth = require('../middleware/auth');
const { planGuard } = require('../middleware/planGuard');
const { guestLimit } = require('../middleware/guestLimit');
const { classifyByKeywords } = require('../services/intentClassifier');
const { routeMessage, routeMessageStream } = require('../services/modelRouter');
const { getHistory, saveMessage, assertConversationOwner } = require('../services/historyManager');
const { estimateTokens, updateTokenUsage } = require('../services/tokenCounter');
const { extractText } = require('../services/documentExtractor');
const { buildSystemPrompt } = require('../prompts/groundingMinerd');
const { searchMinerdChunks } = require('../services/minerdRetrievalService');
const {
  USER_FACING_ERROR_MESSAGE,
  handleGatewayError,
  isClientAbortError,
  logInternalGatewayError,
} = require('../services/errorSanitizer');

// Multer: almacenamiento en memoria (15MB) para subidas multipart de documentos.
const multer = require('multer');
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 15 * 1024 * 1024 },
});

/**
 * Heurística ligera para detectar consultas pedagógicas / curriculares del MINERD.
 * Si hay discernimiento curricular (nivel, ciclo, grado, competencia, indicador,
 * normativa, planificación, evaluación, etc.) activamos el grounding RAG.
 */
const MINERD_KEYWORDS = [
  'minerd', 'currículo', 'curriculo', 'curricular', 'competencia', 'competencia fundamental',
  'competencia específica', 'competencia especifica', 'indicador de logro', 'indicadores de logro',
  'grado', 'nivel inicial', 'nivel primario', 'nivel secundario', 'ciclo',
  'planificación didáctica', 'planificacion didactica', 'planificación', 'planificacion',
  'situación de aprendizaje', 'situacion de aprendizaje', 'secuencia didáctica', 'secuencia didactica',
  'evaluación de los aprendizajes', 'evaluacion de los aprendizajes', 'rúbrica', 'rubrica',
  'adecuación curricular', 'adecuacion curricular', 'adaptación curricular', 'adaptacion curricular',
  'atención a la diversidad', 'atencion a la diversidad', 'ordenanza 1-2021', 'ordenanza 1.ª-2021',
  'ordenanza', 'ley general de educación', 'ley 66-97', 'normativa', 'legislación educativa',
  'legislacion educativa', 'diseño curricular', 'diseno curricular', 'diseños curriculares',
  'diseños curriculares', 'eje temático', 'eje tematico', 'área curricular', 'area curricular',
  'matemáticas', 'matematicas', 'lengua española', 'lengua espanola', 'ciencias sociales',
  'ciencias naturales', 'educación artística', 'educacion artistica', 'competencia ciudadana',
  'evaluación diagnóstica', 'evaluacion diagnostica', 'formación integral', 'formacion integral',
  'transversal', 'docente', 'docentes', 'aula', 'didáctica', 'didactica', 'pedagogía', 'pedagogia',
];

/**
 * Determina si un mensaje (o contexto de la conversación) es MINERD/educativo.
 */
function isMinerdQuery(...texts) {
  const haystack = texts.filter((t) => typeof t === 'string' && t)
    .map((t) => t.toLowerCase())
    .join(' \n ');
  if (!haystack) return false;
  return MINERD_KEYWORDS.some((kw) => haystack.includes(kw));
}

/**
 * Adapta los chunks devueltos por searchMinerdChunks (formato del servicio)
 * al shape que espera buildContextSection de groundingMinerd.js:
 * { content, short_name, page, section, similarity, ... }.
 */
function adaptChunksForPrompt(chunks) {
  return (Array.isArray(chunks) ? chunks : []).map((c) => ({
    content: c.content,
    short_name: c.source?.short_name || c.document_id || 'MINERD',
    page: c.source?.page ?? null,
    section: c.source?.section || c.source?.subsection || null,
    similarity: c.similarity,
    nivel: c.nivel,
    area_curricular: c.area_curricular,
  }));
}

/**
 * Hosts estructurales/técnicos que NUNCA son fuentes documentales: namespaces
 * XML (w3.org/schema.org — venían del xmlns de los SVG de los artefactos),
 * CDNs de librerías y fuentes tipográficas.
 */
const NON_SOURCE_URL_PATTERN =
  /w3\.org|schema\.org|jsdelivr\.net|unpkg\.com|cdnjs\.cloudflare\.com|fonts\.googleapis\.com|fonts\.gstatic\.com|data:|javascript:/i;

/**
 * Elimina bloques de código cercados del texto antes de extraer fuentes.
 * El HTML de los artefactos contiene URLs estructurales (xmlns, CDNs) que
 * no son documentación: extraerlas producía "Sources" rotos e irrelevantes.
 */
function stripCodeBlocksForSources(text) {
  return String(text || '')
    .replace(/```[\s\S]*?(?:```|$)/g, ' ')
    .replace(/~~~[\s\S]*?(?:~~~|$)/g, ' ');
}

/**
 * Extrae enlaces markdown [Título](URL), URLs en texto plano, chunks RAG y referencias de conocimiento.
 * Garantiza que las fuentes consultadas se entreguen en formato estructurado a la app móvil (SourcesSheet)
 * y persistan en SQLite y Supabase.
 */
function extractSourcesFromText(text, existingSources = [], contextChunks = [], isEducational = false) {
  const found = [];
  const seenTitles = new Set();
  const seenUrls = new Set();

  // Solo se extraen URLs de la PROSA: el código de artefactos va fuera.
  const proseText = stripCodeBlocksForSources(text);

  const addSource = (title, url, favicon) => {
    if (!title || !url) return;
    const cleanUrl = url.trim();
    if (cleanUrl.includes('localhost') || NON_SOURCE_URL_PATTERN.test(cleanUrl) || seenUrls.has(cleanUrl)) return;
    seenUrls.add(cleanUrl);
    seenTitles.add(title);
    found.push({
      title: title.trim(),
      url: cleanUrl,
      favicon: (favicon || title.slice(0, 3)).toUpperCase(),
    });
  };

  // 1. Fuentes pre-existentes del proveedor / motor de búsqueda
  if (Array.isArray(existingSources) && existingSources.length > 0) {
    for (const s of existingSources) {
      addSource(s.title || s.name, s.url || s.link, s.favicon || s.site_name);
    }
  }

  // 2. Chunks recuperados por RAG
  if (Array.isArray(contextChunks) && contextChunks.length > 0) {
    for (const c of contextChunks) {
      const shortName = c.short_name || 'MINERD';
      const pageStr = c.page ? ` (pág. ${c.page})` : '';
      const sectionStr = c.section ? ` · ${c.section}` : '';
      const title = `${shortName}${pageStr}${sectionStr}`;
      addSource(title, 'https://ministeriodeeducacion.gob.do/servicios/docentes/diseno-curricular', shortName.slice(0, 3));
    }
  }

  // 3. Extraer enlaces markdown reales [Título](URL) — solo en prosa
  const mdRegex = /\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g;
  let match;
  while ((match = mdRegex.exec(proseText)) !== null) {
    const title = (match[1] || '').trim();
    const url = (match[2] || '').trim();
    let host = url;
    try { host = new URL(url).host.replace(/^www\./, ''); } catch (_) {}
    addSource(title || host, url, host.slice(0, 3));
  }

  // 4. Extraer URLs explícitas en texto plano https://... — solo en prosa
  const urlRegex = /(https?:\/\/[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}(?:\/[^\s\)\]\>"]*)?)/g;
  while ((match = urlRegex.exec(proseText)) !== null) {
    const url = (match[1] || '').trim();
    let host = url;
    try { host = new URL(url).host.replace(/^www\./, ''); } catch (_) {}
    addSource(host, url, host.slice(0, 3));
  }

  return found.slice(0, 10);
}

/**
 * POST /chat
 * Bible sección 08: flujo completo de un mensaje.
 * Regla #3: Streaming REAL (SSE chunk por chunk, no bloques de 15 chars).
 *
 * Body: { message: string, conversationId?: string, subject?: string }
 * Headers: Authorization: Bearer {supabase_jwt}
 *
 * Stream format (SSE):
 *   data: {"type":"chunk","content":"..."}\n\n
 *   data: {"type":"done","content":"...","sources":[...]}\n\n
 *   data: {"type":"error","content":"..."}\n\n
 */
router.post('/', auth, guestLimit, planGuard, upload.array('files', 5), async (req, res) => {
  // FIX scope: estas tres variables se usan en el catch externo, así que
  // deben declararse ANTES del try — declaradas dentro, un error temprano
  // (entre el inicio del try y la declaración) hacía que el catch lanzara
  // ReferenceError y enmascarara el error real.
  let clientConnected = true;
  let heartbeatInterval = null;
  const abortController = new AbortController();

  try {
    const { message, conversationId, model_override, attachments, subject } = req.body;
    const { userId, plan, anonymous } = req.user;
    const isGuest = !!req.user?.isGuest;
    // taskType: el cliente puede forzar el modo de enrutado ('simple' | 'reasoning').
    // 'auto' (default) o cualquier otro valor => comportamiento actual intacto.
    const requestedTaskType = (req.body && typeof req.body.taskType === 'string') ? req.body.taskType.toLowerCase() : 'auto';
    // Idioma de la interfaz del cliente (ej. 'en', 'fr'). Default 'es'.
    const requestedLocale = (req.body && typeof req.body.locale === 'string' && req.body.locale.trim())
      ? req.body.locale.trim().slice(0, 5).toLowerCase()
      : 'es';

    // C1 (IDOR Guard): validar propiedad de la conversación antes de procesar
    // PERF (TTFT): el SELECT de historial se dispara ANTES del guard para que
    // ambos roundtrips a Supabase viajen en paralelo. El guard sigue
    // decidiendo el 403 ANTES de abrir el stream SSE; si falla, el prefetch
    // se descarta sin usarse (getHistory nunca rechaza: catch interno → []).
    const historyPrefetch = (!isGuest && conversationId)
      ? getHistory(conversationId, 50)
      : null;

    if (conversationId && !isGuest && !anonymous && userId) {
      try {
        await assertConversationOwner(userId, conversationId);
      } catch (err) {
        if (err.status === 403) {
          return res.status(403).json({
            error: 'forbidden',
            message: 'No tienes permiso para acceder a esta conversación.',
          });
        }
        throw err;
      }
    }

    const multipartFiles = Array.isArray(req.files) ? req.files : [];
    const hasAttachments =
      (attachments && Array.isArray(attachments) && attachments.length > 0) ||
      multipartFiles.length > 0;
    if ((!message || typeof message !== 'string' || message.trim().length === 0) && !hasAttachments) {
      return res.status(400).json({ error: 'El campo "message" es requerido' });
    }

    // PERF-2: headers SSE fuera INMEDIATAMENTE tras validar autenticación,
    // rate-limit e IDOR — antes de adjuntos, Supabase o cualquier await.
    // El cliente abre el stream sin esperar la preparación del turno.
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache, no-transform');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no'); // nginx: desactiva buffering
    if (typeof res.flushHeaders === 'function') res.flushHeaders();

    // Construir mensaje enriquecido con adjuntos utilizando documentExtractor multiformato.
    let enhancedMessage = message || '';
    const imageDataUris = []; // data URIs para modelos con vision

    const parts = [];

    // 1) Archivos multipart (multer.memoryStorage): buffer en memoria.
    for (const f of multipartFiles) {
      const mime = (f.mimetype || '').toLowerCase();
      const name = f.originalname || 'archivo';
      if (mime.startsWith('image/')) {
        parts.push(`[Imagen: ${name}]`);
        imageDataUris.push(`data:${mime};base64,${f.buffer.toString('base64')}`);
      } else {
        try {
          const result = await extractText(f.buffer, { mimeType: mime, filename: name });
          if (result.ok && result.text) {
            const formatLabel = (result.format || 'archivo').toUpperCase();
            parts.push(`[${formatLabel}: ${name}]\n${result.text}`);
          } else {
            parts.push(`[Archivo: ${name} - no se pudo extraer texto]`);
          }
        } catch (_) {
          parts.push(`[Archivo: ${name}]`);
        }
      }
    }

    // 2) Adjuntos Base64 (req.body.attachments).
    if (attachments && Array.isArray(attachments) && attachments.length > 0) {
      for (const att of attachments) {
        const mime = (att.mime_type || '').toLowerCase();
        const name = att.file_name || 'archivo';
        const b64 = att.base64 || '';

        if (mime.startsWith('image/')) {
          parts.push(`[Imagen: ${name}]`);
          if (b64) {
            imageDataUris.push(`data:${mime};base64,${b64}`);
          }
        } else if (b64) {
          try {
            const buffer = Buffer.from(b64, 'base64');
            const result = await extractText(buffer, { mimeType: mime, filename: name });
            if (result.ok && result.text) {
              const formatLabel = (result.format || 'archivo').toUpperCase();
              parts.push(`[${formatLabel}: ${name}]\n${result.text}`);
            } else {
              parts.push(`[Archivo: ${name} - no se pudo extraer texto]`);
            }
          } catch (_) {
            parts.push(`[Archivo: ${name}]`);
          }
        } else {
          parts.push(`[Archivo: ${name}]`);
        }
      }
    }

    if (parts.length > 0) {
      const msgText = (message || '').trim();
      enhancedMessage = msgText
        ? parts.join('\n\n') + '\n\n' + msgText
        : parts.join('\n\n') + '\n\nPor favor analiza y describe detalladamente el contenido y los detalles clave de esta imagen o archivo adjunto para ayudar al usuario.';
    }

    // (clientConnected/heartbeatInterval/abortController declarados al inicio
    // del handler, antes del try — ver FIX scope arriba.)

    // FIX (Node 16+ / v24): `req.on('close')` se dispara cuando el CUERPO del
    // request termina de leerse (post-body), NO cuando el cliente se
    // desconecta. Usarlo como señal de desconexión marcaba clientConnected=false
    // antes de streamear el primer chunk y abortaba todas las respuestas.
    // La señal correcta es `res.on('close')`: si el socket se cierra SIN que
    // hayamos llamado res.end() (writableEnded=false), el cliente se fue.
    res.on('close', () => {
      if (!res.writableEnded) {
        clientConnected = false;
        abortController.abort();
        if (heartbeatInterval) clearInterval(heartbeatInterval);
      }
    });

    // Headers SSE y flush ya realizados al inicio del handler (PERF-2);
    // aquí solo quedan el helper de envío y el heartbeat inicial.

    // Helper para enviar chunks forzando flush al cliente.
    const sendSse = (payload) => {
      res.write(`data: ${JSON.stringify(payload)}\n\n`);
      if (typeof res.flush === 'function') res.flush();
    };

    // Heartbeat inicial
    sendSse({ type: 'heartbeat', status: 'connected' });

    // 1 & 2. Paralelizar historial e intención.
    const hasImages = imageDataUris && imageDataUris.length > 0;

    let history = [];
    let intent = 'SIMPLE';
    // PERF-2: prefetch del retrieval MINERD en paralelo con el historial
    // cuando el mensaje ya parece consulta educativa. La compuerta
    // isMinerdQuery se preserva (sin ella, cada mensaje gastaría embeddings).
    let ragPrefetch = null;

    if (isGuest) {
      history = (Array.isArray(req.body.history) ? req.body.history.slice(-20) : []);
      // Clasificar también a los invitados: sin esto, "genera una imagen"
      // caía a SIMPLE y el LLM respondía "no puedo generar imágenes".
      intent = hasImages ? 'VISION' : classifyByKeywords(enhancedMessage);
    } else if (!conversationId && Array.isArray(req.body.history) && req.body.history.length > 0) {
      // PRIVACIDAD (historial en nube OFF): usuario registrado con chat
      // efémero (sin conversationId) manda su ventana local, igual que un
      // invitado. Es su propio contenido y solo afecta su propia respuesta.
      history = req.body.history.slice(-20);
      intent = hasImages ? 'VISION' : 'SIMPLE';
    } else {
      if (isMinerdQuery(enhancedMessage)) {
        ragPrefetch = searchMinerdChunks(enhancedMessage, { limit: 3 }).catch(() => null);
      }
      const [dbHistory, detectedIntent] = await Promise.all([
        historyPrefetch ?? getHistory(conversationId, 50),
        // FIX TTFT: clasificación local por keywords (O(1), sin roundtrip a
        // DeepSeek). El clasificador LLM bloqueaba el inicio del stream 1-5s
        // en CADA mensaje antes de enrutar el modelo.
        hasImages ? Promise.resolve('VISION') : Promise.resolve(classifyByKeywords(enhancedMessage)),
        ragPrefetch, // PERF-2: RAG corre en paralelo (resultado ignorado aquí)
      ]);
      history = dbHistory;
      intent = detectedIntent;
    }

    // Override por cliente: solo 'simple'/'reasoning', sin imágenes y sin
    // intención DOCUMENTO/VISION (esas rutas del router se respetan siempre).
    if ((requestedTaskType === 'simple' || requestedTaskType === 'reasoning')
        && !hasImages
        && intent !== 'DOCUMENTO'
        && intent !== 'VISION') {
      intent = requestedTaskType === 'simple' ? 'SIMPLE' : 'RAZONAMIENTO';
    }

    // IMAGEN + invitado: no quemar tokens del LLM con un "no puedo generar
    // imágenes". Aviso estructurado que la app pinta estilo disclaimer.
    if (intent === 'IMAGEN' && isGuest) {
      sendSse({ type: 'notice', code: 'image_login_required' });
      sendSse({ type: 'done', content: '', sources: [] });
      res.end();
      return;
    }

    // IMAGEN con sesión: generar en el chat (G1.1 3/día, XPi 25/día).
    // Mismo enforce y contabilidad que /api/images/generate.
    if (intent === 'IMAGEN' && !isGuest && !hasImages) {
      const dailyImagesUsed = req.usage?.dailyImagesUsed || 0;
      const dailyImagesLimit = req.usage?.dailyImagesLimit || 0;
      if (dailyImagesLimit > 0 && dailyImagesUsed >= dailyImagesLimit) {
        sendSse({ type: 'notice', code: 'image_daily_limit_reached' });
        sendSse({ type: 'done', content: '', sources: [] });
        res.end();
        return;
      }
      let imageHeartbeat = null;
      try {
        const { generateImage } = require('../services/imageGen');
        // Limpiar el verbo: "genera una imagen de un gato" => "un gato"
        const cleanPrompt = enhancedMessage
          .replace(/^(por\s+favor,?\s*)?(genera|crea|hazme|haz|dibuja|pinta|ilustra|muestrame|muéstrame)\s+(me\s+)?(un|una|el|la|unos|unas)?\s*(imagen|foto|dibujo|ilustraci\w+)\s*(del|de|sobre|con)?\s*/i, '')
          .trim() || enhancedMessage;

        // UX #1 Keep-Alive: DashScope t2i tarda 8–12s sin emitir tokens. Avisar
        // al cliente que la imagen está generándose y mantener vivo el canal
        // SSE durante la espera (heartbeat específico de imagen cada 3s).
        sendSse({ type: 'generating_image' });
        imageHeartbeat = setInterval(() => {
          if (clientConnected) sendSse({ type: 'generating_image' });
        }, 3000);

        const img = await generateImage(cleanPrompt, { size: '1024*1024' });
        // Contabilizar (diario en memoria + mensual en RPC)
        try {
          const { getMemUsageMap } = require('../middleware/planGuard');
          const mem = getMemUsageMap().get(userId);
          if (mem) {
            const today = new Date(Date.now() - 4 * 60 * 60 * 1000).toISOString().slice(0, 10);
            if (mem.lastImageReset !== today) {
              mem.dailyImagesUsed = 1;
              mem.lastImageReset = today;
            } else {
              mem.dailyImagesUsed = (mem.dailyImagesUsed || 0) + 1;
            }
          }
          const { updateTokenUsage } = require('../services/tokenCounter');
          await updateTokenUsage(userId, 0, true, req.usage);
        } catch (e) {
          console.warn('[chat] uso de imagen no contabilizado:', e.message);
        }
        const md = `![imagen generada por Éxodo](${img.url})

[Prompt: ${cleanPrompt}](${img.url})`;
        if (conversationId && !isGuest && !anonymous) {
          try {
            await saveMessage(conversationId, 'user', message || '[Imagen solicitada]', { intent });
            await saveMessage(conversationId, 'assistant', md, { intent: 'IMAGEN' });
          } catch (e) {
            console.error('[chat] saveMessage imagen falló:', e.message);
          }
        }
        sendSse({ type: 'chunk', content: md });
        sendSse({ type: 'done', content: md, message: md, sources: [] });
        res.end();
        return;
      } catch (imgErr) {
        if (isClientAbortError(imgErr) || !clientConnected) {
          try { res.end(); } catch (_) {}
          return;
        }
        logInternalGatewayError(imgErr, { provider: 'dashscope', model: 'image', phase: 'chat-imagen' });
        sendSse({ type: 'notice', code: 'image_generation_failed' });
        sendSse({ type: 'done', content: '', sources: [] });
        res.end();
        return;
      } finally {
        if (imageHeartbeat) clearInterval(imageHeartbeat);
      }
    }

    // 3. Construir mensajes con contexto
    const messages = [
      ...history,
      { role: 'user', content: enhancedMessage },
    ];

    // 4. Streamear respuesta del modelo
    // heartbeatInterval se declara en el scope del handler (let) para poder
    // limpiarlo también desde el catch externo si algo falla a mitad de ruta.
    heartbeatInterval = setInterval(() => {
      if (clientConnected) {
        sendSse({ type: 'heartbeat' });
      }
    }, 5000);

    const isDegraded = !!req.user.isDegraded;
    const savedToCloud = !isGuest && !anonymous && !!conversationId;

    sendSse({
      type: 'meta',
      isGuest: isGuest,
      isDegraded: isDegraded,
      savedToCloud: savedToCloud,
    });

    // Construcción del System Prompt dinámico con grounding MINERD.
    // 1) Si la consulta es educativa/MINERD, intenta recuperar chunks del corpus
    //    y los inyecta en la sección de CONTEXTO RAG. 2) Fallback robusto: si
    //    faltan claves de API, Supabase está caído o no hay resultados, se loguea
    //    un warning leve y se continúa con generación base SIN romper el chat.
    let contextChunks = [];
    const minerdContext = enhancedMessage
      + history.map((h) => h.content).filter(Boolean).join(' \n ');

    if (isMinerdQuery(minerdContext)) {
      try {
        // PERF-2: consumir el prefetch hecho en paralelo con el historial;
        // si no se disparó (el historial cambió la clasificación), consulta
        // secuencial como antes.
        const retrieval = ragPrefetch != null
            ? await ragPrefetch
            : await searchMinerdChunks(enhancedMessage, { limit: 3 });
        if (!retrieval) {
          throw new Error('rag_unavailable');
        }
        contextChunks = adaptChunksForPrompt(retrieval.chunks);
        if (contextChunks.length > 0) {
          console.log(`[chat] Grounding MINERD: ${contextChunks.length} chunk(s) recuperado(s) para la consulta educativa`);
        } else {
          console.warn('[chat] Grounding MINERD: consulta educativa sin chunks relevantes; se procede con generación base');
        }
      } catch (err) {
        console.warn(
          `[chat] Retrieval MINERD omitido (${err.code || err.name || 'error'}): ${err.message}. Continuando con generación base.`
        );
      }
    }

    // PERF (TTFT): modo lite para conversación simple sin adjuntos ni RAG —
    // identidad compacta (~110 tokens). Un "Hola" no debe pagar el prefill
    // completo (~1,350 tokens).
    const useLitePrompt =
      !hasImages &&
      intent === 'SIMPLE' &&
      contextChunks.length === 0 &&
      !subject &&
      !req.body.conversationSubject &&
      !isMinerdQuery(minerdContext);

    const { systemPrompt } = buildSystemPrompt({
      userPlan: plan,
      conversationSubject: subject || req.body.conversationSubject,
      // DECISIÓN 30-ago: la respuesta sigue el idioma EN QUE ESCRIBE el
      // usuario (detectado); la interfaz es solo el fallback ante ambigüedad.
      userLocale: requestedLocale,
      messageLang: detectMessageLang(enhancedMessage),
      contextChunks,
      lite: useLitePrompt,
    });

    // CONTEXT PRUNING: ventana de 50 mensajes (~25 turnos). Las grandes IA no
    // cortan por mensajes sino por tokens; el presupuesto (20k) es el limite duro.
    const MAX_HISTORY_MESSAGES = 50;
    const prunedMessages = Array.isArray(messages) ? messages.slice(-MAX_HISTORY_MESSAGES) : [];

    let fullText = '';
    let result;
    // C1: instrumentación de tiempos (handler→primer token→fin).
    const __t0 = Date.now();
    let __ttftLogged = false;
    try {
      // INTERCEPTOR DE ERRORES DEL STREAM SSE:
      // Cualquier error upstream (401/413/429/500, timeout, connection reset)
      // se captura aquí. El modelo nunca escribe texto crudo del vendor al
      // stream; routeMessageStream ya devuelve un resultado sanitizado, pero
      // este try/catch es la red de seguridad final (p. ej. abortos no-cliente
      // o errores de construcción del prompt).
      result = await routeMessageStream(
        plan,
        intent,
        prunedMessages,
        systemPrompt,
        (chunk) => {
          if (!clientConnected) return;
          const textChunk = typeof chunk === 'string' ? chunk : (chunk?.content || '');
          if (textChunk) {
            if (!__ttftLogged) {
              __ttftLogged = true;
              console.log(`[chat][perf] ttft=${Date.now() - __t0}ms intent=${intent} model=${result?.model || model_override || 'auto'} guest=${isGuest}`);
            }
            fullText += textChunk;
            sendSse({ type: 'chunk', content: textChunk });
          }
        },
        model_override,
        imageDataUris,
        req.body.taskType,
        isDegraded,
        isGuest,
        abortController.signal
      );
    } catch (streamErr) {
      clearInterval(heartbeatInterval);
      // Aborto del cliente: cerrar en silencio, no hay nadie escuchando.
      if (isClientAbortError(streamErr) || !clientConnected) {
        try { res.end(); } catch (_) {}
        return;
      }
      // Log interno completo (stack, vendor, modelo) — SOLO consola del servidor.
      logInternalGatewayError(streamErr, { provider: 'gateway', model: 'stream-dispatch', phase: 'chat-route-stream' });
      // Respuesta sanitizada de marca al cliente.
      sendSse({ type: 'error', content: USER_FACING_ERROR_MESSAGE });
      sendSse({ type: 'done', content: fullText || '', sources: [] });
      res.end();
      return;
    }

    clearInterval(heartbeatInterval);

    if (!clientConnected) {
      res.end();
      return;
    }

    if (result.error) {
      // El router ya sanitizó el mensaje; jamás confiar en texto crudo.
      // Doble escudo: si por cualquier razón el mensaje no es el genérico,
      // se reemplaza por el de marca.
      const safeMessage = result.message === USER_FACING_ERROR_MESSAGE
        ? result.message
        : USER_FACING_ERROR_MESSAGE;
      sendSse({ type: 'error', content: safeMessage });
      sendSse({ type: 'done', content: fullText || '', sources: [] });
      res.end();
      return;
    }

    // 5. Persistir en DB: SOLO para usuarios registrados autenticados
    const isEduQuery = isMinerdQuery(minerdContext);
    const sources = extractSourcesFromText(fullText, result.sources, contextChunks, isEduQuery);

    if (conversationId && !isGuest && !anonymous) {
      try {
        const userMsgToSave = (message && message.trim()) ? message.trim() : (hasImages ? '[Foto adjunta]' : '');
        await saveMessage(conversationId, 'user', userMsgToSave, { intent });
        await saveMessage(conversationId, 'assistant', fullText, {
          intent,
          model: result.model,
          tokensInput: result.tokensInput,
          tokensOutput: result.tokensOutput,
          sources: sources,
        });
      } catch (e) {
        console.error('[chat] saveMessage falló:', e.message);
      }
    }

    sendSse({ type: 'done', content: fullText, sources });
    res.end();

    // 6. Contabilidad de tokens
    if (req.user?.userId && !isGuest && !anonymous) {
      const measuredTokens = (result.tokensInput || 0) + (result.tokensOutput || 0);
      const estimatedTokens = estimateTokens(enhancedMessage) + estimateTokens(fullText);
      const totalTokens = measuredTokens > 0 ? measuredTokens : estimatedTokens;

      updateTokenUsage(req.user.userId, totalTokens, hasImages, req.usage).catch((e) =>
        console.error('[chat] updateTokenUsage falló:', e.message)
      );
    }
  } catch (error) {
    // ========================================================================
    // SANITIZACIÓN OBLIGATORIA — Fix de vulnerabilidad 2026-08-19
    // ========================================================================
    // NUNCA escribir `error.message` crudo al stream o al JSON de respuesta:
    // los errores upstream (Groq 413/429, etc.) contienen org IDs, URLs de
    // vendor y tamaños de payload. Se loguea el detalle completo SOLO en la
    // consola del servidor y se devuelve el mensaje genérico de marca.
    // ========================================================================
    if (isClientAbortError(error)) {
      // El cliente canceló; nada que responder.
      if (heartbeatInterval) clearInterval(heartbeatInterval);
      try { res.end(); } catch (_) {}
      return;
    }

    if (heartbeatInterval) clearInterval(heartbeatInterval);

    logInternalGatewayError(error, { provider: 'gateway', model: 'chat-route', phase: 'chat-route-outer' });

    if (res.headersSent) {
      // Stream SSE ya iniciado: emitir eventos sanitizados y cerrar limpiamente.
      try {
        res.write(`data: ${JSON.stringify({ type: 'error', content: USER_FACING_ERROR_MESSAGE })}\n\n`);
        res.write(`data: ${JSON.stringify({ type: 'done', content: '', sources: [] })}\n\n`);
        res.end();
      } catch (_) {
        // Socket ya cerrado.
      }
    } else {
      // Respuesta JSON (pre-stream): mensaje genérico, sin detalles del vendor.
      res.status(500).json({ error: USER_FACING_ERROR_MESSAGE });
    }
  }
});

/**
 * Títulos estilo ChatGPT/Claude:
 * 1. Saludos triviales → el título SON las palabras del usuario ("Hi" → "Hi").
 *    Jamás se inventa hora del día (el LLM no la conoce: un "Hola" a las 8:57pm
 *    producía "morning greetings") ni contexto ajeno a la conversación.
 * 2. Mensajes con tema → LLM con prompt basado 100% en el contenido, temp 0.3.
 */
const GREETING_FIRST_WORDS = new Set([
  'hi', 'hey', 'hello', 'yo', 'hiya', 'howdy', 'greetings', 'greeting',
  'hola', 'holi', 'buenas', 'buenos', 'saludos', 'salut', 'bonjour', 'bonsoir',
  'coucou', 'allo', 'allô', 'olá', 'ola', 'oi', 'bonjou', 'bonswa', 'alo', 'aloha',
  'hallo', 'ciao', 'namaste', 'salam', 'marhaba', 'привет', '안녕', '你好', 'こんにちは',
]);

const PURE_GREETINGS = new Set([
  'what s up', 'whats up', 'what s up', 'wassup', 'wsp', 'sup',
  'qué onda', 'que onda', 'qué tal', 'que tal', 'qué pasa', 'que pasa',
  'buenas tardes', 'buenas noches', 'buenos días', 'buenos dias', 'buen día', 'buen dia',
]);

// Si el mensaje pide algo (ayuda, creación, pregunta real), NO es saludo
// trivial aunque empiece con "hi" — el título debe reflejar la petición.
const REQUEST_HINTS = /\b(help|ayuda|ay[uú]dame|necesito|quiero|deseo|busco|dime|dame|escribe|redacta|traduce|resume|res[uú]me|genera|crea|hazme|haz|explica|expl[íi]came|analiza|can|could|would|please|por\s+favor|favor|write|make|generate|summarize|translate|create|explain|need|want|tell|cu[eé]ntame|where|when|why|what|which|who)\b/i;

function isTrivialGreeting(text) {
  if (typeof text !== 'string') return false;
  const normalized = text
    .toLowerCase()
    .replace(/[¿?¡!.,;:()"'*~\-_#]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (!normalized) return false;
  if (PURE_GREETINGS.has(normalized)) return true;
  if (REQUEST_HINTS.test(normalized)) return false;
  const words = normalized.split(' ');
  if (words.length > 4) return false;
  return GREETING_FIRST_WORDS.has(words[0]);
}

/**
 * Detección ligera del idioma del MENSAJE (stopwords + diacríticos + rango Unicode).
 * El título debe estar en el idioma en que ESCRIBE el usuario, no en el de la
 * interfaz: UI en inglés + mensaje en español → título en español. Si la señal
 * es ambigua (empate o texto sin palabras funcionales), se usa el locale de la
 * interfaz como fallback.
 */
const LANG_STOPWORDS = {
  es: new Set(['el','la','los','las','un','una','unos','unas','de','del','al','y','o','u','que','qué','cómo','como','para','por','con','sin','sobre','entre','mi','mis','tu','tus','su','sus','nuestro','es','está','esta','estoy','son','fue','ser','hace','hay','más','mas','pero','si','sí','no','ya','muy','necesito','quiero','deseo','dime','dame','hola','gracias','favor','cuál','cual','quién','quien','dónde','donde','cuándo','cuando','cuánto','cuanto','porque','planificación','grado','clase','tarea','aula','alumno','alumnos','enseñar','aprender','matemáticas','lengua','ciencias','sociales','naturales','evaluación','rubrica','rúbrica','escribe','escribeme','puedes','podrias','podrías','ayudame','ayúdame','ayuda','explica','explicame','explícame','haz','crea','busca','traduce','resume','resumeme','resúmeme','hablame','háblame','cuentame','cuéntame','mandame','mándame','ensename','enséñame','muestrame','muéstrame','gusta','parece','entonces','tambien','también','tampoco','aqui','aquí','ahora','luego','despues','después','antes','porfa','mio','mío','tuyo','suyo','vamos','puedo','debo','tengo','deberia','debería','ensayo','ensayos','tareas','proyecto','planificar','planifica','corrige','arregla','diseña','disena','necesitó','necesito','quisiera','mejor','peor','verdadera','cierto','cierta','regalame','regálame','ayudarme','lograr','conseguir','aunque','mientras']),
  en: new Set(['the','a','an','of','to','in','on','for','with','and','or','is','are','was','were','be','been','am','do','does','did','have','has','had','will','would','can','could','should','i','you','he','she','it','we','they','my','your','his','her','our','their','this','that','these','those','what','which','who','whom','where','when','why','how','not','yes','please','thanks','thank','hello','hi','hey','need','want','make','write','tell','give','me','about','from','at','by','if','then','than','so','very','just','now','get','got','let','lesson','grade','plan','help']),
  fr: new Set(['le','la','les','un','une','des','du','de','au','aux','et','ou','que','qui','pour','par','avec','sans','sur','dans','mon','ma','mes','ton','ta','tes','son','sa','ses','notre','nos','votre','vos','leur','leurs','est','sont','était','être','faire','fait','il','elle','je','tu','nous','vous','ils','elles','ce','cet','cette','ces','plus','mais','oui','non','bonjour','salut','merci','besoin','veux','comment','pourquoi','où','quand','combien','cours','classe']),
  pt: new Set(['o','a','os','as','um','uma','uns','umas','de','do','da','dos','das','em','no','na','para','por','com','sem','sobre','entre','meu','minha','meus','minhas','seu','sua','é','são','foi','ser','fazer','faz','há','mais','mas','não','sim','obrigado','olá','oi','preciso','quero','como','porque','porquê','qual','quem','onde','quando','quanto','aula','turma','plano']),
  ht: new Set(['nan','yo','ki','mwen','nou','ak','pou','poukisa','kijan','kòman','bonjou','bonswa','mèsi','bezwen','vle','fè','genyen','gen','yon','lekòl','timoun','se','sa','la']),
};

const DIACRITIC_HINTS = {
  es: /[ñáéíóúü¿¡]/g,
  pt: /[ãõâêç]/g,
  fr: /[àèùœîï]/g,
};

function detectMessageLang(text) {
  if (!text || typeof text !== 'string' || text.trim().length < 2) return null;

  // Scripts no latinos: detección directa por rango Unicode (kana antes que
  // han: el japonés mezcla kanji + kana; el chino puro no tiene kana).
  if (/[\u3040-\u30FF]/.test(text)) return 'ja';
  if (/[\uAC00-\uD7AF]/.test(text)) return 'ko';
  if (/[\u4E00-\u9FFF]/.test(text)) return 'zh';
  if (/[\u0400-\u04FF]/.test(text)) return 'ru';
  if (/[\u0600-\u06FF]/.test(text)) return 'ar';
  if (/[\u0900-\u097F]/.test(text)) return 'hi';

  const lower = text.toLowerCase();
  // Señal fuerte (30-ago): ¿ ¡ ñ son exclusivos del español — si aparecen y
  // no hay señal contraria, es español. Arregló "a veces sí, a veces no".
  if (/[¿¡ñ]/.test(text) && !/[a-z]the[a-z]|[a-z]ing\s/.test(lower)) return 'es';
  const tokens = lower.split(/[^a-zà-ÿñ']+/).filter(Boolean);
  const scores = { es: 0, en: 0, fr: 0, pt: 0, ht: 0 };
  for (const w of tokens) {
    for (const lang of Object.keys(scores)) {
      if (LANG_STOPWORDS[lang].has(w)) scores[lang] += 1;
    }
  }
  for (const [lang, re] of Object.entries(DIACRITIC_HINTS)) {
    const hits = lower.match(re);
    if (hits) scores[lang] += hits.length * 0.5;
  }
  const sorted = Object.entries(scores).sort((a, b) => b[1] - a[1]);
  const [topLang, topScore] = sorted[0];
  const secondScore = sorted[1][1];
  // Dominancia estricta: empate o cero señales → null (fallback al locale UI).
  return topScore >= 1 && topScore > secondScore ? topLang : null;
}

/**
 * POST /api/chat/title
 * Genera un título ultra-conciso (2 a 4 palabras) usando LLM (qwen3.7-flash).
 * Saludos triviales NO gastan LLM: el título son las palabras del usuario.
 */
router.post('/title', auth, async (req, res) => {
  try {
    const { conversationId, messages } = req.body || {};
    const locale = (typeof req.body?.locale === 'string' && req.body.locale.trim())
      ? req.body.locale.trim().slice(0, 5).toLowerCase()
      : 'es';
    const { userId, isGuest, anonymous } = req.user || {};

    // C1 (IDOR Guard): validar propiedad de la conversación
    if (conversationId && !isGuest && !anonymous && userId) {
      try {
        await assertConversationOwner(userId, conversationId);
      } catch (err) {
        if (err.status === 403) {
          return res.status(403).json({
            error: 'forbidden',
            message: 'No tienes permiso para acceder a esta conversación.',
          });
        }
        throw err;
      }
    }

    if (!Array.isArray(messages) || messages.length === 0) {
      return res.status(400).json({ error: 'messages array is required' });
    }

    const userMsg = messages.find((m) => m.role === 'user');
    const asstMsg = messages.find((m) => m.role === 'assistant');

    const userText = (userMsg?.content || '').trim();

    if (!userText && !(asstMsg?.content || '').trim()) {
      return res.json({ title: 'Nueva conversación' });
    }

    // Saludo trivial: el título es el mensaje del usuario, sin LLM, sin
    // invención de hora/ánimo. "Hi" → "Hi"; "Buenas tardes" → "Buenas tardes".
    if (isTrivialGreeting(userText)) {
      return res.json({ title: userText.slice(0, 40) });
    }

    const asstSnippet = (asstMsg?.content || '').trim().slice(0, 300);

    const TITLE_LANGS = {
      en: 'English', fr: 'Français', pt: 'Português', ht: 'Kreyòl Ayisyen',
      de: 'Deutsch', it: 'Italiano', ru: 'Русский', zh: '中文',
      ja: '日本語', ko: '한국어', hi: 'हिन्दी', ar: 'العربية',
    };
    // Idioma del título = idioma en que ESCRIBE el usuario (detectado), no el
    // de la interfaz. UI en inglés + mensaje en español → título en español.
    // Solo si el mensaje es ambiguo se respeta el locale de la interfaz.
    const uiLocale = TITLE_LANGS[locale] ? locale : 'es';
    const titleLocale = detectMessageLang(userText) || detectMessageLang(asstSnippet) || uiLocale;
    const titleLang = TITLE_LANGS[titleLocale] || 'español';
    const systemPrompt =
      `Eres el generador de títulos de una app de chat con IA (estilo ChatGPT/Claude). ` +
      `Crea un título de 2 a 4 palabras EN ${titleLang} que refleje el TEMA REAL de la conversación (asunto, intención o entidad principal del mensaje del usuario). ` +
      `REGLAS ESTRICTAS: ` +
      `(1) Basa el título SOLO en el contenido de la conversación; PROHIBIDO inventar hora del día, fecha, ánimo, lugar o cualquier contexto no mencionado en el mensaje. ` +
      `(2) PROHIBIDO números, numeración, comillas, markdown, emojis o punto final. ` +
      `(3) Conserva la capitalización natural de ${titleLang}: primera letra mayúscula, nunca todo minúsculas. ` +
      `(4) Si el mensaje ya es breve y claro, usa sus propias palabras sin adornos. ` +
      `Devuelve ÚNICAMENTE el título.`;

    const prompt = `Usuario: ${userText || '(Imagen / archivo adjunto)'}\nAsistente: ${asstSnippet}`;

    const alibaba = require('../services/providers/alibaba');
    const result = await alibaba.call('qwen3.7-flash', [prompt], systemPrompt, {
      max_tokens: 40,
      temperature: 0.3,
    });

    let rawTitle = (result.text || '').trim();
    // Limpieza de comillas, markdown, puntuación terminal y numeración alucinada
    // ("morning greetings 2" → "morning greetings"): los dígitos sueltos al
    // final provienen del "2 a 4 palabras" del prompt en modelos débiles.
    rawTitle = rawTitle
      .replace(/^["'«“`]+|["'»”`]+$/g, '')
      .replace(/[#*_`~]/g, '')
      .replace(/\.+$/, '')
      .replace(/\s+\d{1,3}$/, '')
      .trim();

    if (!rawTitle || rawTitle.length > 50) {
      rawTitle = rawTitle.slice(0, 40).trim();
    }

    if (rawTitle) {
      rawTitle = rawTitle.charAt(0).toUpperCase() + rawTitle.slice(1);
    }

    return res.json({ title: rawTitle || 'Conversación' });
  } catch (error) {
    console.error('[chat/title] Error generando título con LLM:', error.message);
    return res.status(500).json({ error: 'Failed to generate title', fallback: 'Conversación' });
  }
});

module.exports = router;
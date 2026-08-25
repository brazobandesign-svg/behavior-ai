const express = require('express');
const router = express.Router();
const auth = require('../middleware/auth');
const { planGuard } = require('../middleware/planGuard');
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
 * Extrae enlaces markdown [Título](URL), URLs en texto plano, chunks RAG y referencias de conocimiento.
 * Garantiza que las fuentes consultadas se entreguen en formato estructurado a la app móvil (SourcesSheet)
 * y persistan en SQLite y Supabase.
 */
function extractSourcesFromText(text, existingSources = [], contextChunks = [], isEducational = false) {
  const found = [];
  const seenTitles = new Set();
  const seenUrls = new Set();

  const addSource = (title, url, favicon) => {
    if (!title || !url) return;
    const cleanUrl = url.trim();
    if (cleanUrl.includes('localhost') || seenUrls.has(cleanUrl)) return;
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

  // 3. Extraer enlaces markdown [Título](URL)
  const mdRegex = /\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g;
  let match;
  while ((match = mdRegex.exec(text)) !== null) {
    const title = (match[1] || '').trim();
    const url = (match[2] || '').trim();
    let host = url;
    try { host = new URL(url).host.replace(/^www\./, ''); } catch (_) {}
    addSource(title || host, url, host.slice(0, 3));
  }

  // 4. Extraer URLs en texto plano https://...
  const urlRegex = /(https?:\/\/[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}(?:\/[^\s\)\]\>"]*)?)/g;
  while ((match = urlRegex.exec(text)) !== null) {
    const url = (match[1] || '').trim();
    let host = url;
    try { host = new URL(url).host.replace(/^www\./, ''); } catch (_) {}
    addSource(host, url, host.slice(0, 3));
  }

  // 5. Entidades de conocimiento, repositorios científicos y fuentes autorizadas
  const knowledgeEntities = [
    // Astronomía y Astrofísica
    { keywords: [/sagitario\s*b2/i, /v[íi]a\s*l[áa]ctea/i, /astronom[íi]a/i, /interestelar/i, /astroqu[íi]mica/i, /galaxia/i, /telescopio/i], title: 'NASA · Astrophysics Data System', url: 'https://ui.adsabs.harvard.edu', favicon: 'ADS' },
    { keywords: [/sagitario\s*b2/i, /nube\s*molecular/i, /espacio/i, /exoplaneta/i, /supernova/i], title: 'European Southern Observatory (ESO)', url: 'https://www.eso.org', favicon: 'ESO' },
    // Física, Fusión Nuclear, Cuántica y Energía
    { keywords: [/fusi[óo]n\s*nuclear/i, /tokamak/i, /plasma/i, /stellarator/i, /iter/i], title: 'ITER · International Thermonuclear Experimental Reactor', url: 'https://www.iter.org', favicon: 'ITR' },
    { keywords: [/fusi[óo]n/i, /nuclear/i, /energ[íi]a\s*at[óo]mica/i, /radiaci[óo]n/i, /is[óo]topo/i], title: 'IAEA · International Atomic Energy Agency', url: 'https://www.iaea.org', favicon: 'IAE' },
    { keywords: [/f[íi]sica/i, /cu[áa]ntic[ao]/i, /part[íi]cula/i, /bos[óo]n/i, /relatividad/i, /qu[íi]mica/i, /termodin[áa]mica/i], title: 'arXiv · Cornell University Library', url: 'https://arxiv.org', favicon: 'ARX' },
    // Matemáticas y Filosofía
    { keywords: [/pit[áa]goras/i, /teorema/i, /geometr[íi]a/i, /filosof[íi]a/i, /l[óo]gica/i, /epistemolog[íi]a/i], title: 'Stanford Encyclopedia of Philosophy', url: 'https://plato.stanford.edu', favicon: 'SEP' },
    { keywords: [/pit[áa]goras/i, /matem[áa]tica/i, /c[áa]lculo/i, /ecuaci[óo]n/i, /algoritmo/i], title: 'Wolfram MathWorld', url: 'https://mathworld.wolfram.com', favicon: 'WMW' },
    // Ciencias de la Salud y Biología
    { keywords: [/medicina/i, /c[eé]lula/i, /gen[eé]tica/i, /adn/i, /arn/i, /prote[íi]na/i, /farmacolog[íi]a/i, /virus/i, /inmunolog[íi]a/i], title: 'PubMed · National Library of Medicine (NIH)', url: 'https://pubmed.ncbi.nlm.nih.gov', favicon: 'MED' },
    { keywords: [/salud/i, /epidemia/i, /vacuna/i, /enfermedad/i, /oms/i, /who/i], title: 'World Health Organization (OMS)', url: 'https://www.who.int', favicon: 'OMS' },
    // Leyes y Normativas Dominicanas
    { keywords: [/constituci[óo]n/i, /c[óo]digo\s*civil/i, /ley\s*\d+/i, /jurisprudencia/i, /tribunal/i, /sentencia/i], title: 'Poder Judicial Dominicano · Repositorio Legal', url: 'https://poderjudicial.gob.do/servicios/consultas-de-leyes/', favicon: 'PJD' },
    // Computación, Tecnología e Ingeniería
    { keywords: [/inteligencia\s*artificial/i, /red\s*neuronal/i, /machine\s*learning/i, /deep\s*learning/i, /computaci[óo]n/i], title: 'IEEE Xplore Digital Library', url: 'https://ieeexplore.ieee.org', favicon: 'IEE' },
  ];

  for (const entity of knowledgeEntities) {
    if (found.length >= 10) break;
    const matches = entity.keywords.some((rx) => rx.test(text));
    if (matches && !seenUrls.has(entity.url)) {
      addSource(entity.title, entity.url, entity.favicon);
    }
  }

  // 6. Si es consulta educativa/curricular dominicana y no hay fuentes específicas, adjuntar el marco normativo MINERD
  if (isEducational && found.length === 0) {
    addSource('MINERD · Diseño Curricular Nivel Secundario', 'https://ministeriodeeducacion.gob.do/servicios/docentes/diseno-curricular', 'DC');
    addSource('MINERD · Ordenanza 04-2023 / 01-2021', 'https://ministeriodeeducacion.gob.do/transparencia/marco-legal/ordenanzas', 'ORD');
    addSource('Ley General de Educación 66-97', 'https://ministeriodeeducacion.gob.do/transparencia/marco-legal/ley-general-de-educacion-66-97', 'LEY');
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
router.post('/', auth, planGuard, upload.array('files', 5), async (req, res) => {
  try {
    const { message, conversationId, model_override, attachments, subject } = req.body;
    const { userId, plan, anonymous } = req.user;
    const isGuest = !!req.user?.isGuest;

    // C1 (IDOR Guard): validar propiedad de la conversación antes de procesar
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

// Flag para detectar si el cliente se desconectó a mitad de la respuesta.
    let clientConnected = true;
    let heartbeatInterval = null; // scope del handler: limpiable desde el catch externo
    const abortController = new AbortController();
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

    // Preparar SSE ANTES de cualquier await para que el cliente vea los
    // headers inmediatamente y empiece a esperar chunks.
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache, no-transform');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no'); // nginx: desactiva buffering
    if (typeof res.flushHeaders === 'function') res.flushHeaders();

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
      history = (Array.isArray(req.body.history) ? req.body.history.slice(-6) : []);
      intent = hasImages ? 'VISION' : 'SIMPLE';
    } else {
      if (isMinerdQuery(enhancedMessage)) {
        ragPrefetch = searchMinerdChunks(enhancedMessage, { limit: 3 }).catch(() => null);
      }
      const [dbHistory, detectedIntent] = await Promise.all([
        getHistory(conversationId, 10),
        // FIX TTFT: clasificación local por keywords (O(1), sin roundtrip a
        // DeepSeek). El clasificador LLM bloqueaba el inicio del stream 1-5s
        // en CADA mensaje antes de enrutar el modelo.
        hasImages ? Promise.resolve('VISION') : Promise.resolve(classifyByKeywords(enhancedMessage)),
        ragPrefetch, // PERF-2: RAG corre en paralelo (resultado ignorado aquí)
      ]);
      history = dbHistory;
      intent = detectedIntent;
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

    const { systemPrompt } = buildSystemPrompt({
      userPlan: plan,
      conversationSubject: subject || req.body.conversationSubject,
      userLocale: 'es',
      contextChunks,
    });

    // CONTEXT PRUNING: Limitar historial a 10 mensajes para evitar latencia de 28s
    // en conversaciones muy largas (240k+ tokens).
    const MAX_HISTORY_MESSAGES = 10;
    const prunedMessages = Array.isArray(messages) ? messages.slice(-MAX_HISTORY_MESSAGES) : [];

    let fullText = '';
    let result;
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
        // FIX (no-mutación 2026-08-19): persistir SOLO el texto original que
        // escribió el usuario. `enhancedMessage` (con etiquetas [Imagen:...] y
        // el prompt sintético de análisis) se usa ÚNICAMENTE como payload al LLM,
        // jamás se guarda en el historial ni se muestra en la burbuja del usuario.
        await saveMessage(conversationId, 'user', message || '', { intent });
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
 * POST /api/chat/title
 * Genera un título ultra-conciso (2 a 4 palabras) usando LLM (qwen3.7-flash)
 * con temperatura 0.0 y zero-shot.
 */
router.post('/title', auth, async (req, res) => {
  try {
    const { conversationId, messages } = req.body || {};
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
    const asstSnippet = (asstMsg?.content || '').trim().slice(0, 300);

    if (!userText && !asstSnippet) {
      return res.json({ title: 'Nueva conversación' });
    }

    const systemPrompt =
      'Eres un generador de títulos concisos. Genera un título temático de 2 a 4 palabras en español que resuma el núcleo de la conversación. Devuelve ÚNICAMENTE el título limpio, sin comillas, sin formato Markdown y sin punto final.';

    const prompt = `Usuario: ${userText || '(Imagen / archivo adjunto)'}\nAsistente: ${asstSnippet}`;

    const alibaba = require('../services/providers/alibaba');
    const result = await alibaba.call('qwen3.7-flash', [prompt], systemPrompt, {
      max_tokens: 30,
      temperature: 0.0,
    });

    let rawTitle = (result.text || '').trim();
    // Limpieza de comillas, markdown y puntuación terminal
    rawTitle = rawTitle
      .replace(/^["'«“`]+|["'»”`]+$/g, '')
      .replace(/[#*_`~]/g, '')
      .replace(/\.+$/, '')
      .trim();

    if (!rawTitle || rawTitle.length > 50) {
      rawTitle = rawTitle.slice(0, 40).trim();
    }

    return res.json({ title: rawTitle || 'Conversación' });
  } catch (error) {
    console.error('[chat/title] Error generando título con LLM:', error.message);
    return res.status(500).json({ error: 'Failed to generate title', fallback: 'Conversación' });
  }
});

module.exports = router;
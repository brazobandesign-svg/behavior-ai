const express = require('express');
const router = express.Router();
const auth = require('../middleware/auth');
const { planGuard } = require('../middleware/planGuard');
const { classifyIntent } = require('../services/intentClassifier');
const { routeMessage, routeMessageStream } = require('../services/modelRouter');
const { getHistory, saveMessage } = require('../services/historyManager');
const { estimateTokens, updateTokenUsage } = require('../services/tokenCounter');
const pdfParse = require('pdf-parse'); // [Punto 40+42] Extracción de texto de PDF

/**
 * System prompt de Éxodo — Bible sección 11, Regla #7:
 * "El system prompt de Éxodo está en español. La personalidad es hispanohablante y caribeña."
 * Regla #9: "No puede instruirlo a mentir si el usuario pregunta directamente."
 */
const EXODO_SYSTEM_PROMPT = `Eres Éxodo, un asistente de inteligencia artificial creado por Behavior.

Tu personalidad:
- Eres cercano, directo y útil. Tu tono es profesional pero cálido.
- Tu idioma nativo es el español. Respondes en el idioma que el usuario use.
- Tienes contexto profundo sobre República Dominicana y Latinoamérica.
- Conoces el currículo del MINERD, legislación dominicana y el contexto cultural local.

Reglas:
- No reveles qué modelo de IA corre por debajo de ti. Eres Éxodo.
- Si el usuario pregunta directamente si fuiste entrenado por Behavior, sé honesto: eres una interfaz inteligente creada por Behavior que utiliza tecnología de IA avanzada.
- Nunca inventes información legal o médica. Si no sabes, dilo.
- Formatea tus respuestas con markdown cuando sea apropiado.`;

/**
 * Extrae enlaces markdown [Título](URL) y URLs en texto plano del contenido.
 * Garantiza que las fuentes citadas se persistan en Supabase desde el backend.
 */
function extractSourcesFromText(text, existingSources = []) {
  if (existingSources && existingSources.length > 0) {
    return existingSources.slice(0, 10);
  }
  const found = [];
  const seenUrls = new Set();
  
  // 1. Extraer enlaces markdown [Título](URL)
  const mdRegex = /\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g;
  let match;
  while ((match = mdRegex.exec(text)) !== null) {
    const title = (match[1] || '').trim();
    const url = (match[2] || '').trim();
    if (url && !url.includes('localhost') && !seenUrls.has(url)) {
      seenUrls.add(url);
      let host = url;
      try { host = new URL(url).host; } catch (_) {}
      found.push({
        title: title || host,
        url: url
      });
    }
  }

  // 2. Extraer URLs en texto plano https://...
  const urlRegex = /(https?:\/\/[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}(?:\/[^\s\)\]\>"]*)?)/g;
  while ((match = urlRegex.exec(text)) !== null) {
    const url = (match[1] || '').trim();
    if (url && !url.includes('localhost') && !seenUrls.has(url)) {
      seenUrls.add(url);
      let host = url;
      try { host = new URL(url).host.replace(/^www\./, ''); } catch (_) {}
      found.push({
        title: host,
        url: url
      });
    }
  }

  return found.slice(0, 10);
}

/**
 * POST /chat
 * Bible sección 08: flujo completo de un mensaje.
 * Regla #3: Streaming REAL (SSE chunk por chunk, no bloques de 15 chars).
 *
 * Body: { message: string, conversationId?: string }
 * Headers: Authorization: Bearer {supabase_jwt}
 *
 * Stream format (SSE):
 *   data: {"type":"chunk","content":"..."}\n\n
 *   data: {"type":"done","content":"...","sources":[...]}\n\n
 *   data: {"type":"error","content":"..."}\n\n
 */
router.post('/', auth, planGuard, async (req, res) => {
  try {
    const { message, conversationId, model_override, attachments } = req.body;
    const { userId, plan, anonymous } = req.user;

    const hasAttachments = attachments && Array.isArray(attachments) && attachments.length > 0;
    if ((!message || typeof message !== 'string' || message.trim().length === 0) && !hasAttachments) {
      return res.status(400).json({ error: 'El campo "message" es requerido' });
    }

    // [Punto 40+42] Construir mensaje enriquecido con adjuntos.
    // PDFs: extraer texto real con pdf-parse.
    // Imágenes: etiquetar para clasificación + guardar data URI para visión.
    // Archivos de texto: decodificar y prepender al mensaje.
    let enhancedMessage = message || '';
    const imageDataUris = []; // [Punto 42] data URIs para modelos con visión

    if (attachments && Array.isArray(attachments) && attachments.length > 0) {
      const parts = [];
      for (const att of attachments) {
        const mime = (att.mime_type || '').toLowerCase();
        const name = att.file_name || 'archivo';
        const b64 = att.base64 || '';

        if (mime.startsWith('image/')) {
          // [Punto 42] Etiquetar para el clasificador + guardar para visión
          parts.push(`[Imagen: ${name}]`);
          if (b64) {
            imageDataUris.push(`data:${mime};base64,${b64}`);
          }
        } else if (mime === 'application/pdf') {
          // [Punto 40] Extraer texto real del PDF con pdf-parse
          try {
            const pdfBuffer = Buffer.from(b64, 'base64');
            const pdfData = await pdfParse(pdfBuffer);
            const pdfText = pdfData.text || '';
            parts.push(`[PDF: ${name}]\n${pdfText}`);
          } catch (_) {
            parts.push(`[PDF: ${name} - no se pudo extraer texto]`);
          }
        } else if (
          mime.startsWith('text/') ||
          name.endsWith('.md') || name.endsWith('.json') ||
          name.endsWith('.xml') || name.endsWith('.csv')
        ) {
          try {
            const text = Buffer.from(b64, 'base64').toString('utf-8');
            parts.push(`[Archivo: ${name}]\n${text}`);
          } catch (_) {
            parts.push(`[Archivo: ${name}]`);
          }
        } else {
          parts.push(`[Archivo: ${name}]`);
        }
      }
      if (parts.length > 0) {
        const msgText = (message || '').trim();
        enhancedMessage = msgText
          ? parts.join('\n\n') + '\n\n' + msgText
          : parts.join('\n\n') + '\n\nPor favor analiza y describe detalladamente el contenido y los detalles clave de esta imagen o archivo adjunto para ayudar al usuario.';
      }
    }

    // Flag para detectar si el cliente se desconectó a mitad de la respuesta.
    // Si se cierra la conexión, abortamos: no enviamos más SSE, no contamos tokens,
    // no guardamos mensajes. El provider sigue corriendo pero ignoramos su resultado.
    let clientConnected = true;
    req.on('close', () => {
      clientConnected = false;
    });

    // Preparar SSE ANTES de cualquier await para que el cliente vea los
    // headers inmediatamente y empiece a esperar chunks.
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no'); // nginx: desactiva buffering
    res.flushHeaders();

    // Helper para enviar chunks forzando flush al cliente.
    const sendSse = (payload) => {
      res.write(`data: ${JSON.stringify(payload)}\n\n`);
      // Forzar flush inmediato en cada chunk.
      if (typeof res.flush === 'function') res.flush();
    };

    // [Punto 4 Fix] Enviar heartbeat inmediato. Esto garantiza que el cliente
    // móvil reciba los headers HTTP y primeros bytes en <100ms, resolviendo
    // la promesa reqClient.send(request) al instante sin caer por timeout.
    sendSse({ type: 'heartbeat', status: 'connected' });

    // 1 & 2. Paralelizar historial e intención.
    // Para Guests: Cero consultas a Supabase (historial viene en payload o vacío).
    const isGuest = !!req.user?.isGuest;
    const hasImages = imageDataUris && imageDataUris.length > 0;

    let history = [];
    let intent = 'SIMPLE';

    if (isGuest) {
      history = (Array.isArray(req.body.history) ? req.body.history.slice(-6) : []);
      intent = hasImages ? 'VISION' : 'SIMPLE';
    } else {
      const [dbHistory, detectedIntent] = await Promise.all([
        getHistory(conversationId, 10),
        hasImages ? Promise.resolve('VISION') : classifyIntent(enhancedMessage),
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
    const heartbeatInterval = setInterval(() => {
      if (clientConnected) {
        sendSse({ type: 'heartbeat' });
      }
    }, 5000);

    // [Metadatos SSE Neutros]: Solo flags de estado del sistema (isGuest, savedToCloud, isDegraded)
    const isDegraded = !!req.user.isDegraded;
    const savedToCloud = !isGuest && !anonymous && !!conversationId;

    sendSse({
      type: 'meta',
      isGuest: isGuest,
      isDegraded: isDegraded,
      savedToCloud: savedToCloud,
    });

    let fullText = '';
    const result = await routeMessageStream(
      plan,
      intent,
      messages,
      EXODO_SYSTEM_PROMPT,
      (chunk) => {
        // Si el cliente se fue, dejamos de acumular texto y de enviar chunks.
        if (!clientConnected) return;
        fullText += chunk;
        sendSse({ type: 'chunk', content: chunk });
      },
      model_override,
      imageDataUris,
      req.body.taskType,
      isDegraded,
      isGuest
    );

    clearInterval(heartbeatInterval);

    // Si el cliente se desconectó antes de terminar, no enviamos done/error ni persistimos.
    if (!clientConnected) {
      res.end();
      return;
    }

    // Si el router devolvió un error (feature no disponible, etc.),
    // mandarlo como SSE para que el frontend lo parsee correctamente.
    if (result.error) {
      sendSse({ type: 'error', content: result.message || 'Error procesando tu mensaje' });
      res.end();
      return;
    }

    // 5. Persistir en DB: SOLO para usuarios registrados autenticados (NUNCA para guests)
    const sources = extractSourcesFromText(fullText, result.sources);

    if (conversationId && !isGuest && !anonymous) {
      try {
        await saveMessage(conversationId, 'user', enhancedMessage, { intent });
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

    // 6. Contabilidad de tokens: SOLO para usuarios registrados autenticados
    if (req.user?.userId && !isGuest && !anonymous) {
      const measuredTokens = (result.tokensInput || 0) + (result.tokensOutput || 0);
      const estimatedTokens = estimateTokens(enhancedMessage) + estimateTokens(fullText);
      const totalTokens = measuredTokens > 0 ? measuredTokens : estimatedTokens;

      updateTokenUsage(req.user.userId, totalTokens, hasImages, req.usage).catch((e) =>
        console.error('[chat] updateTokenUsage falló:', e.message)
      );
    }
  } catch (error) {
    console.error('[chat] Error procesando mensaje:', error);
    if (res.headersSent) {
      res.write(`data: ${JSON.stringify({ type: 'error', content: error.message || 'Error procesando tu mensaje' })}\n\n`);
      res.end();
    } else {
      res.status(500).json({
        error: 'Error procesando tu mensaje',
        details: process.env.NODE_ENV !== 'production' ? error.message : undefined,
      });
    }
  }
});

module.exports = router;
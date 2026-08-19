const { GoogleGenAI } = require('@google/genai');

/**
 * Provider: Google Gemini 2.5 Flash-Lite (@google/genai)
 * 
 * Rol en la arquitectura:
 * 1. Modelo primario y dedicado para Visión Multimodal (imágenes, OCR, capturas, diagramas).
 * 2. Fallback transparente de texto cuando DeepSeek arroje 429, timeout o 500/503.
 * 
 * Guardrails Obligatorios de Costos:
 * - Modelo exacto: 'gemini-2.5-flash-lite' ($0.10 in / $0.40 out por 1M).
 * - PROHIBIDO Search Grounding: Cero tools de búsqueda (evita cobro de $35/1k calls).
 * - PROHIBIDO Maps Grounding (evita cobro de $25/1k calls).
 * - PROHIBIDO Context Caching persistente en payloads cortos.
 */

const TARGET_MODEL = 'gemini-flash-lite-latest';

function getClient() {
  const apiKey = process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY;
  if (!apiKey) {
    throw new Error('GEMINI_API_KEY / GOOGLE_API_KEY no configurada en el entorno');
  }

  return new GoogleGenAI({ apiKey });
}

function parseDataUri(dataUri) {
  if (typeof dataUri !== 'string') return null;

  const match = dataUri.match(/^data:([^;]+);base64,(.+)$/);
  if (match) {
    return {
      mimeType: match[1],
      data: match[2],
    };
  }

  // Si viene solo base64 sin prefijo data:
  return {
    mimeType: 'image/jpeg',
    data: dataUri,
  };
}

function buildContents(messages, systemPrompt, imageDataUris = []) {
  const contents = [];

  for (let i = 0; i < messages.length; i++) {
    const msg = messages[i];
    const isLast = i === messages.length - 1;
    const role = msg.role === 'assistant' ? 'model' : 'user';

    const parts = [];

    // Agregar texto del mensaje
    if (msg.content) {
      parts.push({
        text: typeof msg.content === 'string' ? msg.content : JSON.stringify(msg.content),
      });
    }

    // Si es el último mensaje de usuario y hay imágenes adjuntas, agregar inlineData
    if (isLast && role === 'user' && imageDataUris && imageDataUris.length > 0) {
      for (const uri of imageDataUris) {
        const parsed = parseDataUri(uri);
        if (parsed) {
          parts.push({
            inlineData: {
              mimeType: parsed.mimeType,
              data: parsed.data,
            },
          });
        }
      }
    }

    if (parts.length > 0) {
      contents.push({
        role,
        parts,
      });
    }
  }

  return contents;
}

/**
 * Llamada estándar (no streaming)
 */
async function call(modelId, messages, systemPrompt, imageDataUris = [], options = {}) {
  const ai = getClient();
  const contents = buildContents(messages, systemPrompt, imageDataUris);

  // Configuración estricta sin Grounding
  const config = {
    maxOutputTokens: options.max_tokens || 2000,
    temperature: 0.7,
  };

  if (systemPrompt && systemPrompt.trim()) {
    config.systemInstruction = {
      parts: [{ text: systemPrompt.trim() }],
    };
  }

  if (options.signal && options.signal.aborted) {
    throw new Error('AbortError');
  }

  let response;
  const generatePromise = ai.models.generateContent({
    model: TARGET_MODEL,
    contents: contents,
    config: config,
  });

  if (options.signal) {
    const abortPromise = new Promise((_, reject) => {
      const onAbort = () => reject(new Error('AbortError'));
      options.signal.addEventListener('abort', onAbort);
      // Clean up the event listener when generatePromise completes
      generatePromise.finally(() => options.signal.removeEventListener('abort', onAbort)).catch(() => {});
    });
    response = await Promise.race([generatePromise, abortPromise]);
  } else {
    response = await generatePromise;
  }

  const text = response.text || '';
  const usage = response.usageMetadata || {};

  return {
    text: text,
    tokensInput: usage.promptTokenCount || 0,
    tokensOutput: usage.candidatesTokenCount || 0,
    model: TARGET_MODEL,
    provider: 'gemini',
  };
}

/**
 * Llamada con Streaming
 */
async function callStream(modelId, messages, systemPrompt, onChunk, imageDataUris = [], options = {}) {
  const ai = getClient();
  const contents = buildContents(messages, systemPrompt, imageDataUris);

  const config = {
    maxOutputTokens: options.max_tokens || 2000,
    temperature: 0.7,
  };

  if (systemPrompt && systemPrompt.trim()) {
    config.systemInstruction = {
      parts: [{ text: systemPrompt.trim() }],
    };
  }

  const responseStream = await ai.models.generateContentStream({
    model: TARGET_MODEL,
    contents: contents,
    config: config,
  });

  let fullText = '';
  let usage = {};

  for await (const chunk of responseStream) {
    if (options.signal && options.signal.aborted) break;
    if (chunk.text) {
      fullText += chunk.text;
      onChunk(chunk.text);
    }
    if (chunk.usageMetadata) {
      usage = chunk.usageMetadata;
    }
  }

  return {
    text: fullText,
    tokensInput: usage.promptTokenCount || 0,
    tokensOutput: usage.candidatesTokenCount || 0,
    model: TARGET_MODEL,
    provider: 'gemini',
  };
}

module.exports = {
  call,
  callStream,
};

const { MODEL_MAP, GENESIS_FALLBACK_CHAIN, XPI_FALLBACK_CHAIN, MODEL_TO_PROVIDER } = require('../config/models');

/**
 * Model Router — Bible sección 05.
 * Decide qué API llamar según intención + plan.
 * Nunca llama a Sonnet por default sin clasificación previa.
 * Cascada de fallback para Genesis (4 proveedores).
 *
 * Dos variantes:
 *   • routeMessage       → bloqueante, devuelve texto completo
 *   • routeMessageStream → streamea cada chunk al callback onChunk
 */

/**
 * Estima el número de tokens en la petición (promedio ~3.5 chars/token).
 */
function estimateTokens(messages, systemPrompt) {
  const text = (systemPrompt || '') + JSON.stringify(messages || []);
  return Math.ceil(text.length / 3.5);
}

/**
 * Construye dinámicamente la cadena de fallback óptima según la cuota y el volumen de tokens.
 * Evita enviar documentos/prompts masivos (>12k tokens) a Groq donde morirían con 429.
 */
function getFallbackChainForRequest(plan, intent, messages, systemPrompt, effectiveModelId) {
  const isXpi = plan === 'hazak' || effectiveModelId === 'ehyeh' || effectiveModelId === 'hazak';
  if (isXpi) {
    const list = [effectiveModelId, ...XPI_FALLBACK_CHAIN];
    return Array.from(new Set(list.filter(Boolean)));
  }

  // [Fix visión] VISION nunca debe caer en la cascada normal de texto
  // (Groq/Llama/DeepSeek no aceptan imageDataUris). Cadena específica:
  // pixtral-12b-2409 como motor de visión real de Mistral.
  if (intent === 'VISION') {
    return Array.from(new Set([effectiveModelId, 'pixtral-12b-2409'].filter(Boolean)));
  }

  const tokenCount = estimateTokens(messages, systemPrompt);
  let chain = [];

  // Regla táctica para documentos densos o prompts gigantes > 12,000 tokens
  if (intent === 'DOCUMENTO' || tokenCount > 12000) {
    if (tokenCount > 28000) {
      // Si supera 28,000 tokens, solo Mistral aguanta (625k - 2.25M TPM)
      chain = [
        effectiveModelId,
        'mistral-large-2512',
        'codestral-2508',
        'mistral-small-2506'
      ];
    } else {
      // Entre 12,000 y 28,000 tokens: Mistral + Llama 4 Scout (30k TPM en Groq)
      chain = [
        effectiveModelId,
        'mistral-large-2512',
        'codestral-2508',
        'mistral-small-2506',
        'meta-llama/llama-4-scout-17b-16e-instruct'
      ];
    }
  } else {
    // Para peticiones estándar <= 12,000 tokens: Cascada optimizada completa
    chain = [
      effectiveModelId,
      'codestral-2508',
      'mistral-small-2506',
      'meta-llama/llama-4-scout-17b-16e-instruct',
      'llama-3.3-70b-versatile',
      'qwen/qwen3.6-27b'
    ];
  }

  return Array.from(new Set(chain.filter(Boolean)));
}

/**
 * Obtiene el provider correcto y ejecuta la llamada con fallback.
 * @param {string} plan - 'genesis' | 'hazak'
 * @param {string} intent - 'SIMPLE' | 'REDACCION' | 'RAZONAMIENTO' | 'DOCUMENTO' | 'IMAGEN'
 * @param {Array} messages - Array de mensajes con formato { role, content }
 * @param {string} systemPrompt - El system prompt de Éxodo
 * @returns {Promise<ReadableStream|Object>} - Stream SSE o respuesta de imagen
 */
async function routeMessage(plan, intent, messages, systemPrompt, modelOverride, imageDataUris) {
  const modelId = MODEL_MAP[intent]?.[plan];
  const effectiveModelId = modelOverride || modelId;

  if (!effectiveModelId) {
    return {
      error: 'feature_not_available',
      message: intent === 'IMAGEN'
        ? 'La generación de imágenes solo está disponible en el plan Hazak.'
        : 'Esta función no está disponible en tu plan actual.',
      plan_required: 'hazak',
    };
  }

  // Usar cascada de fallback en caso de error
  if (intent !== 'IMAGEN') {
    const chain = getFallbackChainForRequest(plan, intent, messages, systemPrompt, effectiveModelId);
    return await callWithFallback(chain, messages, systemPrompt, imageDataUris);
  }

  // Para Hazak IMAGEN, llamar directo al modelo asignado
  return await callProvider(effectiveModelId, messages, systemPrompt, imageDataUris);
}

/**
 * Variante streaming real. Itera la cascada con cada modelo.
 */
async function routeMessageStream(plan, intent, messages, systemPrompt, onChunk, modelOverride, imageDataUris) {
  const modelId = MODEL_MAP[intent]?.[plan];

  const effectiveModelId = modelOverride || modelId;

  if (!effectiveModelId) {
    return {
      error: 'feature_not_available',
      message: intent === 'IMAGEN'
        ? 'La generación de imágenes solo está disponible en el plan Hazak.'
        : 'Esta función no está disponible en tu plan actual.',
      plan_required: 'hazak',
      text: '',
      tokensInput: 0,
      tokensOutput: 0,
    };
  }

  if (intent !== 'IMAGEN') {
    const chain = getFallbackChainForRequest(plan, intent, messages, systemPrompt, effectiveModelId);
    return await callStreamWithFallback(chain, messages, systemPrompt, onChunk, imageDataUris);
  }

  return await callProviderStream(effectiveModelId, messages, systemPrompt, onChunk, imageDataUris);
}

/**
 * Intenta llamar proveedores en cascada hasta que uno responda.
 * Loggea cada intento con su código de error para diagnóstico rápido.
 */
async function callWithFallback(fallbackChain, messages, systemPrompt, imageDataUris) {
  const attempts = [];

  for (const modelId of fallbackChain) {
    const t0 = Date.now();
    try {
      const result = await callProvider(modelId, messages, systemPrompt, imageDataUris);
      if (result && !result.error) {
        const elapsed = Date.now() - t0;
        console.log(`[modelRouter] ✅ ${modelId} OK en ${elapsed}ms`);
        return result;
      }
      attempts.push({ modelId, code: 'ERROR', detail: result?.message || 'error devuelto' });
    } catch (err) {
      const elapsed = Date.now() - t0;
      const code = err.code || 'UNKNOWN';
      attempts.push({ modelId, code, elapsed, detail: err.message });
      console.warn(`[modelRouter] ❌ ${modelId} ${code} en ${elapsed}ms — ${err.message}`);
      continue;
    }
  }

  console.error('[modelRouter] Todos los proveedores fallaron:', JSON.stringify(attempts, null, 2));
  return {
    error: 'all_providers_failed',
    message: 'Todos los proveedores están temporalmente no disponibles. Intenta de nuevo en unos minutos.',
    attempts,
  };
}

/**
 * Llama al provider correcto basado en el modelId.
 */
async function callProvider(modelId, messages, systemPrompt, imageDataUris) {
  const providerName = MODEL_TO_PROVIDER[modelId];

  if (!providerName) {
    throw new Error(`Provider no configurado para modelo: ${modelId}`);
  }

  const provider = require(`./providers/${providerName}`);
  return await provider.call(modelId, messages, systemPrompt, imageDataUris);
}

/**
 * Variante streaming de callProvider.
 * Si el provider expone callStream(), lo usa. Si no, hace fallback al
 * modo bloqueante y emite el texto completo como un solo chunk.
 */
async function callProviderStream(modelId, messages, systemPrompt, onChunk, imageDataUris) {
  const providerName = MODEL_TO_PROVIDER[modelId];

  if (!providerName) {
    throw new Error(`Provider no configurado para modelo: ${modelId}`);
  }

  const provider = require(`./providers/${providerName}`);

  if (typeof provider.callStream === 'function') {
    return await provider.callStream(modelId, messages, systemPrompt, onChunk, imageDataUris);
  }

  // Fallback: bloqueante → emite todo de golpe (mejor que nada).
  const result = await provider.call(modelId, messages, systemPrompt, imageDataUris);
  if (result && result.text) onChunk(result.text);
  return result;
}

/**
 * Itera la cascada probando cada modelo con streaming.
 * Si el provider soporta callStream, streamea real.
 * Si no, emite de golpe (vía callProviderStream).
 */
async function callStreamWithFallback(fallbackChain, messages, systemPrompt, onChunk, imageDataUris) {
  const attempts = [];

  for (const modelId of fallbackChain) {
    const t0 = Date.now();
    try {
      const result = await callProviderStream(modelId, messages, systemPrompt, onChunk, imageDataUris);
      if (result && !result.error) {
        const elapsed = Date.now() - t0;
        console.log(`[modelRouter] ✅ ${modelId} stream OK en ${elapsed}ms (${result.tokensOutput} tok out)`);
        return result;
      }
      attempts.push({ modelId, code: 'ERROR', detail: result?.message || 'error devuelto' });
    } catch (err) {
      const elapsed = Date.now() - t0;
      const code = err.code || 'UNKNOWN';
      attempts.push({ modelId, code, elapsed, detail: err.message });
      console.warn(`[modelRouter] ❌ ${modelId} ${code} en ${elapsed}ms — ${err.message}`);
      // Si el cliente ya recibió chunks parciales, no podemos "deshacer".
      // Devolvemos lo que tengamos y marcamos error.
      continue;
    }
  }

  console.error('[modelRouter] Todos los proveedores fallaron:', JSON.stringify(attempts, null, 2));
  return {
    error: 'all_providers_failed',
    message: 'Todos los proveedores están temporalmente no disponibles. Intenta de nuevo en unos minutos.',
    attempts,
    text: '',
    tokensInput: 0,
    tokensOutput: 0,
  };
}

module.exports = { routeMessage, routeMessageStream };

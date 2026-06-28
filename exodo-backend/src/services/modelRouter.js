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
 * Obtiene el provider correcto y ejecuta la llamada con fallback.
 * @param {string} plan - 'genesis' | 'hazak'
 * @param {string} intent - 'SIMPLE' | 'REDACCION' | 'RAZONAMIENTO' | 'DOCUMENTO' | 'IMAGEN'
 * @param {Array} messages - Array de mensajes con formato { role, content }
 * @param {string} systemPrompt - El system prompt de Éxodo
 * @returns {Promise<ReadableStream|Object>} - Stream SSE o respuesta de imagen
 */
async function routeMessage(plan, intent, messages, systemPrompt, modelOverride) {
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

  // Usar cascada de fallback en caso de error (intenta toda la lista hasta llegar a Ollama local)
  // Primero intenta el modelo asignado por intent+plan, luego cascada completa.
  if (intent !== 'IMAGEN') {
    const isXpi = plan === 'hazak' || modelOverride === 'ehyeh' || modelOverride === 'hazak';
    const fallbackList = isXpi ? XPI_FALLBACK_CHAIN : GENESIS_FALLBACK_CHAIN;
    const chain = [effectiveModelId, ...fallbackList.filter((m) => m !== effectiveModelId)];
    return await callWithFallback(chain, messages, systemPrompt);
  }

  // Para Hazak IMAGEN, llamar directo al modelo asignado
  return await callProvider(effectiveModelId, messages, systemPrompt);
}

/**
 * Variante streaming real. Itera la cascada con cada modelo.
 * Si un modelo tiene callStream(), lo usa; si no, cae al modo bloqueante
 * y emite todo el texto de golpe (mejor que nada).
 *
 * @param {string} plan
 * @param {string} intent
 * @param {Array} messages
 * @param {string} systemPrompt
 * @param {(chunk: string) => void} onChunk
 * @returns {Promise<{text:string, model:string, tokensInput:number, tokensOutput:number, error?:string, message?:string, attempts?:Array}>}
 */
async function routeMessageStream(plan, intent, messages, systemPrompt, onChunk, modelOverride) {
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
    const isXpi = plan === 'hazak' || modelOverride === 'ehyeh' || modelOverride === 'hazak';
    const fallbackList = isXpi ? XPI_FALLBACK_CHAIN : GENESIS_FALLBACK_CHAIN;
    const chain = [effectiveModelId, ...fallbackList.filter((m) => m !== effectiveModelId)];
    return await callStreamWithFallback(chain, messages, systemPrompt, onChunk);
  }

  return await callProviderStream(effectiveModelId, messages, systemPrompt, onChunk);
}

/**
 * Intenta llamar proveedores en cascada hasta que uno responda.
 * Loggea cada intento con su código de error para diagnóstico rápido.
 */
async function callWithFallback(fallbackChain, messages, systemPrompt) {
  const attempts = [];

  for (const modelId of fallbackChain) {
    const t0 = Date.now();
    try {
      const result = await callProvider(modelId, messages, systemPrompt);
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
async function callProvider(modelId, messages, systemPrompt) {
  const providerName = MODEL_TO_PROVIDER[modelId];

  if (!providerName) {
    throw new Error(`Provider no configurado para modelo: ${modelId}`);
  }

  const provider = require(`./providers/${providerName}`);
  return await provider.call(modelId, messages, systemPrompt);
}

/**
 * Variante streaming de callProvider.
 * Si el provider expone callStream(), lo usa. Si no, hace fallback al
 * modo bloqueante y emite el texto completo como un solo chunk.
 */
async function callProviderStream(modelId, messages, systemPrompt, onChunk) {
  const providerName = MODEL_TO_PROVIDER[modelId];

  if (!providerName) {
    throw new Error(`Provider no configurado para modelo: ${modelId}`);
  }

  const provider = require(`./providers/${providerName}`);

  if (typeof provider.callStream === 'function') {
    return await provider.callStream(modelId, messages, systemPrompt, onChunk);
  }

  // Fallback: bloqueante → emite todo de golpe (mejor que nada).
  const result = await provider.call(modelId, messages, systemPrompt);
  if (result && result.text) onChunk(result.text);
  return result;
}

/**
 * Itera la cascada probando cada modelo con streaming.
 * Si el provider soporta callStream, streamea real.
 * Si no, emite de golpe (vía callProviderStream).
 */
async function callStreamWithFallback(fallbackChain, messages, systemPrompt, onChunk) {
  const attempts = [];

  for (const modelId of fallbackChain) {
    const t0 = Date.now();
    try {
      const result = await callProviderStream(modelId, messages, systemPrompt, onChunk);
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

const { MODEL_MAP, GENESIS_FALLBACK_CHAIN, XPI_FALLBACK_CHAIN, MODEL_TO_PROVIDER } = require('../config/models');

/**
 * Model Router
 * Decide qué API llamar según intención + plan.
 * Dos variantes:
 *   • routeMessage       → bloqueante, devuelve texto completo
 *   • routeMessageStream → streamea cada chunk al callback onChunk
 */

function getFallbackChainForRequest(plan, intent, messages, systemPrompt, effectiveModelId) {
  // Simplificado temporalmente. El usuario definirá las reglas luego.
  return [effectiveModelId];
}

async function routeMessage(plan, intent, messages, systemPrompt, modelOverride, imageDataUris) {
  const modelId = MODEL_MAP[intent]?.[plan];
  const effectiveModelId = modelOverride || modelId;

  if (!effectiveModelId) {
    return {
      error: 'feature_not_available',
      message: 'Esta función no está disponible en tu plan actual.',
      plan_required: 'hazak',
    };
  }

  if (intent !== 'IMAGEN') {
    const chain = getFallbackChainForRequest(plan, intent, messages, systemPrompt, effectiveModelId);
    return await callWithFallback(chain, messages, systemPrompt, imageDataUris);
  }

  return await callProvider(effectiveModelId, messages, systemPrompt, imageDataUris);
}

async function routeMessageStream(plan, intent, messages, systemPrompt, onChunk, modelOverride, imageDataUris) {
  const modelId = MODEL_MAP[intent]?.[plan];
  const effectiveModelId = modelOverride || modelId;

  if (!effectiveModelId) {
    return {
      error: 'feature_not_available',
      message: 'Esta función no está disponible en tu plan actual.',
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

async function callProvider(modelId, messages, systemPrompt, imageDataUris) {
  const providerName = MODEL_TO_PROVIDER[modelId];

  if (!providerName) {
    throw new Error(`Provider no configurado para modelo: ${modelId}`);
  }

  const provider = require(`./providers/${providerName}`);
  return await provider.call(modelId, messages, systemPrompt, imageDataUris);
}

async function callProviderStream(modelId, messages, systemPrompt, onChunk, imageDataUris) {
  const providerName = MODEL_TO_PROVIDER[modelId];

  if (!providerName) {
    throw new Error(`Provider no configurado para modelo: ${modelId}`);
  }

  const provider = require(`./providers/${providerName}`);

  if (typeof provider.callStream === 'function') {
    return await provider.callStream(modelId, messages, systemPrompt, onChunk, imageDataUris);
  }

  const result = await provider.call(modelId, messages, systemPrompt, imageDataUris);
  if (result && result.text) onChunk(result.text);
  return result;
}

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

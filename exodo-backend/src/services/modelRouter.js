const { MODEL_MAP, GENESIS_FALLBACK_CHAIN, MODEL_TO_PROVIDER } = require('../config/models');

/**
 * Model Router — Bible sección 05.
 * Decide qué API llamar según intención + plan.
 * Nunca llama a Sonnet por default sin clasificación previa.
 * Cascada de fallback para Genesis (4 proveedores).
 */

/**
 * Obtiene el provider correcto y ejecuta la llamada con fallback.
 * @param {string} plan - 'genesis' | 'hazak'
 * @param {string} intent - 'SIMPLE' | 'REDACCION' | 'RAZONAMIENTO' | 'DOCUMENTO' | 'IMAGEN'
 * @param {Array} messages - Array de mensajes con formato { role, content }
 * @param {string} systemPrompt - El system prompt de Éxodo
 * @returns {Promise<ReadableStream|Object>} - Stream SSE o respuesta de imagen
 */
async function routeMessage(plan, intent, messages, systemPrompt) {
  const modelId = MODEL_MAP[intent]?.[plan];

  if (!modelId) {
    return {
      error: 'feature_not_available',
      message: intent === 'IMAGEN'
        ? 'La generación de imágenes solo está disponible en el plan Hazak.'
        : 'Esta función no está disponible en tu plan actual.',
      plan_required: 'hazak',
    };
  }

  // Usar cascada de fallback en caso de error (intenta toda la lista hasta llegar a Ollama local)
  if (intent !== 'IMAGEN') {
    return await callWithFallback(GENESIS_FALLBACK_CHAIN, messages, systemPrompt);
  }

  // Para Hazak IMAGEN, llamar directo al modelo asignado
  return await callProvider(modelId, messages, systemPrompt);
}

/**
 * Intenta llamar proveedores en cascada hasta que uno responda.
 */
async function callWithFallback(fallbackChain, messages, systemPrompt) {
  for (const modelId of fallbackChain) {
    try {
      const result = await callProvider(modelId, messages, systemPrompt);
      if (result && !result.error) {
        return result;
      }
    } catch (err) {
      console.warn(`[modelRouter] Fallback: ${modelId} falló (${err.message}), intentando siguiente...`);
      continue;
    }
  }

  return {
    error: 'all_providers_failed',
    message: 'Todos los proveedores están temporalmente no disponibles. Intenta de nuevo en unos minutos.',
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

module.exports = { routeMessage };

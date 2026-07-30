const { MODEL_MAP, MODEL_TO_PROVIDER } = require('../config/models');

/**
 * Model Router — Matriz de Enrutamiento Inteligente Éxodo
 * 
 * Regla de Oro:
 * 1. Detección Multimodal Primero: Si hay imágenes adjuntas, FORZAR gpt-4o-mini
 *    sin importar el plan (G1.1 o Hazak), ya que DeepSeek no procesa imágenes.
 * 2. Texto Puro:
 *    - Plan G1.1 (Free): gpt-4o-mini (OpenAI)
 *    - Plan Hazak (Pro): deepseek-chat (DeepSeek V3)
 *    - Modo Razonamiento Profundo (Hazak): deepseek-reasoner (DeepSeek R1)
 */

function getEffectiveModel(plan, intent, modelOverride, imageDataUris) {
  // 1. Regla de Oro: Detección Multimodal Primero.
  // Si hay imagen, forzar gpt-4o-mini sin importar el plan o intención.
  if (imageDataUris && imageDataUris.length > 0) {
    return 'gpt-4o-mini';
  }

  // 2. Si hay override de modelo explícito enviado por el cliente
  if (modelOverride) {
    if (MODEL_TO_PROVIDER[modelOverride]) {
      return modelOverride;
    }
    // Mapeo defensivo para modelos legacy no reconocidos -> usar deepseek-chat
    if (modelOverride.includes('nemotron') || modelOverride.includes('origo')) {
      return 'deepseek-chat';
    }
    if (modelOverride.includes('deepseek') || modelOverride.includes('ehyeh') || modelOverride.includes('hazak')) {
      return 'deepseek-chat';
    }
    return 'deepseek-chat';
  }

  // 3. Matriz estándar por intención y plan
  const mapped = MODEL_MAP[intent]?.[plan];
  return mapped || 'deepseek-chat';
}

async function routeMessage(plan, intent, messages, systemPrompt, modelOverride, imageDataUris) {
  const effectiveModelId = getEffectiveModel(plan, intent, modelOverride, imageDataUris);

  if (!effectiveModelId) {
    return {
      error: 'feature_not_available',
      message: 'Esta función no está disponible en tu plan actual.',
      plan_required: 'hazak',
    };
  }

  return await callProvider(effectiveModelId, messages, systemPrompt, imageDataUris);
}

async function routeMessageStream(plan, intent, messages, systemPrompt, onChunk, modelOverride, imageDataUris) {
  const effectiveModelId = getEffectiveModel(plan, intent, modelOverride, imageDataUris);

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

  return await callProviderStream(effectiveModelId, messages, systemPrompt, onChunk, imageDataUris);
}

async function callProvider(modelId, messages, systemPrompt, imageDataUris) {
  const providerName = MODEL_TO_PROVIDER[modelId] || 'openai';
  const provider = require(`./providers/${providerName}`);
  return await provider.call(modelId, messages, systemPrompt, imageDataUris);
}

async function callProviderStream(modelId, messages, systemPrompt, onChunk, imageDataUris) {
  const providerName = MODEL_TO_PROVIDER[modelId] || 'openai';
  const provider = require(`./providers/${providerName}`);

  if (typeof provider.callStream === 'function') {
    return await provider.callStream(modelId, messages, systemPrompt, onChunk, imageDataUris);
  }

  const result = await provider.call(modelId, messages, systemPrompt, imageDataUris);
  if (result && result.text) onChunk(result.text);
  return result;
}

module.exports = { routeMessage, routeMessageStream, getEffectiveModel };

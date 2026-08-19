const { PLAN_CONFIG, MODEL_MAP, ECO_MODELS } = require('../config/models');
const deepseekProvider = require('./providers/deepseekProvider');
const geminiProvider = require('./providers/geminiProvider');
const groqProvider = require('./providers/groqProvider');

/**
 * Model Router — Matriz de Enrutamiento Inteligente Éxodo v4.2
 * 
 * Reglas:
 * 1. Cuentas Guest / Anónimas O Free Degrado (cuota diaria agotada):
 *    ├── ¿Hay imagen/archivo? -> Groq Visión (qwen/qwen3.6-27b)
 *    └── ¿Solo texto/código? -> Groq Texto (llama-3.3-70b-versatile, max_tokens: 4096, respuesta natural)
 *    ==> CERO consumo en DeepSeek ($0.00 USD).
 * 
 * 2. Cuentas Registradas Free (< 6,000 tokens diarios):
 *    ├── ¿Hay imagen/archivo? -> Gemini 2.5 Flash-Lite
 *    └── ¿Solo texto/código? -> DeepSeek V4 Flash (deepseek-chat)
 * 
 * 3. Cuentas Registradas Pro (Hazak $4.99 / 50,000 tokens diarios):
 *    ├── ¿Hay imagen/archivo? -> Gemini 2.5 Flash-Lite
 *    └── ¿Solo texto/código? -> DeepSeek V4 Pro (deepseek-reasoner)
 */

function getEffectiveModel(plan, intent, modelOverride, imageDataUris, taskType, isDegraded = false, isGuest = false) {
  const isPro = (plan === 'pro' || plan === 'hazak');
  const hasImages = imageDataUris && imageDataUris.length > 0;

  // A. Multimodal Primero si hay imágenes
  if (hasImages) {
    if (isGuest || plan === 'guest' || (isDegraded && !isPro)) {
      return {
        provider: 'groq',
        modelId: ECO_MODELS.vision,
        isEco: true,
        maxTokens: PLAN_CONFIG.free.ecoMaxOutputTokens, // 4096
      };
    }
    return {
      provider: 'gemini',
      modelId: 'gemini-flash-lite-latest',
      isEco: false,
      maxTokens: isPro ? PLAN_CONFIG.pro.maxOutputTokens : PLAN_CONFIG.free.maxOutputTokensNormal,
    };
  }

  // B. Override explícito del cliente (prioridad absoluta para pruebas o selección específica)
  if (modelOverride) {
    const override = String(modelOverride).toLowerCase();
    if (override.includes('gemini')) {
      return { provider: 'gemini', modelId: 'gemini-flash-lite-latest', isEco: false, maxTokens: isPro ? 4096 : 1500 };
    }
    if (override.includes('groq') || override.includes('llama')) {
      return { provider: 'groq', modelId: ECO_MODELS.text, isEco: true, maxTokens: PLAN_CONFIG.free.ecoMaxOutputTokens };
    }
    if (override.includes('xpi') || override.includes('ehyeh') || override.includes('hazak') || override.includes('reasoner') || override.includes('pro') || override.includes('r1')) {
      return { provider: 'deepseek', modelId: 'deepseek-reasoner', isEco: false, maxTokens: PLAN_CONFIG.pro.maxOutputTokens };
    }
    if (override.includes('g1.1') || override.includes('origo') || override.includes('flash') || override.includes('genesis') || override.includes('chat') || override.includes('alibaba') || override.includes('qwen')) {
      return { provider: 'deepseek', modelId: process.env.ALIBABA_MODEL || 'deepseek-chat', isEco: false, maxTokens: PLAN_CONFIG.free.maxOutputTokensNormal };
    }
  }

  // CASO 1: GUEST O MODO ECO (Costo $0.00 en Groq — Limpio y sin cortes artificiales)
  if (isGuest || plan === 'guest' || (isDegraded && !isPro)) {
    return {
      provider: 'groq',
      modelId: ECO_MODELS.text,
      isEco: true,
      maxTokens: PLAN_CONFIG.free.ecoMaxOutputTokens, // 4096
    };
  }

  // CASO 2: USUARIOS REGISTRADOS DENTRO DE CUOTA O PRO

  // C. Plan Pro (Hazak): Llamada exclusiva a DeepSeek Reasoner V4 Pro
  if (isPro) {
    return {
      provider: 'deepseek',
      modelId: 'deepseek-reasoner',
      isEco: false,
      maxTokens: PLAN_CONFIG.pro.maxOutputTokens,
    };
  }

  // D. Tareas de razonamiento explícito
  if (taskType === 'reasoning' || taskType === 'code_analysis' || intent === 'RAZONAMIENTO') {
    return {
      provider: 'deepseek',
      modelId: 'deepseek-reasoner',
      isEco: false,
      maxTokens: 2500,
    };
  }

  // E. Plan Free Registrado dentro de cuota: DeepSeek V4 Flash / Alibaba Qwen
  return {
    provider: 'deepseek',
    modelId: process.env.ALIBABA_MODEL || 'deepseek-chat',
    isEco: false,
    maxTokens: PLAN_CONFIG.free.maxOutputTokensNormal,
  };
}

/**
 * Llamada estándar con fallback
 */
async function routeMessage(plan, intent, messages, systemPrompt, modelOverride, imageDataUris, taskType, isDegraded = false, isGuest = false, signal = null) {
  const target = getEffectiveModel(plan, intent, modelOverride, imageDataUris, taskType, isDegraded, isGuest);
  const options = { max_tokens: target.maxTokens, signal };

  if (target.provider === 'groq') {
    return await groqProvider.call(target.modelId, messages, systemPrompt, imageDataUris, options);
  }

  if (target.provider === 'gemini') {
    return await geminiProvider.call(target.modelId, messages, systemPrompt, imageDataUris, options);
  }

  try {
    return await deepseekProvider.call(target.modelId, messages, systemPrompt, options);
  } catch (error) {
    console.warn(`[ModelRouter Fallback] Proveedor primario falló (${error.message}). Reintentando con Gemini Flash-Lite...`);
    try {
      return await geminiProvider.call('gemini-flash-lite-latest', messages, systemPrompt, imageDataUris, options);
    } catch (geminiError) {
      console.warn(`[ModelRouter Fallback] Gemini falló. Reintentando con Groq Eco...`);
      return await groqProvider.call(ECO_MODELS.text, messages, systemPrompt, imageDataUris, options);
    }
  }
}

/**
 * Llamada Streaming SSE con fallback
 */
async function routeMessageStream(plan, intent, messages, systemPrompt, onChunk, modelOverride, imageDataUris, taskType, isDegraded = false, isGuest = false, signal = null) {
  const target = getEffectiveModel(plan, intent, modelOverride, imageDataUris, taskType, isDegraded, isGuest);
  const options = { max_tokens: target.maxTokens, signal };

  if (target.provider === 'groq') {
    return await groqProvider.callStream(target.modelId, messages, systemPrompt, onChunk, imageDataUris, options);
  }

  if (target.provider === 'gemini') {
    return await geminiProvider.callStream(target.modelId, messages, systemPrompt, onChunk, imageDataUris, options);
  }

  try {
    return await deepseekProvider.callStream(target.modelId, messages, systemPrompt, onChunk, options);
  } catch (error) {
    console.warn(`[ModelRouter Fallback] Proveedor primario Stream falló (${error.message}). Reintentando con Gemini Flash-Lite...`);
    try {
      return await geminiProvider.callStream('gemini-flash-lite-latest', messages, systemPrompt, onChunk, imageDataUris, options);
    } catch (geminiError) {
      console.warn(`[ModelRouter Fallback] Gemini Stream falló. Reintentando con Groq Eco...`);
      return await groqProvider.callStream(ECO_MODELS.text, messages, systemPrompt, onChunk, imageDataUris, options);
    }
  }
}

module.exports = {
  routeMessage,
  routeMessageStream,
  getEffectiveModel,
};

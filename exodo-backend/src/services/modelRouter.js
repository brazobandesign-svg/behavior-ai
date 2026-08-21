'use strict';

const { ALIBABA_CONFIG, PLAN_CONFIG, MODEL_MAP } = require('../config/models');
const alibabaProvider = require('./providers/alibaba');
const {
  logInternalGatewayError,
  isClientAbortError,
  USER_FACING_ERROR_MESSAGE,
} = require('./errorSanitizer');

/**
 * ============================================================================
 * MATRIZ DE ENRUTAMIENTO ALIBABA CLOUD MODEL STUDIO (DASHSCOPE) FREE TIER
 * ============================================================================
 */

function sanitizedErrorResult() {
  return { text: '', error: true, message: USER_FACING_ERROR_MESSAGE };
}

function getExecutionChain(plan, intent, modelOverride, imageDataUris, taskType) {
  const isPro = (plan === 'pro' || plan === 'hazak');
  const hasImages = imageDataUris && imageDataUris.length > 0;

  // A. Visión / Multimodal: Forzar qwen-vl-max como primario absoluto si hay imágenes
  if (hasImages) {
    return [
      'qwen-vl-max',
      'qwen3.5-omni-plus',
      'qwen3-vl-plus',
    ];
  }

  // B. Override explícito del cliente
  if (modelOverride) {
    const override = String(modelOverride).toLowerCase();
    if (override.includes('thinking') || override.includes('reasoner') || override.includes('235b')) {
      return [
        ALIBABA_CONFIG.models.hazakReasoner,
        ALIBABA_CONFIG.models.hazakReasonerFallback,
        ALIBABA_CONFIG.models.hazakPrimary,
      ];
    }
    if (override.includes('max')) {
      return [
        ALIBABA_CONFIG.models.hazakPrimary,
        ALIBABA_CONFIG.models.hazakFallback,
        ALIBABA_CONFIG.models.genesisSimple,
      ];
    }
    if (override.includes('flash') || override.includes('fast')) {
      return [
        ALIBABA_CONFIG.models.genesisSimple,
        ALIBABA_CONFIG.models.genesisSimpleFallback,
        ALIBABA_CONFIG.models.hazakPrimary,
      ];
    }
    if (override.includes('qwq')) {
      return [
        ALIBABA_CONFIG.models.hazakReasonerFallback,
        ALIBABA_CONFIG.models.hazakReasoner,
        ALIBABA_CONFIG.models.hazakPrimary,
      ];
    }
  }

  // C. Plan Pro (Hazak)
  if (isPro) {
    if (intent === 'RAZONAMIENTO' || taskType === 'reasoning' || taskType === 'code_analysis') {
      return [
        ALIBABA_CONFIG.models.hazakReasoner,          // qwen3-235b-a22b-thinking-2507
        ALIBABA_CONFIG.models.hazakReasonerFallback,  // qwq-plus
        ALIBABA_CONFIG.models.hazakFallback,          // deepseek-v3.2
        ALIBABA_CONFIG.models.hazakPrimary,           // qwen3.7-max-2026-06-08
      ];
    }
    return [
      ALIBABA_CONFIG.models.hazakPrimary,             // qwen3.7-max-2026-06-08
      ALIBABA_CONFIG.models.hazakFallback,            // deepseek-v3.2
      ALIBABA_CONFIG.models.hazakReasoner,            // qwen3-235b-a22b-thinking-2507
      ALIBABA_CONFIG.models.genesisSimple,            // qwen3.7-flash
    ];
  }

  // D. Plan Free (Genesis G1.1)
  if (intent === 'REDACCION' || taskType === 'writing') {
    return [
      ALIBABA_CONFIG.models.genesisRedaccion,         // qwen3.6-plus
      ALIBABA_CONFIG.models.genesisRedaccionFallback, // qwen3.5-plus
      ALIBABA_CONFIG.models.genesisSimple,           // qwen3.7-flash
    ];
  }

  if (intent === 'RAZONAMIENTO' || taskType === 'reasoning') {
    return [
      ALIBABA_CONFIG.models.genesisReasoner,         // qwen3.7-flash
      ALIBABA_CONFIG.models.genesisReasonerFallback, // qwen3.6-27b
      ALIBABA_CONFIG.models.genesisSimpleFallback,   // qwen3.6-plus
    ];
  }

  return [
    ALIBABA_CONFIG.models.genesisSimple,             // qwen3.7-flash
    ALIBABA_CONFIG.models.genesisSimpleFallback,     // qwen3.6-plus
    ALIBABA_CONFIG.models.genesisRedaccionFallback,  // qwen3.5-plus
  ];
}

function getEffectiveModel(plan, intent, modelOverride, imageDataUris, taskType) {
  const chain = getExecutionChain(plan, intent, modelOverride, imageDataUris, taskType);
  return {
    provider: 'alibaba',
    modelId: chain[0],
    fallbackChain: chain,
    isEco: false,
    maxTokens: (plan === 'pro' || plan === 'hazak') ? 8192 : 4096,
  };
}

/**
 * Llamada estándar con iteración estricta a través de la cadena Alibaba DashScope.
 */
async function routeMessage(plan, intent, messages, systemPrompt, modelOverride, imageDataUris, taskType, isDegraded = false, isGuest = false, signal = null) {
  const chain = getExecutionChain(plan, intent, modelOverride, imageDataUris, taskType);
  const options = {
    max_tokens: (plan === 'pro' || plan === 'hazak') ? 8192 : 4096,
    signal,
    imageDataUris: Array.isArray(imageDataUris) ? imageDataUris : [],
  };

  let lastError = null;
  // No-stream: timeout total holgado (por debajo del timeout de 60s del client
  // OpenAI) para que el error local gane la carrera y loguee contexto propio.
  const MODEL_TIMEOUT_MS = 55000;

  for (let i = 0; i < chain.length; i++) {
    const modelId = chain[i];
    try {
      if (i > 0) {
        // Async logging: no bloquea el event loop
        setImmediate(() => console.warn(`[ModelRouter Fallback] Intentando con modelo Alibaba (${i + 1}/${chain.length}): ${modelId}...`));
      }

      // Timeout por modelo para fail-fast
      const result = await Promise.race([
        alibabaProvider.call(modelId, messages, systemPrompt, options),
        new Promise((_, reject) =>
          setTimeout(() => reject(new Error(`Model timeout after ${MODEL_TIMEOUT_MS}ms`)), MODEL_TIMEOUT_MS)
        )
      ]);

      return result;
    } catch (err) {
      if (isClientAbortError(err)) throw err;
      lastError = err;
      // Async error logging: no bloquea el hot path
      setImmediate(() => logInternalGatewayError(err, { provider: 'alibaba', model: modelId, phase: `call-chain-step-${i + 1}` }));
    }
  }

  if (lastError && isClientAbortError(lastError)) throw lastError;
  logInternalGatewayError(lastError || new Error('ALL_ALIBABA_MODELS_FAILED'), { provider: 'alibaba', phase: 'call-chain-exhausted' });
  return sanitizedErrorResult();
}

/**
 * Llamada Streaming SSE con iteración estricta a través de la cadena Alibaba DashScope.
 *
 * FIX TTFT (2026-08-20): el race anterior mataba el stream COMPLETO a los 10s
 * (prometía fail-fast pero medía la duración total de la respuesta). Cualquier
 * generación >10s thrasheaba entre modelos y terminaba en error sanitizado.
 * Ahora el timeout de 5s aplica SOLO al time-to-first-token: al llegar el
 * primer chunk se limpia el timer y el stream fluye sin interrupción hasta
 * completarse. Si el TTFT expira, se aborta el intento zombi (señal enlazada
 * a la del cliente) y se salta al siguiente modelo de la cadena.
 */
async function routeMessageStream(plan, intent, messages, systemPrompt, onChunk, modelOverride, imageDataUris, taskType, isDegraded = false, isGuest = false, signal = null) {
  const chain = getExecutionChain(plan, intent, modelOverride, imageDataUris, taskType);
  // Vision: el payload multimodal (imágenes base64) alarga el TTFT de qwen-vl
  // (~1.5-3.0s en carga normal, más con imágenes grandes). 15s evita abortar
  // intentos sanos y thrashear la cadena de fallback.
  const hasImages = Array.isArray(imageDataUris) && imageDataUris.length > 0;
  const TTFT_TIMEOUT_MS = hasImages ? 15000 : 5000;

  let lastError = null;

  for (let i = 0; i < chain.length; i++) {
    const modelId = chain[i];

    // Señal por intento, enlazada a la del cliente: permite abortar el stream
    // upstream si el TTFT expira sin duplicar desconexiones del usuario final.
    const attemptCtrl = new AbortController();
    const onOuterAbort = () => attemptCtrl.abort();
    if (signal) {
      if (signal.aborted) attemptCtrl.abort();
      else signal.addEventListener('abort', onOuterAbort, { once: true });
    }

    const attemptOptions = {
      max_tokens: (plan === 'pro' || plan === 'hazak') ? 8192 : 4096,
      signal: attemptCtrl.signal,
      imageDataUris: Array.isArray(imageDataUris) ? imageDataUris : [],
    };

    let ttftTimer = null;
    try {
      if (i > 0) {
        // Async logging: no bloquea el event loop
        setImmediate(() => console.warn(`[ModelRouter Fallback] Intentando streaming con modelo Alibaba (${i + 1}/${chain.length}): ${modelId}...`));
      }

      const ttftTimeout = new Promise((_, reject) => {
        ttftTimer = setTimeout(() => {
          attemptCtrl.abort(); // matar el intento zombi antes de saltar de modelo
          reject(new Error(`TTFT timeout after ${TTFT_TIMEOUT_MS}ms sin primer chunk (${modelId})`));
        }, TTFT_TIMEOUT_MS);
      });

      // onChunk con guard: limpia el timer TTFT en el primer chunk y a partir
      // de ahí reenvía cada delta 1:1, sin buffering ni throttling.
      let firstChunkSeen = false;
      const guardedOnChunk = (chunk) => {
        if (!firstChunkSeen) {
          firstChunkSeen = true;
          if (ttftTimer) { clearTimeout(ttftTimer); ttftTimer = null; }
        }
        if (typeof onChunk === 'function') onChunk(chunk);
      };

      const result = await Promise.race([
        alibabaProvider.callStream(modelId, messages, systemPrompt, guardedOnChunk, attemptOptions),
        ttftTimeout,
      ]);

      return result;
    } catch (err) {
      if (isClientAbortError(err)) throw err;
      lastError = err;
      // Async error logging: no bloquea el hot path
      setImmediate(() => logInternalGatewayError(err, { provider: 'alibaba', model: modelId, phase: `stream-chain-step-${i + 1}` }));
    } finally {
      if (ttftTimer) clearTimeout(ttftTimer);
      if (signal) signal.removeEventListener('abort', onOuterAbort);
    }
  }

  if (lastError && isClientAbortError(lastError)) throw lastError;
  logInternalGatewayError(lastError || new Error('ALL_ALIBABA_MODELS_STREAM_FAILED'), { provider: 'alibaba', phase: 'stream-chain-exhausted' });
  return sanitizedErrorResult();
}

module.exports = {
  routeMessage,
  routeMessageStream,
  getEffectiveModel,
  getExecutionChain,
};

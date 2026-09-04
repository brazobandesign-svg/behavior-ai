'use strict';

const { ALIBABA_CONFIG, PLAN_CONFIG, MODEL_MAP } = require('../config/models');
const alibabaProvider = require('./providers/alibaba');
const {
  logInternalGatewayError,
  isClientAbortError,
  USER_FACING_ERROR_MESSAGE,
  userFacingError,
} = require('./errorSanitizer');

/**
 * ============================================================================
 * MATRIZ DE ENRUTAMIENTO ALIBABA CLOUD MODEL STUDIO (DASHSCOPE) FREE TIER
 * ============================================================================
 */

function sanitizedErrorResult(err = null) {
  const out = err ? userFacingError(err) : { content: USER_FACING_ERROR_MESSAGE, code: 'error' };
  return { text: '', error: true, message: out.content, code: out.code };
}

// DOCTRINA 30-ago: matriz Free/Pro lista para el lanzamiento (30-sept-2026),
// apagada durante la beta. PLAN_ROUTING_ENABLED=true activa la diferenciación:
//   XPi (hazak)    → modelos flagship (max / qwq / coder / vl-max)
//   G1.1 (genesis) → modelos rápidos/eco (flash / plus / vl-plus)
const PLAN_ROUTING_ENABLED = process.env.PLAN_ROUTING_ENABLED === 'true';

function getExecutionChain(plan, intent, modelOverride, imageDataUris, taskType, isGuest = false) {
  const isGuestUser = isGuest || plan === 'guest';
  const hasImages = imageDataUris && imageDataUris.length > 0;

  // 0. Modo Eco Estricto para Invitados ($0.00): modelos flash/eco, sin flagship de pago
  if (isGuestUser) {
    if (hasImages) {
      return [
        ALIBABA_CONFIG.models.visionEco || 'qwen3-vl-plus',
        ALIBABA_CONFIG.models.fastPrimary || 'qwen3.7-flash-2026-07-15',
      ];
    }
    return [
      ALIBABA_CONFIG.models.fastPrimary || 'qwen3.7-flash-2026-07-15',
      ALIBABA_CONFIG.models.textFallback,
    ];
  }

  // 1. Visión e Imágenes
  if (hasImages) {
    if (PLAN_ROUTING_ENABLED && plan === 'genesis') {
      return [ALIBABA_CONFIG.models.visionEco || 'qwen3-vl-plus', ALIBABA_CONFIG.models.visionPrimary];
    }
    return [
      ALIBABA_CONFIG.models.visionPrimary, // qwen-vl-max
    ];
  }

  // 2. Override explícito si el cliente lo solicita
  if (modelOverride) {
    const override = String(modelOverride).toLowerCase();
    if (override.includes('qwq') || override.includes('reasoner') || override.includes('thinking')) {
      return [ALIBABA_CONFIG.models.reasonerPrimary];
    }
    if (override.includes('code') || override.includes('coder')) {
      return [ALIBABA_CONFIG.models.coderPrimary];
    }
    if (override.includes('vision') || override.includes('image')) {
      return [ALIBABA_CONFIG.models.visionPrimary];
    }
  }

  // 3. Código y Artefactos (con fallback robusto)
  if (intent === 'CODE' || taskType === 'code' || taskType === 'code_analysis') {
    return [
      ALIBABA_CONFIG.models.coderPrimary, // qwen3-coder-plus-2025-07-22
      ALIBABA_CONFIG.models.textPrimary,  // qwen3.7-max
      ALIBABA_CONFIG.models.textFallback, // qwen3.6-plus
    ];
  }

  // 4. Razonamiento Profundo y Matemáticas (con fallback robusto)
  if (intent === 'RAZONAMIENTO' || taskType === 'reasoning') {
    return [
      ALIBABA_CONFIG.models.reasonerPrimary, // qwq-plus
      ALIBABA_CONFIG.models.textPrimary,     // qwen3.7-max
      ALIBABA_CONFIG.models.textFallback,    // qwen3.6-plus
    ];
  }

  // 5. Conversación Simple, Saludos y Consultas Directas
  if (intent === 'SIMPLE' || taskType === 'simple') {
    if (PLAN_ROUTING_ENABLED && plan === 'genesis') {
      // G1.1: rapidez primero; la cadena de fallback sube a plus si falla.
      return [
        ALIBABA_CONFIG.models.fastPrimary || 'qwen3.7-flash-2026-07-15',
        ALIBABA_CONFIG.models.textFallback,
      ];
    }
    return [
      PLAN_ROUTING_ENABLED
        ? ALIBABA_CONFIG.models.textPrimary // XPi: flagship en todo
        : (ALIBABA_CONFIG.models.fastPrimary || 'qwen3.7-flash-2026-07-15'),
      ALIBABA_CONFIG.models.textPrimary,
    ];
  }

  // 5b. Redacción con matriz activa: XPi flagship, G1.1 plus.
  if (PLAN_ROUTING_ENABLED && plan === 'genesis'
      && (intent === 'REDACCION' || intent === 'DOCUMENTO')) {
    return [
      ALIBABA_CONFIG.models.textFallback,
      ALIBABA_CONFIG.models.fastPrimary || 'qwen3.7-flash-2026-07-15',
    ];
  }

  // 6. Redacción Compleja, Ensayos y Texto Extenso (Máxima Elocuencia)
  return [
    ALIBABA_CONFIG.models.textPrimary,  // qwen3.7-max-2026-05-20
    ALIBABA_CONFIG.models.textFallback, // qwen3.6-plus-2026-04-02
  ];
}

function getEffectiveModel(plan, intent, modelOverride, imageDataUris, taskType, isGuest = false) {
  const chain = getExecutionChain(plan, intent, modelOverride, imageDataUris, taskType, isGuest);
  return {
    provider: 'alibaba',
    modelId: chain[0],
    fallbackChain: chain,
    isEco: isGuest || plan === 'guest',
    maxTokens: 8192,
  };
}

/**
 * Llamada estándar con iteración estricta a través de la cadena Alibaba DashScope.
 */
async function routeMessage(plan, intent, messages, systemPrompt, modelOverride, imageDataUris, taskType, isDegraded = false, isGuest = false, signal = null, incognito = false) {
  const chain = getExecutionChain(plan, intent, modelOverride, imageDataUris, taskType, isGuest);
  const options = {
    max_tokens: 8192,
    signal,
    imageDataUris: Array.isArray(imageDataUris) ? imageDataUris : [],
    incognito: !!incognito,
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
      setImmediate(() => logInternalGatewayError(err, { provider: 'alibaba', model: modelId, phase: `call-chain-step-${i + 1}`, incognito: !!incognito }));
    }
  }

  if (lastError && isClientAbortError(lastError)) throw lastError;
  logInternalGatewayError(lastError || new Error('ALL_ALIBABA_MODELS_FAILED'), { provider: 'alibaba', phase: 'call-chain-exhausted', incognito: !!incognito });
  return sanitizedErrorResult(lastError);
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
async function routeMessageStream(plan, intent, messages, systemPrompt, onChunk, modelOverride, imageDataUris, taskType, isDegraded = false, isGuest = false, signal = null, incognito = false) {
  const chain = getExecutionChain(plan, intent, modelOverride, imageDataUris, taskType, isGuest);
  // TTFT timeout adaptativo: modelos de razonamiento (qwq-plus), visión y código
  // requieren margen para pensar/procesar tokens iniciales sin abortar prematuramente.
  const hasImages = Array.isArray(imageDataUris) && imageDataUris.length > 0;
  const isHeavyTask = hasImages || intent === 'RAZONAMIENTO' || intent === 'CODE' || taskType === 'reasoning' || taskType === 'code';
  const TTFT_TIMEOUT_MS = isHeavyTask ? 20000 : 12000;

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
      max_tokens: 8192,
      signal: attemptCtrl.signal,
      imageDataUris: Array.isArray(imageDataUris) ? imageDataUris : [],
      incognito: !!incognito,
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
      setImmediate(() => logInternalGatewayError(err, { provider: 'alibaba', model: modelId, phase: `stream-chain-step-${i + 1}`, incognito: !!incognito }));
    } finally {
      if (ttftTimer) clearTimeout(ttftTimer);
      if (signal) signal.removeEventListener('abort', onOuterAbort);
    }
  }

  if (lastError && isClientAbortError(lastError)) throw lastError;
  logInternalGatewayError(lastError || new Error('ALL_ALIBABA_MODELS_STREAM_FAILED'), { provider: 'alibaba', phase: 'stream-chain-exhausted', incognito: !!incognito });
  return sanitizedErrorResult(lastError);
}

module.exports = {
  routeMessage,
  routeMessageStream,
  getEffectiveModel,
  getExecutionChain,
};

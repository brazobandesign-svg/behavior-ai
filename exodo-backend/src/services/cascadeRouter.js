'use strict';

/**
 * src/services/cascadeRouter.js
 *
 * Arquitectura Gateway Modular para la Cascada Multi-Proveedor Original:
 *   OpenAI -> Google (Gemini) -> DeepSeek -> Groq (Eco)
 *
 * DOCTRINA DE PLATAFORMA:
 * - Pro (XPi): OpenAI -> Google Gemini -> DeepSeek -> Groq Eco
 * - Free (G1.1): Google Gemini -> DeepSeek -> Groq Eco
 * - Degradado (cuota agotada): Groq Eco ($0.00) directo
 * - Guest e Incógnito: Groq Eco ($0.00) directo
 * - Visión: Google Gemini / Groq Vision / OpenAI Vision
 *
 * Por defecto permanece INACTIVO (CASCADE_ENABLED === 'false').
 * Alibaba DashScope sigue como driver principal en modelRouter.js.
 */

const openaiProvider = require('./providers/openaiProvider');
const geminiProvider = require('./providers/geminiProvider');
const deepseekProvider = require('./providers/deepseekProvider');
const groqProvider = require('./providers/groqProvider');

const {
  logInternalGatewayError,
  isClientAbortError,
  USER_FACING_ERROR_MESSAGE,
  userFacingError,
} = require('./errorSanitizer');

const CASCADE_ENABLED = process.env.CASCADE_ENABLED === 'true';

const PROVIDER_MAP = {
  openai: openaiProvider,
  gemini: geminiProvider,
  deepseek: deepseekProvider,
  groq: groqProvider,
};

function getCascadeChain(plan, intent, modelOverride, imageDataUris, taskType, isGuest = false, isDegraded = false) {
  const isGuestUser = isGuest || plan === 'guest';
  const hasImages = imageDataUris && imageDataUris.length > 0;
  const isPro = (plan === 'pro' || plan === 'hazak');

  // 1. Invitados o Usuarios con cuota diaria agotada (Degradados): Groq Eco directo ($0.00)
  if (isGuestUser || isDegraded) {
    if (hasImages) {
      return [
        { provider: 'groq', model: 'qwen/qwen3.6-27b', isEco: true },
        { provider: 'gemini', model: 'gemini-flash-lite-latest', isEco: true },
      ];
    }
    return [
      { provider: 'groq', model: 'llama-3.3-70b-versatile', isEco: true },
    ];
  }

  // 2. Visión Multimodal (Fotos, diagramas, OCR)
  if (hasImages) {
    return [
      { provider: 'gemini', model: 'gemini-flash-lite-latest', isEco: false },
      { provider: 'groq', model: 'qwen/qwen3.6-27b', isEco: true },
      { provider: 'openai', model: 'gpt-4o', isEco: false },
    ];
  }

  // 3. Razonamiento Profundo y Código
  if (intent === 'RAZONAMIENTO' || intent === 'CODE' || taskType === 'reasoning' || taskType === 'code') {
    if (isPro) {
      return [
        { provider: 'openai', model: 'o3-mini', isEco: false },
        { provider: 'deepseek', model: 'deepseek-reasoner', isEco: false },
        { provider: 'gemini', model: 'gemini-flash-lite-latest', isEco: false },
        { provider: 'groq', model: 'llama-3.3-70b-versatile', isEco: true },
      ];
    }
    // Free: DeepSeek Reasoner -> Gemini -> Groq
    return [
      { provider: 'deepseek', model: 'deepseek-reasoner', isEco: false },
      { provider: 'gemini', model: 'gemini-flash-lite-latest', isEco: false },
      { provider: 'groq', model: 'llama-3.3-70b-versatile', isEco: true },
    ];
  }

  // 4. Pro (XPi): OpenAI -> Google -> DeepSeek -> Groq Eco
  if (isPro) {
    return [
      { provider: 'openai', model: 'gpt-4o', isEco: false },
      { provider: 'gemini', model: 'gemini-flash-lite-latest', isEco: false },
      { provider: 'deepseek', model: 'deepseek-chat', isEco: false },
      { provider: 'groq', model: 'llama-3.3-70b-versatile', isEco: true },
    ];
  }

  // 5. Free (G1.1): Google Gemini -> DeepSeek -> Groq Eco
  return [
    { provider: 'gemini', model: 'gemini-flash-lite-latest', isEco: false },
    { provider: 'deepseek', model: 'deepseek-chat', isEco: false },
    { provider: 'groq', model: 'llama-3.3-70b-versatile', isEco: true },
  ];
}

async function routeCascadeStream(plan, intent, messages, systemPrompt, onChunk, modelOverride, imageDataUris, taskType, isDegraded = false, isGuest = false, signal = null, incognito = false) {
  const chain = getCascadeChain(plan, intent, modelOverride, imageDataUris, taskType, isGuest, isDegraded);
  const TTFT_TIMEOUT_MS = (intent === 'RAZONAMIENTO' || intent === 'CODE') ? 20000 : 12000;

  let lastError = null;

  for (let i = 0; i < chain.length; i++) {
    const step = chain[i];
    const providerImpl = PROVIDER_MAP[step.provider];
    if (!providerImpl) continue;

    const attemptCtrl = new AbortController();
    const onOuterAbort = () => attemptCtrl.abort();
    if (signal) {
      if (signal.aborted) attemptCtrl.abort();
      else signal.addEventListener('abort', onOuterAbort, { once: true });
    }

    const attemptOptions = {
      max_tokens: 4096,
      signal: attemptCtrl.signal,
      imageDataUris: Array.isArray(imageDataUris) ? imageDataUris : [],
      incognito: !!incognito,
    };

    let ttftTimer = null;
    try {
      if (i > 0) {
        setImmediate(() => console.warn(`[Cascade Fallback] Saltando a paso ${i + 1}/${chain.length}: ${step.provider} (${step.model})...`));
      }

      const ttftTimeout = new Promise((_, reject) => {
        ttftTimer = setTimeout(() => {
          attemptCtrl.abort();
          reject(new Error(`TTFT timeout after ${TTFT_TIMEOUT_MS}ms (${step.provider}/${step.model})`));
        }, TTFT_TIMEOUT_MS);
      });

      let firstChunkSeen = false;
      const guardedOnChunk = (chunk) => {
        if (!firstChunkSeen) {
          firstChunkSeen = true;
          if (ttftTimer) { clearTimeout(ttftTimer); ttftTimer = null; }
        }
        if (typeof onChunk === 'function') onChunk(chunk);
      };

      const result = await Promise.race([
        providerImpl.callStream(step.model, messages, systemPrompt, guardedOnChunk, attemptOptions),
        ttftTimeout,
      ]);

      return result;
    } catch (err) {
      if (isClientAbortError(err)) throw err;
      lastError = err;
      setImmediate(() => logInternalGatewayError(err, { provider: step.provider, model: step.model, phase: `cascade-step-${i + 1}`, incognito: !!incognito }));
    } finally {
      if (ttftTimer) clearTimeout(ttftTimer);
      if (signal) signal.removeEventListener('abort', onOuterAbort);
    }
  }

  if (lastError && isClientAbortError(lastError)) throw lastError;
  logInternalGatewayError(lastError || new Error('ALL_CASCADE_MODELS_FAILED'), { provider: 'cascade', phase: 'cascade-exhausted', incognito: !!incognito });
  const out = lastError ? userFacingError(lastError) : { content: USER_FACING_ERROR_MESSAGE, code: 'error' };
  return { text: '', error: true, message: out.content, code: out.code };
}

module.exports = {
  CASCADE_ENABLED,
  getCascadeChain,
  routeCascadeStream,
};

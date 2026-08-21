'use strict';

const { OpenAI } = require('openai');
const { ALIBABA_CONFIG } = require('../../config/models');
const { logInternalGatewayError, wrapProviderError } = require('../errorSanitizer');

/**
 * Provider: Alibaba Cloud Model Studio (DashScope) OpenAI-Compatible Gateway
 *
 * Base URL: https://dashscope-intl.aliyuncs.com/compatible-mode/v1
 * Models: Qwen 3.7 Max/Flash, Qwen 3.6/3.5 Plus, Qwen3 Thinking, Qwen VL Max, QwQ Plus, DeepSeek V3.2
 */

function resolveModelName(modelId) {
  if (!modelId) return ALIBABA_CONFIG.models.hazakPrimary;
  const m = String(modelId).trim().toLowerCase();

  if (m === 'deepseek-chat' || m === 'genesis' || m === 'g1.1' || m === 'flash' || m === 'simple') {
    return ALIBABA_CONFIG.models.genesisSimple; // qwen3.7-flash
  }
  if (m === 'deepseek-reasoner' || m === 'hazak' || m === 'j1.9' || m === 'pro' || m === 'thinking' || m === 'reasoner') {
    return ALIBABA_CONFIG.models.hazakReasoner; // qwen3-235b-a22b-thinking-2507
  }
  if (m === 'max' || m === 'primary') {
    return ALIBABA_CONFIG.models.hazakPrimary; // qwen3.7-max-2026-06-08
  }
  if (m === 'redaccion') {
    return ALIBABA_CONFIG.models.genesisRedaccion; // qwen3.6-plus
  }
  if (m === 'vision' || m === 'vl' || m === 'omni' || m === 'qwen-vl-max') {
    return 'qwen-vl-max'; // qwen-vl-max
  }
  if (m === 'qwq') {
    return ALIBABA_CONFIG.models.hazakReasonerFallback; // qwq-plus
  }

  return modelId;
}

function getClient() {
  const apiKey = process.env.DASHSCOPE_API_KEY ||
                 process.env.ALIBABA_API_KEY ||
                 process.env.ALIBABA_FREE_KEY ||
                 ALIBABA_CONFIG.apiKey;

  const baseURL = process.env.ALIBABA_BASE_URL ||
                  ALIBABA_CONFIG.baseURL ||
                  'https://dashscope-intl.aliyuncs.com/compatible-mode/v1';

  return new OpenAI({
    baseURL,
    apiKey,
    timeout: 60000,
  });
}

function buildMessages(messages, systemPrompt, imageDataUris = []) {
  const formatted = [];

  if (systemPrompt && systemPrompt.trim()) {
    formatted.push({
      role: 'system',
      content: systemPrompt.trim(),
    });
  }

  const images = Array.isArray(imageDataUris) ? imageDataUris : [];

  for (let i = 0; i < messages.length; i++) {
    const msg = messages[i];
    const isLastUserMsg = (i === messages.length - 1);

    if (typeof msg === 'string') {
      if (isLastUserMsg && images.length > 0) {
        const userContent = [
          { type: 'text', text: msg || 'Por favor analiza e inspecciona detalladamente esta imagen.' },
          ...images.map((uri) => ({
            type: 'image_url',
            image_url: { url: uri }
          }))
        ];
        formatted.push({ role: 'user', content: userContent });
      } else {
        formatted.push({ role: 'user', content: msg });
      }
    } else if (msg && typeof msg === 'object') {
      if (msg.role === 'user' && isLastUserMsg && images.length > 0) {
        const userContent = [
          { type: 'text', text: msg.content || 'Por favor analiza e inspecciona detalladamente esta imagen.' },
          ...images.map((uri) => ({
            type: 'image_url',
            image_url: { url: uri }
          }))
        ];
        formatted.push({ role: 'user', content: userContent });
      } else {
        formatted.push({
          role: msg.role === 'user' ? 'user' : 'assistant',
          content: msg.content || '',
        });
      }
    }
  }

  return formatted;
}

/**
 * FIX TTFT (2026-08-20): los modelos Qwen híbridos traen thinking ACTIVADO por
 * defecto en DashScope compatible-mode. Eso quema 8-15s generando cadenas de
 * razonamiento ocultas (reasoning_content) ANTES del primer token visible.
 * En las rutas rápidas (flash/plus/max/vl) se desactiva explícitamente con los
 * dos formatos que acepta la API (alias legacy + formato actual). Los modelos
 * reasoning puros (thinking/reasoner/qwq/235b) conservan su comportamiento.
 */
function buildThinkingParams(isReasoning) {
  if (isReasoning) return {};
  return {
    enable_thinking: false,
    thinking: { type: 'disabled' },
  };
}

/**
 * Detecta 400s donde el endpoint rechaza específicamente los params de
 * thinking (modelos antiguos estrictos). Permite un retry defensivo sin ellos.
 */
function isThinkingParamRejection(err) {
  const status = err && (err.status || (err.error && err.error.status));
  if (status !== 400) return false;
  const msg = String(err.message || '');
  return /think|enable_thinking|invalid.*param|par[aá]metro/i.test(msg);
}

/**
 * Llamada síncrona sin streaming
 */
async function call(modelId, messages, systemPrompt, options = {}) {
  const client = getClient();
  const targetModel = resolveModelName(modelId);
  const opts = (options && typeof options === 'object' && !Array.isArray(options)) ? options : {};
  const imageDataUris = Array.isArray(options) ? options : (opts.imageDataUris || []);
  const formattedMessages = buildMessages(messages, systemPrompt, imageDataUris);

  const maxTokens = opts.max_tokens || 4096;
  const isReasoning = targetModel.includes('thinking') ||
                      targetModel.includes('reasoner') ||
                      targetModel.includes('qwq') ||
                      targetModel.includes('235b');

  const baseParams = {
    model: targetModel,
    messages: formattedMessages,
    max_tokens: maxTokens,
    temperature: isReasoning ? undefined : 0.7,
  };

  let response;
  try {
    response = await client.chat.completions.create(
      { ...baseParams, ...buildThinkingParams(isReasoning) },
      { signal: opts.signal || null }
    );
  } catch (err) {
    if (isThinkingParamRejection(err)) {
      // Endpoint estricto que no tolera los params de thinking: retry limpio.
      response = await client.chat.completions.create(baseParams, { signal: opts.signal || null });
    } else {
      console.error(`[alibaba] Call error con modelo ${targetModel}:`, err.message);
      throw wrapProviderError(err, targetModel, 'call-request');
    }
  }

  const choice = response.choices && response.choices[0];
  const text = choice && choice.message ? (choice.message.content || '') : '';
  const reasoning = choice && choice.message ? choice.message.reasoning_content : null;

  return {
    text: text || '',
    reasoning: reasoning || null,
    tokensInput: response.usage?.prompt_tokens || 0,
    tokensOutput: response.usage?.completion_tokens || 0,
    model: targetModel,
    provider: 'alibaba',
  };
}

/**
 * Llamada con Streaming SSE
 */
async function callStream(modelId, messages, systemPrompt, onChunk, options = {}) {
  const client = getClient();
  const targetModel = resolveModelName(modelId);
  const opts = (options && typeof options === 'object' && !Array.isArray(options)) ? options : {};
  const imageDataUris = Array.isArray(options) ? options : (opts.imageDataUris || []);
  const formattedMessages = buildMessages(messages, systemPrompt, imageDataUris);

  const maxTokens = opts.max_tokens || 4096;
  const isReasoning = targetModel.includes('thinking') ||
                      targetModel.includes('reasoner') ||
                      targetModel.includes('qwq') ||
                      targetModel.includes('235b');

  const baseParams = {
    model: targetModel,
    messages: formattedMessages,
    max_tokens: maxTokens,
    temperature: isReasoning ? undefined : 0.7,
    stream: true,
    stream_options: { include_usage: true },
  };

  let stream;
  try {
    stream = await client.chat.completions.create(
      { ...baseParams, ...buildThinkingParams(isReasoning) },
      { signal: opts.signal || null }
    );
  } catch (err) {
    if (isThinkingParamRejection(err)) {
      // Endpoint estricto que no tolera los params de thinking: retry limpio.
      stream = await client.chat.completions.create(baseParams, { signal: opts.signal || null });
    } else {
      console.error(`[alibaba] Stream init error con modelo ${targetModel}:`, err.message);
      throw wrapProviderError(err, targetModel, 'call-stream-init');
    }
  }

  let fullText = '';
  let fullReasoning = '';
  let tokensInput = 0;
  let tokensOutput = 0;

  try {
    for await (const chunk of stream) {
      if (opts.signal && opts.signal.aborted) {
        break;
      }

      const delta = chunk.choices && chunk.choices[0] && chunk.choices[0].delta;
      const content = delta ? (delta.content || '') : '';
      const reasoning = delta ? (delta.reasoning_content || '') : '';

      if (chunk.usage) {
        tokensInput = chunk.usage.prompt_tokens || tokensInput;
        tokensOutput = chunk.usage.completion_tokens || tokensOutput;
      }

      if (reasoning) {
        fullReasoning += reasoning;
      }

      if (content && content.length > 0) {
        fullText += content;
        if (typeof onChunk === 'function') {
          onChunk(content);
        }
      }
    }
  } catch (err) {
    if (opts.signal && opts.signal.aborted) {
      return {
        text: fullText,
        reasoning: fullReasoning || null,
        tokensInput,
        tokensOutput,
        model: targetModel,
        provider: 'alibaba',
        aborted: true,
      };
    }
    console.error(`[alibaba] Stream iteration error con modelo ${targetModel}:`, err.message);
    throw wrapProviderError(err, targetModel, 'call-stream-iteration');
  }

  return {
    text: fullText,
    reasoning: fullReasoning || null,
    tokensInput: tokensInput || Math.ceil(fullText.length / 3.5),
    tokensOutput: tokensOutput || Math.ceil(fullText.length / 3.5),
    model: targetModel,
    provider: 'alibaba',
  };
}

module.exports = {
  call,
  callStream,
  resolveModelName,
  getClient,
};

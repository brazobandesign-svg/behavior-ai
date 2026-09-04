'use strict';

const { OpenAI } = require('openai');
const { SYSTEM_PROMPT } = require('../../config/systemPrompt');
const { logInternalGatewayError } = require('../errorSanitizer');

let _client = null;
let _cachedKey = null;

function getClient() {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    throw new Error('OPENAI_API_KEY no configurada en el entorno');
  }
  if (_client && _cachedKey === apiKey) {
    return _client;
  }
  _client = new OpenAI({
    apiKey,
    timeout: 45000,
  });
  _cachedKey = apiKey;
  return _client;
}

function buildMessages(messages, systemPrompt, imageDataUris = []) {
  const formatted = [];
  const effectivePrompt = (systemPrompt && typeof systemPrompt === 'string' && systemPrompt.trim())
    ? systemPrompt.trim()
    : SYSTEM_PROMPT;

  if (effectivePrompt) {
    formatted.push({
      role: 'system',
      content: effectivePrompt,
    });
  }

  const images = Array.isArray(imageDataUris) ? imageDataUris : [];

  for (let i = 0; i < messages.length; i++) {
    const msg = messages[i];
    const isLast = (i === messages.length - 1);

    if (isLast && msg.role === 'user' && images.length > 0) {
      const contentParts = [
        { type: 'text', text: msg.content || 'Por favor analiza esta imagen con detalle.' }
      ];
      for (const uri of images) {
        contentParts.push({
          type: 'image_url',
          image_url: { url: uri },
        });
      }
      formatted.push({ role: 'user', content: contentParts });
    } else if (msg && msg.role && msg.content) {
      formatted.push({
        role: msg.role === 'assistant' ? 'assistant' : 'user',
        content: typeof msg.content === 'string' ? msg.content : JSON.stringify(msg.content),
      });
    }
  }

  return formatted;
}

function wrapProviderError(err, modelId, phase) {
  logInternalGatewayError(err, { provider: 'openai', model: modelId, phase });
  const normalized = new Error('UPSTREAM_PROVIDER_ERROR');
  normalized.status = typeof err?.status === 'number' ? err.status : undefined;
  normalized.provider = 'openai';
  normalized.isUpstream = true;
  return normalized;
}

async function call(modelId, messages, systemPrompt, maybeImagesOrOptions = [], maybeOptions = {}) {
  const isArr = Array.isArray(maybeImagesOrOptions);
  const imageDataUris = isArr ? maybeImagesOrOptions : (maybeImagesOrOptions?.imageDataUris || []);
  const options = isArr ? (maybeOptions || {}) : (maybeImagesOrOptions || {});

  const client = getClient();
  const targetModel = modelId || 'gpt-4o';
  const formattedMessages = buildMessages(messages, systemPrompt, imageDataUris);
  const maxTokens = options.max_tokens || 4096;

  let response;
  try {
    response = await client.chat.completions.create({
      model: targetModel,
      messages: formattedMessages,
      max_tokens: maxTokens,
      temperature: 0.7,
    }, { signal: options.signal || null });
  } catch (err) {
    throw wrapProviderError(err, targetModel, 'call-request');
  }

  const choice = response.choices && response.choices[0];
  const text = choice && choice.message ? choice.message.content : '';

  return {
    text: text || '',
    tokensInput: response.usage?.prompt_tokens || 0,
    tokensOutput: response.usage?.completion_tokens || 0,
    model: targetModel,
    provider: 'openai',
    isEco: false,
  };
}

async function callStream(modelId, messages, systemPrompt, onChunk, maybeImagesOrOptions = [], maybeOptions = {}) {
  const isArr = Array.isArray(maybeImagesOrOptions);
  const imageDataUris = isArr ? maybeImagesOrOptions : (maybeImagesOrOptions?.imageDataUris || []);
  const options = isArr ? (maybeOptions || {}) : (maybeImagesOrOptions || {});

  const client = getClient();
  const targetModel = modelId || 'gpt-4o';
  const formattedMessages = buildMessages(messages, systemPrompt, imageDataUris);
  const maxTokens = options.max_tokens || 4096;

  let stream;
  try {
    stream = await client.chat.completions.create({
      model: targetModel,
      messages: formattedMessages,
      max_tokens: maxTokens,
      temperature: 0.7,
      stream: true,
      stream_options: { include_usage: true },
    }, { signal: options.signal || null });
  } catch (err) {
    throw wrapProviderError(err, targetModel, 'stream-open');
  }

  let fullText = '';
  let usage = { prompt_tokens: 0, completion_tokens: 0 };

  try {
    for await (const chunk of stream) {
      if (chunk.usage) {
        usage = chunk.usage;
      }
      const delta = chunk.choices && chunk.choices[0]?.delta?.content;
      if (delta) {
        fullText += delta;
        if (typeof onChunk === 'function') {
          onChunk(delta);
        }
      }
    }
  } catch (err) {
    throw wrapProviderError(err, targetModel, 'stream-iteration');
  }

  return {
    text: fullText,
    tokensInput: usage.prompt_tokens || 0,
    tokensOutput: usage.completion_tokens || 0,
    model: targetModel,
    provider: 'openai',
    isEco: false,
  };
}

module.exports = {
  call,
  callStream,
  getClient,
};

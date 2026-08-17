const { OpenAI } = require('openai');

/**
 * Provider: DeepSeek V4 (api.deepseek.com)
 * 
 * Modelos soportados:
 * - deepseek-chat (DeepSeek V3 / Flash): Texto, código, conversación ágil.
 * - deepseek-reasoner (DeepSeek R1 / Pro): Razonamiento analítico profundo (Thinking Mode).
 * 
 * Guardrails y Optimización de Costos:
 * 1. Prefijo fijo para Context Caching: El System Prompt se ubica al inicio de messages.
 * 2. max_tokens acotado (1500 - 2000) para evitar consumo descontrolado de output tokens.
 */

function getClient() {
  const apiKey = process.env.DEEPSEEK_API_KEY;
  if (!apiKey) {
    throw new Error('DEEPSEEK_API_KEY no configurada en el entorno');
  }

  return new OpenAI({
    baseURL: 'https://api.deepseek.com',
    apiKey: apiKey,
    timeout: 30000, // 30s timeout
  });
}

function buildMessages(messages, systemPrompt) {
  const formatted = [];

  // Optimización de Prefijo Cache: System prompt siempre al inicio
  if (systemPrompt && systemPrompt.trim()) {
    formatted.push({
      role: 'system',
      content: systemPrompt.trim(),
    });
  }

  for (const m of messages) {
    if (m && m.role && m.content) {
      formatted.push({
        role: m.role === 'assistant' ? 'assistant' : 'user',
        content: typeof m.content === 'string' ? m.content : JSON.stringify(m.content),
      });
    }
  }

  return formatted;
}

/**
 * Llamada estándar (no streaming)
 */
async function call(modelId, messages, systemPrompt, options = {}) {
  const client = getClient();
  const targetModel = modelId === 'deepseek-reasoner' ? 'deepseek-reasoner' : 'deepseek-chat';
  const formattedMessages = buildMessages(messages, systemPrompt);

  const maxTokens = options.max_tokens || 2000;

  const response = await client.chat.completions.create({
    model: targetModel,
    messages: formattedMessages,
    max_tokens: maxTokens,
    temperature: targetModel === 'deepseek-reasoner' ? undefined : 0.7,
  });

  const choice = response.choices && response.choices[0];
  const text = choice && choice.message ? choice.message.content : '';
  const reasoning = choice && choice.message ? choice.message.reasoning_content : null;

  return {
    text: text || '',
    reasoning: reasoning || null,
    tokensInput: response.usage?.prompt_tokens || 0,
    tokensOutput: response.usage?.completion_tokens || 0,
    model: targetModel,
    provider: 'deepseek',
  };
}

/**
 * Llamada con Streaming SSE
 */
async function callStream(modelId, messages, systemPrompt, onChunk, options = {}) {
  const client = getClient();
  const targetModel = modelId === 'deepseek-reasoner' ? 'deepseek-reasoner' : 'deepseek-chat';
  const formattedMessages = buildMessages(messages, systemPrompt);

  const maxTokens = options.max_tokens || 2000;

  const stream = await client.chat.completions.create({
    model: targetModel,
    messages: formattedMessages,
    max_tokens: maxTokens,
    stream: true,
    temperature: targetModel === 'deepseek-reasoner' ? undefined : 0.7,
  });

  let fullText = '';
  let fullReasoning = '';

  for await (const chunk of stream) {
    const delta = chunk.choices && chunk.choices[0] && chunk.choices[0].delta;
    if (!delta) continue;

    if (delta.reasoning_content) {
      fullReasoning += delta.reasoning_content;
      // Emitir reasoning con tag o estructura si se requiere
    }

    if (delta.content) {
      fullText += delta.content;
      onChunk(delta.content);
    }
  }

  return {
    text: fullText,
    reasoning: fullReasoning || null,
    tokensInput: 0,
    tokensOutput: 0,
    model: targetModel,
    provider: 'deepseek',
  };
}

module.exports = {
  call,
  callStream,
};

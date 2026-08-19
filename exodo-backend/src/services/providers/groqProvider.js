const { OpenAI } = require('openai');

/**
 * Provider: Groq (https://api.groq.com/openai/v1)
 * 
 * Rol en la arquitectura:
 * Motor para cuentas Guest / Invitados y Degradación Eco ($0.00).
 * 
 * Modelos:
 * - Texto: llama-3.3-70b-versatile (Sin restricciones artificiales, max_tokens: 4096).
 * - Visión: qwen/qwen3.6-27b.
 */

function getClient() {
  const apiKey = process.env.GROQ_API_KEY;
  if (!apiKey) {
    throw new Error('GROQ_API_KEY no configurada en el entorno');
  }

  return new OpenAI({
    baseURL: 'https://api.groq.com/openai/v1',
    apiKey: apiKey,
    timeout: 30000,
  });
}

function buildMessages(messages, systemPrompt, imageDataUris = []) {
  const formatted = [];

  // System Prompt limpio y natural (sin inyecciones de brevedad)
  if (systemPrompt && systemPrompt.trim()) {
    formatted.push({
      role: 'system',
      content: systemPrompt.trim(),
    });
  }

  for (let i = 0; i < messages.length; i++) {
    const msg = messages[i];
    const isLast = i === messages.length - 1;

    if (isLast && msg.role === 'user' && imageDataUris && imageDataUris.length > 0) {
      // Formato multimodal para Groq Vision (Qwen / Llama Vision)
      const contentParts = [
        { type: 'text', text: msg.content || 'Analiza esta imagen con detalle.' }
      ];

      for (const uri of imageDataUris) {
        contentParts.push({
          type: 'image_url',
          image_url: { url: uri },
        });
      }

      formatted.push({
        role: 'user',
        content: contentParts,
      });
    } else if (msg && msg.role && msg.content) {
      formatted.push({
        role: msg.role === 'assistant' ? 'assistant' : 'user',
        content: typeof msg.content === 'string' ? msg.content : JSON.stringify(msg.content),
      });
    }
  }

  return formatted;
}

/**
 * Llamada estándar (Limpia, sin restricciones)
 */
async function call(modelId, messages, systemPrompt, imageDataUris = [], options = {}) {
  const client = getClient();
  const hasImages = imageDataUris && imageDataUris.length > 0;
  const targetModel = hasImages ? 'qwen/qwen3.6-27b' : (modelId || 'openai/gpt-oss-120b');
  const formattedMessages = buildMessages(messages, systemPrompt, imageDataUris);

  const maxTokens = options.max_tokens || 4096;

  const response = await client.chat.completions.create({
    model: targetModel,
    messages: formattedMessages,
    max_tokens: maxTokens,
    temperature: 0.7,
  }, { signal: options.signal || null });

  const choice = response.choices && response.choices[0];
  const text = choice && choice.message ? choice.message.content : '';

  return {
    text: text || '',
    tokensInput: response.usage?.prompt_tokens || 0,
    tokensOutput: response.usage?.completion_tokens || 0,
    model: targetModel,
    provider: 'groq',
    isEco: true,
  };
}

/**
 * Llamada Streaming SSE (Limpia, sin restricciones)
 */
async function callStream(modelId, messages, systemPrompt, onChunk, imageDataUris = [], options = {}) {
  const client = getClient();
  const hasImages = imageDataUris && imageDataUris.length > 0;
  const targetModel = hasImages ? 'qwen/qwen3.6-27b' : (modelId || 'openai/gpt-oss-120b');
  const formattedMessages = buildMessages(messages, systemPrompt, imageDataUris);

  const maxTokens = options.max_tokens || 4096;

  const stream = await client.chat.completions.create({
    model: targetModel,
    messages: formattedMessages,
    max_tokens: maxTokens,
    stream: true,
    temperature: 0.7,
  }, { signal: options.signal || null });

  let fullText = '';

  for await (const chunk of stream) {
    const delta = chunk.choices && chunk.choices[0] && chunk.choices[0].delta;
    if (delta && delta.content) {
      fullText += delta.content;
      onChunk(delta.content);
    }
  }

  return {
    text: fullText,
    tokensInput: 0,
    tokensOutput: 0,
    model: targetModel,
    provider: 'groq',
    isEco: true,
  };
}

module.exports = {
  call,
  callStream,
};

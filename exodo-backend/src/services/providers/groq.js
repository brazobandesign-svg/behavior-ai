/**
 * Provider: Groq API
 * Soporta cualquier modelo de Groq (ej: qwen/qwen3.6-27b, meta-llama/llama-4-scout-17b-16e-instruct, llama-3.3-70b-versatile)
 * Soporta multimodalidad (visión) para modelos compatibles.
 * Filtra automáticamente bloques de pensamiento <think>...</think> para no mostrarlos al usuario.
 */

const VISION_MODELS = new Set([
  'qwen/qwen3.6-27b',
  'meta-llama/llama-4-scout-17b-16e-instruct',
  'llama-3.2-11b-vision-preview',
  'llama-3.2-90b-vision-preview'
]);

function stripThinking(text) {
  if (!text.includes('<think>')) return text;
  let cleaned = text.replace(/<think>[\s\S]*?<\/think>/g, '');
  cleaned = cleaned.replace(/<think>[\s\S]*/g, ''); // Elimina bloque incompleto al final
  return cleaned.trimStart();
}

async function call(modelId, messages, systemPrompt, imageDataUris) {
  const groqKey = process.env.GROQ_API_KEY;
  if (!groqKey) throw new Error('GROQ_API_KEY no configurada en el entorno');

  const targetModel = modelId || 'qwen/qwen3.6-27b';
  const supportsVision = VISION_MODELS.has(targetModel);

  // Clonar y formatear mensajes
  const formattedMessages = messages.map(m => ({ role: m.role, content: m.content }));

  // Si hay imágenes y es un modelo multimodal, enriquecer el último mensaje del usuario
  if (imageDataUris && imageDataUris.length > 0 && formattedMessages.length > 0 && supportsVision) {
    const lastMsg = formattedMessages[formattedMessages.length - 1];
    if (lastMsg.role === 'user') {
      const contentArray = [
        { type: 'text', text: typeof lastMsg.content === 'string' ? lastMsg.content : '' }
      ];
      for (const uri of imageDataUris) {
        contentArray.push({
          type: 'image_url',
          image_url: { url: uri }
        });
      }
      lastMsg.content = contentArray;
    }
  }

  const response = await fetch('https://api.groq.com/openai/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${groqKey}`,
    },
    body: JSON.stringify({
      model: targetModel,
      messages: [
        { role: 'system', content: systemPrompt || '' },
        ...formattedMessages,
      ],
      temperature: 0.7,
      stream: false,
    }),
  });

  if (!response.ok) {
    const errBody = await response.text();
    throw new Error(`Groq (${targetModel}) error ${response.status}: ${errBody}`);
  }

  const data = await response.json();
  const rawText = data.choices?.[0]?.message?.content || '';
  const cleanedText = stripThinking(rawText).trim();

  return {
    text: cleanedText,
    model: targetModel,
    tokensInput: data.usage?.prompt_tokens || 0,
    tokensOutput: data.usage?.completion_tokens || 0,
  };
}

async function callStream(modelId, messages, systemPrompt, onChunk, imageDataUris) {
  const groqKey = process.env.GROQ_API_KEY;
  if (!groqKey) throw new Error('GROQ_API_KEY no configurada para Stream de Groq');

  const targetModel = modelId || 'qwen/qwen3.6-27b';
  const supportsVision = VISION_MODELS.has(targetModel);

  // Clonar y formatear mensajes
  const formattedMessages = messages.map(m => ({ role: m.role, content: m.content }));

  // Si hay imágenes y es un modelo multimodal, enriquecer el último mensaje del usuario
  if (imageDataUris && imageDataUris.length > 0 && formattedMessages.length > 0 && supportsVision) {
    const lastMsg = formattedMessages[formattedMessages.length - 1];
    if (lastMsg.role === 'user') {
      const contentArray = [
        { type: 'text', text: typeof lastMsg.content === 'string' ? lastMsg.content : '' }
      ];
      for (const uri of imageDataUris) {
        contentArray.push({
          type: 'image_url',
          image_url: { url: uri }
        });
      }
      lastMsg.content = contentArray;
    }
  }

  const response = await fetch('https://api.groq.com/openai/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${groqKey}`,
    },
    body: JSON.stringify({
      model: targetModel,
      messages: [
        { role: 'system', content: systemPrompt || '' },
        ...formattedMessages,
      ],
      temperature: 0.7,
      stream: true,
    }),
  });

  if (!response.ok) {
    const errBody = await response.text();
    throw new Error(`Groq stream (${targetModel}) error ${response.status}: ${errBody}`);
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder('utf-8');
  let buffer = '';
  let fullText = '';
  let emittedText = '';
  let tokensInput = 0;
  let tokensOutput = 0;

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop() || '';

    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed.startsWith('data: ')) continue;
      const jsonStr = trimmed.slice(6).trim();
      if (jsonStr === '[DONE]') continue;
      try {
        const data = JSON.parse(jsonStr);
        const chunkText = data.choices?.[0]?.delta?.content;
        if (chunkText) {
          fullText += chunkText;
          const cleanedText = stripThinking(fullText);
          if (cleanedText.length > emittedText.length) {
            const newChunk = cleanedText.slice(emittedText.length);
            emittedText = cleanedText;
            if (typeof onChunk === 'function' && newChunk.length > 0) {
              onChunk(newChunk);
            }
          }
        }
        if (data.usage) {
          tokensInput = data.usage.prompt_tokens || tokensInput;
          tokensOutput = data.usage.completion_tokens || tokensOutput;
        }
      } catch (e) {
        // Ignorar JSON incompleto
      }
    }
  }

  return {
    text: emittedText,
    model: targetModel,
    tokensInput,
    tokensOutput,
  };
}

module.exports = { call, callStream };

/**
 * Provider: Mistral API
 * Soporta cualquier modelo de Mistral (ej: mistral-small-2506, codestral-2508, devstral-2512, ministral-8b-2512)
 * Soporta multimodalidad (visión) mediante auto-enrutado a pixtral-12b-2409 cuando hay imágenes adjuntas.
 */

const VISION_MODEL = 'pixtral-12b-2409';

function stripThinking(text) {
  if (!text.includes('<think>')) return text;
  let cleaned = text.replace(/<think>[\s\S]*?<\/think>/g, '');
  cleaned = cleaned.replace(/<think>[\s\S]*/g, '');
  return cleaned.trimStart();
}

async function call(modelId, messages, systemPrompt, imageDataUris) {
  const mistralKey = process.env.MISTRAL_API_KEY;
  if (!mistralKey) throw new Error('MISTRAL_API_KEY no configurada en el entorno');

  let targetModel = modelId || 'mistral-small-2506';

  // Clonar y formatear mensajes
  const formattedMessages = messages.map(m => ({ role: m.role, content: m.content }));

  // Si hay imágenes, enrutar a modelo de visión (Pixtral)
  if (imageDataUris && imageDataUris.length > 0 && formattedMessages.length > 0) {
    targetModel = VISION_MODEL;
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

  const response = await fetch('https://api.mistral.ai/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${mistralKey}`,
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
    throw new Error(`Mistral (${targetModel}) error ${response.status}: ${errBody}`);
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
  const mistralKey = process.env.MISTRAL_API_KEY;
  if (!mistralKey) throw new Error('MISTRAL_API_KEY no configurada para Stream de Mistral');

  let targetModel = modelId || 'mistral-small-2506';

  // Clonar y formatear mensajes
  const formattedMessages = messages.map(m => ({ role: m.role, content: m.content }));

  // Si hay imágenes, enrutar a modelo de visión (Pixtral)
  if (imageDataUris && imageDataUris.length > 0 && formattedMessages.length > 0) {
    targetModel = VISION_MODEL;
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

  const response = await fetch('https://api.mistral.ai/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${mistralKey}`,
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
    throw new Error(`Mistral stream (${targetModel}) error ${response.status}: ${errBody}`);
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

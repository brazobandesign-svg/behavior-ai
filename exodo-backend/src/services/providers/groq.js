/**
 * Provider: Groq API
 * Soporta cualquier modelo de Groq (ej: llama-3.3-70b-versatile)
 */

async function call(modelId, messages, systemPrompt) {
  const groqKey = process.env.GROQ_API_KEY;
  if (!groqKey) throw new Error('GROQ_API_KEY no configurada en el entorno');

  const targetModel = modelId || 'llama-3.3-70b-versatile';

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
        ...messages,
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
  const text = data.choices?.[0]?.message?.content || '';

  return {
    text,
    model: targetModel,
    tokensInput: data.usage?.prompt_tokens || 0,
    tokensOutput: data.usage?.completion_tokens || 0,
  };
}

async function callStream(modelId, messages, systemPrompt, onChunk) {
  const groqKey = process.env.GROQ_API_KEY;
  if (!groqKey) throw new Error('GROQ_API_KEY no configurada para Stream de Groq');

  const targetModel = modelId || 'llama-3.3-70b-versatile';

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
        ...messages,
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
          if (typeof onChunk === 'function') onChunk(chunkText);
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
    text: fullText,
    model: targetModel,
    tokensInput,
    tokensOutput,
  };
}

module.exports = { call, callStream };

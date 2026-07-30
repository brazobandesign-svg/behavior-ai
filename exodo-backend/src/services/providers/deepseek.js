/**
 * Provider: DeepSeek Direct API
 * Soportando: deepseek-chat (V3 / Flash) y deepseek-reasoner (R1 / Pro)
 */

async function call(modelId, messages, systemPrompt) {
  const deepseekKey = process.env.DEEPSEEK_API_KEY;
  if (!deepseekKey) throw new Error('DEEPSEEK_API_KEY no configurada en el entorno');

  const targetModel = modelId === 'deepseek-reasoner' ? 'deepseek-reasoner' : 'deepseek-chat';

  const response = await fetch('https://api.deepseek.com/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${deepseekKey}`,
    },
    body: JSON.stringify({
      model: targetModel,
      messages: [
        { role: 'system', content: systemPrompt || '' },
        ...messages,
      ],
      max_tokens: 4096,
      temperature: targetModel === 'deepseek-reasoner' ? 0.6 : 0.7,
      stream: false,
    }),
  });

  if (!response.ok) {
    const errBody = await response.text();
    throw new Error(`DeepSeek (${targetModel}) error ${response.status}: ${errBody}`);
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
  const deepseekKey = process.env.DEEPSEEK_API_KEY;
  if (!deepseekKey) throw new Error('DEEPSEEK_API_KEY no configurada para Stream');

  const targetModel = modelId === 'deepseek-reasoner' ? 'deepseek-reasoner' : 'deepseek-chat';

  const response = await fetch('https://api.deepseek.com/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${deepseekKey}`,
    },
    body: JSON.stringify({
      model: targetModel,
      messages: [
        { role: 'system', content: systemPrompt || '' },
        ...messages,
      ],
      max_tokens: 4096,
      temperature: targetModel === 'deepseek-reasoner' ? 0.6 : 0.7,
      stream: true,
    }),
  });

  if (!response.ok) {
    const errBody = await response.text();
    throw new Error(`DeepSeek stream (${targetModel}) error ${response.status}: ${errBody}`);
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
        // Ignorar JSON incompletos en el stream
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

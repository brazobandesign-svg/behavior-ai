/**
 * Provider: Ollama Local (Qwen 2.5 7B)
 * Uso: Modelo local para pruebas de desarrollo ilimitadas
 */

async function call(modelId, messages, systemPrompt) {
  const response = await fetch('http://localhost:11434/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'qwen2.5:7b',
      messages: [
        { role: 'system', content: systemPrompt },
        ...messages,
      ],
      max_tokens: 2048,
      temperature: 0.7,
    }),
  });

  if (!response.ok) {
    const errBody = await response.text();
    throw new Error(`Ollama error ${response.status}: ${errBody}`);
  }

  const data = await response.json();
  return {
    text: data.choices?.[0]?.message?.content || '',
    model: 'ollama-qwen2.5-7b',
    tokensInput: data.usage?.prompt_tokens || 15,
    tokensOutput: data.usage?.completion_tokens || 25,
  };
}

module.exports = { call };

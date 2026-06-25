/**
 * Provider: Cerebras (Llama 3.1 70B)
 * Uso: Fallback 3 para Genesis (último recurso)
 * Bible sección 04: Free tier
 */

async function call(modelId, messages, systemPrompt) {
  const apiKey = process.env.CEREBRAS_API_KEY || 'demo';

  const response = await fetch('https://api.cerebras.ai/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: 'llama-3.1-70b',
      messages: [
        { role: 'system', content: systemPrompt },
        ...messages,
      ],
      max_tokens: 4096,
      temperature: 0.7,
    }),
  });

  if (!response.ok) {
    const errBody = await response.text();
    throw new Error(`Cerebras error ${response.status}: ${errBody}`);
  }

  const data = await response.json();
  return {
    text: data.choices?.[0]?.message?.content || '',
    model: 'cerebras-llama-3.1',
    tokensInput: data.usage?.prompt_tokens || 0,
    tokensOutput: data.usage?.completion_tokens || 0,
  };
}

module.exports = { call };

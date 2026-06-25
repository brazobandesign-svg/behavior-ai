/**
 * Provider: NVIDIA NIM (Llama 4 Maverick)
 * Uso: Fallback 2 para Genesis
 * Bible sección 04: Free tier
 */

async function call(modelId, messages, systemPrompt) {
  const apiKey = process.env.NIM_API_KEY || 'nvapi-free';

  const response = await fetch('https://integrate.api.nvidia.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: 'meta/llama-4-maverick-17b-128e-instruct',
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
    throw new Error(`NIM error ${response.status}: ${errBody}`);
  }

  const data = await response.json();
  return {
    text: data.choices?.[0]?.message?.content || '',
    model: 'nim-llama-4',
    tokensInput: data.usage?.prompt_tokens || 0,
    tokensOutput: data.usage?.completion_tokens || 0,
  };
}

module.exports = { call };

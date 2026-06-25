/**
 * Provider: DeepSeek V4 Pro via OpenRouter
 * Uso: RAZONAMIENTO para Hazak
 * Bible sección 04: $0.44/$0.87 por M tokens
 */

async function call(modelId, messages, systemPrompt) {
  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) throw new Error('OPENROUTER_API_KEY no configurada');

  const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
      'HTTP-Referer': 'https://exodo.behavior.ai',
      'X-Title': 'Éxodo by Behavior',
    },
    body: JSON.stringify({
      model: 'deepseek/deepseek-v4-pro',
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
    throw new Error(`DeepSeek V4 Pro error ${response.status}: ${errBody}`);
  }

  const data = await response.json();
  const text = data.choices?.[0]?.message?.content || '';

  return {
    text,
    model: 'deepseek-v4-pro',
    tokensInput: data.usage?.prompt_tokens || 0,
    tokensOutput: data.usage?.completion_tokens || 0,
  };
}

module.exports = { call };

/**
 * Provider: Anthropic (Claude)
 * Modelo: Claude Sonnet 4.6 (REDACCION para Hazak)
 * Bible sección 04: $3.00/$15.00 por M tokens
 * Regla #4: Haiku nunca, en ningún plan ni fallback.
 * Bible: Prompt caching habilitado desde el primer día.
 */

async function call(modelId, messages, systemPrompt) {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error('ANTHROPIC_API_KEY no configurada');

  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 4096,
      system: [
        {
          type: 'text',
          text: systemPrompt,
          cache_control: { type: 'ephemeral' }, // Prompt caching — 90% descuento
        },
      ],
      messages: messages.map(m => ({
        role: m.role,
        content: m.content,
      })),
    }),
  });

  if (!response.ok) {
    const errBody = await response.text();
    throw new Error(`Anthropic Sonnet error ${response.status}: ${errBody}`);
  }

  const data = await response.json();
  const text = data.content?.[0]?.text || '';

  return {
    text,
    model: 'claude-sonnet-4-6',
    tokensInput: data.usage?.input_tokens || 0,
    tokensOutput: data.usage?.output_tokens || 0,
  };
}

module.exports = { call };

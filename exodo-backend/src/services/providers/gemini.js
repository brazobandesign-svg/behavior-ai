/**
 * Provider: Google Gemini
 * Modelos: gemini-2.5-flash (Genesis primario + SIMPLE para todos)
 *          gemini-3.1-pro (DOCUMENTO para Hazak)
 * Bible sección 04: Google AI Studio, $0.30/$2.50 por M tokens (Flash)
 */

const MODEL_IDS = {
  'gemini-2.5-flash': 'gemini-2.5-flash',
  'gemini-3.1-pro': 'gemini-3.1-pro',
};

async function call(modelId, messages, systemPrompt) {
  const apiKey = process.env.GOOGLE_AI_API_KEY;
  if (!apiKey) throw new Error('GOOGLE_AI_API_KEY no configurada');

  const geminiModel = MODEL_IDS[modelId] || 'gemini-2.5-flash';

  // Convertir formato OpenAI-style a Gemini format
  const contents = messages.map(m => ({
    role: m.role === 'assistant' ? 'model' : 'user',
    parts: [{ text: m.content }],
  }));

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${geminiModel}:generateContent?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: systemPrompt }] },
        contents,
        generationConfig: {
          maxOutputTokens: 4096,
          temperature: 0.7,
        },
      }),
    }
  );

  if (!response.ok) {
    const errBody = await response.text();
    throw new Error(`Gemini ${geminiModel} error ${response.status}: ${errBody}`);
  }

  const data = await response.json();
  const text = data.candidates?.[0]?.content?.parts?.[0]?.text;
  const usage = data.usageMetadata;

  return {
    text: text || '',
    model: geminiModel,
    tokensInput: usage?.promptTokenCount || 0,
    tokensOutput: usage?.candidatesTokenCount || 0,
  };
}

module.exports = { call };

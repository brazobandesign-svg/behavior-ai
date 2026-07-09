/**
 * Provider: Google Gemini (Direct API)
 * Modelos: gemini-2.0-flash (Genesis G1.1 primario)
 * Bible sección 04: Google AI Studio
 */

const MODEL_IDS = {
  'gemini-1.5-flash': 'gemini-2.0-flash',
  'gemini-2.0-flash': 'gemini-2.0-flash',
  'gemini-2.5-flash': 'gemini-2.0-flash',
};

/**
 * Convierte mensajes OpenAI-style [{role, content}] al formato Gemini
 * [{role, parts:[{text}]}], fusionando mensajes consecutivos del mismo rol
 * para evitar el error "adjacent user/model messages" de Gemini.
 */
function formatMessages(messages, imageDataUris) {
  const contents = [];
  for (const m of messages) {
    const geminiRole = m.role === 'assistant' ? 'model' : 'user';
    const text = m.content || '';
    // Fusionar con el anterior si es el mismo rol (Gemini rechaza roles adyacentes iguales)
    if (contents.length > 0 && contents[contents.length - 1].role === geminiRole) {
      contents[contents.length - 1].parts.push({ text });
    } else {
      contents.push({ role: geminiRole, parts: [{ text }] });
    }
  }

  // [Fix visión] Adjuntar imágenes al ÚLTIMO turno de usuario (el mensaje actual).
  // Gemini espera inlineData como parte del mismo turno que la pregunta del usuario,
  // no como un turno separado.
  if (imageDataUris && imageDataUris.length > 0 && contents.length > 0) {
    const lastContent = contents[contents.length - 1];
    if (lastContent.role === 'user') {
      for (const dataUri of imageDataUris) {
        const match = /^data:([^;]+);base64,(.+)$/.exec(dataUri);
        if (match) {
          lastContent.parts.push({
            inlineData: { mimeType: match[1], data: match[2] },
          });
        }
      }
    }
  }

  return contents;
}

async function call(modelId, messages, systemPrompt, imageDataUris) {
  const apiKey = process.env.GOOGLE_AI_API_KEY;
  if (!apiKey) throw new Error('GOOGLE_AI_API_KEY no configurada');

  const geminiModel = MODEL_IDS[modelId] || 'gemini-2.0-flash';
  const contents = formatMessages(messages, imageDataUris);

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${geminiModel}:generateContent?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: systemPrompt || '' }] },
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
  const text = data.candidates?.[0]?.content?.parts?.[0]?.text || '';
  const usage = data.usageMetadata;

  return {
    text,
    model: geminiModel,
    tokensInput: usage?.promptTokenCount || 0,
    tokensOutput: usage?.candidatesTokenCount || 0,
  };
}

async function callStream(modelId, messages, systemPrompt, onChunk, imageDataUris) {
  const apiKey = process.env.GOOGLE_AI_API_KEY;
  if (!apiKey) throw new Error('GOOGLE_AI_API_KEY no configurada');

  const geminiModel = MODEL_IDS[modelId] || 'gemini-2.0-flash';
  const contents = formatMessages(messages, imageDataUris);

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${geminiModel}:streamGenerateContent?alt=sse&key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: systemPrompt || '' }] },
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
    throw new Error(`Gemini stream ${geminiModel} error ${response.status}: ${errBody}`);
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
        const chunkText = data.candidates?.[0]?.content?.parts?.[0]?.text;
        if (chunkText) {
          fullText += chunkText;
          if (typeof onChunk === 'function') onChunk(chunkText);
        }
        if (data.usageMetadata) {
          tokensInput = data.usageMetadata.promptTokenCount || tokensInput;
          tokensOutput = data.usageMetadata.candidatesTokenCount || tokensOutput;
        }
      } catch (e) {
        // Ignorar JSON incompletos en el stream
      }
    }
  }

  return {
    text: fullText,
    model: geminiModel,
    tokensInput,
    tokensOutput,
  };
}

module.exports = { call, callStream };

/**
 * Clasificador de intención de mensajes.
 * Bible sección 05: ~50 tokens en Gemini Flash, ~$0.000015 por llamada.
 * Categorías: SIMPLE | REDACCION | RAZONAMIENTO | DOCUMENTO | IMAGEN
 * Regla #8: en caso de duda → SIMPLE (error hacia lo barato).
 */

const INTENT_SYSTEM_PROMPT = `Clasifica el siguiente mensaje del usuario en exactamente UNA de estas categorías. Responde SOLO con la categoría, nada más.

SIMPLE — preguntas, conversación casual, saludos, definiciones, traducciones
REDACCION — planificaciones, redactar documentos, cartas, contratos, textos formales, ensayos
RAZONAMIENTO — análisis, comparaciones, resolución matemática, evaluación, argumentación lógica
DOCUMENTO — el usuario adjuntó o menciona un archivo PDF/Word/Excel, pide resumir o extraer
IMAGEN — generar imagen, diseñar logo, crear foto, ilustración

Si tienes duda, responde SIMPLE.`;

/**
 * Clasifica la intención de un mensaje usando Gemini Flash.
 * @param {string} message - El mensaje del usuario
 * @returns {Promise<string>} - La intención: SIMPLE | REDACCION | RAZONAMIENTO | DOCUMENTO | IMAGEN
 */
async function classifyIntent(message) {
  const apiKey = process.env.GOOGLE_AI_API_KEY;

  if (!apiKey) {
    console.warn('[intentClassifier] Sin GOOGLE_AI_API_KEY, defaulting a SIMPLE');
    return 'SIMPLE';
  }

  try {
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [
            { role: 'user', parts: [{ text: `${INTENT_SYSTEM_PROMPT}\n\nMensaje: "${message}"` }] },
          ],
          generationConfig: {
            maxOutputTokens: 10,
            temperature: 0.0,
          },
        }),
      }
    );

    const data = await response.json();
    const result = data.candidates?.[0]?.content?.parts?.[0]?.text?.trim().toUpperCase();

    const validIntents = ['SIMPLE', 'REDACCION', 'RAZONAMIENTO', 'DOCUMENTO', 'IMAGEN'];
    if (validIntents.includes(result)) {
      return result;
    }

    // Regla #8: en duda → SIMPLE
    console.warn(`[intentClassifier] Resultado inesperado: "${result}", usando SIMPLE`);
    return 'SIMPLE';
  } catch (err) {
    console.error('[intentClassifier] Error:', err.message);
    return 'SIMPLE';
  }
}

module.exports = { classifyIntent };

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

  // Sin key: fallback local keyword-based (gratis, ~10 ms).
  if (!apiKey) {
    const local = classifyByKeywords(message);
    console.warn(`[intentClassifier] Sin GOOGLE_AI_API_KEY, fallback local → ${local}`);
    return local;
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

    // Resultado inesperado del LLM: fallback local.
    const local = classifyByKeywords(message);
    console.warn(`[intentClassifier] LLM devolvió "${result}", fallback local → ${local}`);
    return local;
  } catch (err) {
    // Gemini caído / red / rate limit: fallback local silencioso.
    const local = classifyByKeywords(message);
    console.error(`[intentClassifier] Error Gemini: ${err.message}, fallback local → ${local}`);
    return local;
  }
}

/**
 * Clasificador keyword-based como fallback (cero costo, ~0 ms).
 * Devuelve siempre la mejor coincidencia o 'SIMPLE' si no hay pista clara.
 *
 * Categorías:
 *   IMAGEN      — crear/generar/diseñar/imaginar/dibujar algo visual
 *   DOCUMENTO   — pdf/word/excel/adjuntar archivo/resumir documento
 *   REDACCION   — redactar/escribir/carta/correo/ensayo/contrato
 *   RAZONAMIENTO — analizar/comparar/por qué/cuál es mejor/cuánto/matemática
 *   SIMPLE      — todo lo demás
 */
function classifyByKeywords(message) {
  if (!message || typeof message !== 'string') return 'SIMPLE';

  const m = message.toLowerCase().trim();

  // Adjuntos de archivo (no están en el texto sino en la metadata del chat).
  // El frontend en chat_screen inserta "[Foto: name]", "[Archivos: ...]" antes de mandar.
  if (/\[(foto|archivo|archivos|documento|pdf|excel|word|imagen|gallery)\s*:/i.test(m)) {
    return 'DOCUMENTO';
  }

  // IMAGEN — generación visual
  const imgKw = ['genera una imagen', 'generar imagen', 'crea una imagen', 'crear imagen',
                 'hazme una imagen', 'dibuja', 'diseña un logo', 'diseña un',
                 'ilustra', 'imagina', 'muéstrame una foto', 'renderiza', 'pinta'];
  if (imgKw.some((k) => m.includes(k))) return 'IMAGEN';

  // DOCUMENTO — referencia explícita a archivo
  const docKw = ['adjunto', 'adjunté', 'en el archivo', 'el pdf', 'el documento',
                 'resume este', 'resúmeme este', 'lee este', 'extrae de',
                 'tabla de excel', 'hoja de cálculo', 'la planilla', 'el word'];
  if (docKw.some((k) => m.includes(k))) return 'DOCUMENTO';

  // REDACCION — producir texto formal/largo
  const redKw = ['redacta', 'redactar', 'escríbeme', 'escribe un', 'escribe una',
                 'hazme un', 'hazme una', 'carta de', 'correo formal', 'correo a',
                 'contrato', 'carta de presentación', 'ensayo sobre', 'tesis sobre',
                 'informe de', 'memorandum', 'solicitud formal', 'carta formal',
                 'currículum', 'cv de', 'carta de recomendación', 'carta laboral'];
  if (redKw.some((k) => m.includes(k))) return 'REDACCION';

  // RAZONAMIENTO — análisis, comparación, cálculo
  const razKw = ['analiza', 'analizar', 'compara', 'comparar', 'diferencia entre',
                 'cuál es mejor', 'qué es mejor', 'por qué', 'porque ',
                 'explica por qué', 'razona', 'argumenta', 'evalúa', 'evaluar',
                 'cuánto es', 'cuánto son', 'cuál es la diferencia', 'calcula',
                 'resuelve', 'demuestra', 'prueba que', 'ventajas y desventajas',
                 'pros y contras', 'si ... entonces', 'hipótesis'];
  if (razKw.some((k) => m.includes(k))) return 'RAZONAMIENTO';

  // SIMPLE — default (saludos, preguntas cortas, definiciones)
  return 'SIMPLE';
}

module.exports = { classifyIntent, classifyByKeywords };

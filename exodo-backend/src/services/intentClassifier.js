/**
 * Clasificador de intención de mensajes.
 * Categorías: SIMPLE | REDACCION | RAZONAMIENTO | DOCUMENTO | IMAGEN
 * Usa deepseek-chat para consumir tácticamente el saldo del backend.
 */

const deepseekProvider = require('./providers/deepseekProvider');

const INTENT_SYSTEM_PROMPT = `Clasifica el siguiente mensaje del usuario en exactamente UNA de estas categorías. Responde SOLO con la categoría en mayúsculas, nada más.

SIMPLE — preguntas, conversación casual, saludos, definiciones, traducciones
REDACCION — planificaciones, redactar documentos, cartas, contratos, textos formales, ensayos
RAZONAMIENTO — análisis, comparaciones, resolución matemática, evaluación, argumentación lógica
DOCUMENTO — el usuario adjuntó o menciona un archivo PDF/Word/Excel, pide resumir o extraer
IMAGEN — generar imagen, diseñar logo, crear foto, ilustración

Si tienes duda, responde SIMPLE.`;

async function classifyIntent(message) {
  if (!process.env.DEEPSEEK_API_KEY) {
    const local = classifyByKeywords(message);
    return local;
  }

  try {
    const resultObj = await deepseekProvider.call(
      'deepseek-chat',
      [{ role: 'user', content: `Mensaje: "${message}"` }],
      INTENT_SYSTEM_PROMPT
    );

    const result = (resultObj?.text || '').trim().toUpperCase();
    const validIntents = ['SIMPLE', 'REDACCION', 'RAZONAMIENTO', 'DOCUMENTO', 'IMAGEN'];
    if (validIntents.includes(result)) {
      return result;
    }

    return classifyByKeywords(message);
  } catch (err) {
    console.warn(`[intentClassifier] Error DeepSeek intent: ${err.message}, fallback local`);
    return classifyByKeywords(message);
  }
}

function classifyByKeywords(message) {
  if (!message || typeof message !== 'string') return 'SIMPLE';

  const m = message.toLowerCase().trim();

  if (/\[(foto|archivo|archivos|documento|pdf|excel|word|imagen|gallery)\s*:/i.test(m)) {
    return 'DOCUMENTO';
  }

  const imgKw = ['genera una imagen', 'generar imagen', 'crea una imagen', 'crear imagen',
                 'hazme una imagen', 'dibuja', 'diseña un logo', 'diseña un',
                 'ilustra', 'imagina', 'muéstrame una foto', 'renderiza', 'pinta'];
  if (imgKw.some((k) => m.includes(k))) return 'IMAGEN';

  const docKw = ['adjunto', 'adjunté', 'en el archivo', 'el pdf', 'el documento',
                 'resume este', 'resúmeme este', 'lee este', 'extrae de',
                 'tabla de excel', 'hoja de cálculo', 'la planilla', 'el word'];
  if (docKw.some((k) => m.includes(k))) return 'DOCUMENTO';

  const redKw = ['redacta', 'redactar', 'escríbeme', 'escribe un', 'escribe una',
                 'hazme un', 'hazme una', 'carta de', 'correo formal', 'correo a',
                 'contrato', 'carta de presentación', 'ensayo sobre', 'tesis sobre',
                 'informe de', 'memorandum', 'solicitud formal', 'carta formal',
                 'currículum', 'cv de', 'carta de recomendación', 'carta laboral'];
  if (redKw.some((k) => m.includes(k))) return 'REDACCION';

  const razKw = ['analiza', 'analizar', 'compara', 'comparar', 'diferencia entre',
                 'cuál es mejor', 'qué es mejor', 'por qué', 'porque ',
                 'explica por qué', 'razona', 'argumenta', 'evalúa', 'evaluar',
                 'cuánto es', 'cuánto son', 'cuál es la diferencia', 'calcula',
                 'resuelve', 'demuestra', 'prueba que', 'ventajas y desventajas',
                 'pros y contras', 'si ... entonces', 'hipótesis'];
  if (razKw.some((k) => m.includes(k))) return 'RAZONAMIENTO';

  return 'SIMPLE';
}

module.exports = { classifyIntent, classifyByKeywords };

/**
 * Clasificador de intención de mensajes.
 * Categorías: SIMPLE | REDACCION | RAZONAMIENTO | DOCUMENTO | IMAGEN
 * Usa deepseek-chat para consumir tácticamente el saldo del backend.
 */

const alibabaProvider = require('./providers/alibaba');

const INTENT_SYSTEM_PROMPT = `Clasifica el siguiente mensaje del usuario en exactamente UNA de estas categorías. Responde SOLO con la categoría en mayúsculas, nada más.

SIMPLE — preguntas, conversación casual, saludos, definiciones, traducciones
REDACCION — planificaciones, redactar documentos, cartas, contratos, textos formales, ensayos
RAZONAMIENTO — análisis, comparaciones, resolución matemática, evaluación, argumentación lógica
DOCUMENTO — el usuario adjuntó o menciona un archivo PDF/Word/Excel, pide resumir o extraer
IMAGEN — generar imagen, diseñar logo, crear foto, ilustración

Si tienes duda, responde SIMPLE.`;

async function classifyIntent(message) {
  // IMAGEN se decide localmente ANTES del LLM: la señal léxica ("genera una
  // foto de un gato") es determinante, y la clasificación remota puede
  // rebajarla a SIMPLE y enviar la petición al LLM de texto en vez del t2i.
  const local = classifyByKeywords(message);
  if (local === 'IMAGEN') return local;

  if (!process.env.DEEPSEEK_API_KEY) {
    return local;
  }

  try {
    const resultObj = await alibabaProvider.call(
      'deepseek-chat',
      [{ role: 'user', content: `Mensaje: "${message}"` }],
      INTENT_SYSTEM_PROMPT
    );

    const result = (resultObj?.text || '').trim().toUpperCase();
    const validIntents = ['SIMPLE', 'REDACCION', 'RAZONAMIENTO', 'DOCUMENTO', 'IMAGEN'];
    if (validIntents.includes(result)) {
      return result;
    }

    return local;
  } catch (err) {
    console.warn(`[intentClassifier] Error DeepSeek intent: ${err.message}, fallback local`);
    return local;
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
  // Regex robusta (30-ago): "genera una FOTO de un gato" caía a SIMPLE y el
  // LLM respondía "no puedo generar imágenes". Cubre verbos×sustantivos
  // comunes en es/en incluyendo plurales y acentos.
  const imgRe = /\b(genera|generar|crear?|create|generate|make|haz(?:me)?|draw|dibuja(?:rme)?|pinta|renderiza|ilustra|muestra|muéstrame|show|dise[ñn]a)\b[\s\S]{0,24}\b(imagen(?:es)?|images?|fotos?|photos?|pictures?|dibujos?|drawings?|ilustraci(?:ó|o)nes?|illustrations?|logos?|logotipos?)\b/i;
  if (imgRe.test(m)) return 'IMAGEN';

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

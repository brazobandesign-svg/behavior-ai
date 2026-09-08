/**
 * src/utils/sanitizeOptions.js
 *
 * Normalizador y blindaje universal para tarjetas de opciones interactivas (Guided Cards).
 * Maneja todos los escenarios posibles de salida de modelos LLM:
 * 1. ```exodo-options bien formado -> validado y preservado.
 * 2. ```exodo-options sin fence de cierre (corte de red/stream) -> se le agrega el cierre ```.
 * 3. ```json ... ``` con payload de opciones -> convertido a ```exodo-options.
 * 4. ``` ... ``` (sin lang) con payload de opciones -> convertido a ```exodo-options.
 * 5. JSON crudo como única respuesta -> envuelto en ```exodo-options.
 * 6. Prosa + JSON crudo -> se aísla la prosa y el JSON se cerca en ```exodo-options.
 * 7. Claves en español (pregunta / opciones) -> normalizadas a question / options.
 * 8. Claves invertidas (options antes de question).
 * 9. recommend / labels preservados si existen.
 * 10. JSON truncado por corte de red -> tolerancia y cierre limpio de bloques.
 */

/**
 * Valida si un objeto parseado califica como tarjeta de opciones guiadas.
 */
function isOptionsPayload(obj) {
  if (!obj || typeof obj !== 'object' || Array.isArray(obj)) return false;
  const q = obj.question || obj.pregunta;
  const opts = obj.options || obj.opciones;
  return typeof q === 'string' && q.trim().length > 0 && Array.isArray(opts) && opts.length >= 2;
}

/**
 * Normaliza el objeto JSON al esquema canónico esperado por la app móvil y web:
 * { question: string, options: string[], recommend?: number, labels?: object }
 */
function normalizeOptionsJson(parsed) {
  const normalized = {
    question: (parsed.question || parsed.pregunta || '').trim(),
    options: (parsed.options || parsed.opciones || [])
      .map((o) => (typeof o === 'string' ? o.trim() : String(o)))
      .filter((o) => o.length > 0),
  };
  if (typeof parsed.recommend === 'number') {
    normalized.recommend = parsed.recommend;
  }
  if (parsed.labels && typeof parsed.labels === 'object') {
    normalized.labels = parsed.labels;
  }
  return JSON.stringify(normalized, null, 2);
}

/**
 * Extrae la porción JSON candidata de opciones guiadas dentro de un texto.
 * Retorna { fullMatch, startIndex, endIndex, parsed } o null.
 */
function extractJsonCandidate(text) {
  if (!text || typeof text !== 'string') return null;

  // 1. Buscar bloques cercados ```json o ``` (sin lang)
  const fenceRegex = /```(?:json)?\s*(\{[\s\S]*?\})\s*```/i;
  const fenceMatch = text.match(fenceRegex);
  if (fenceMatch) {
    try {
      const parsed = JSON.parse(fenceMatch[1]);
      if (isOptionsPayload(parsed)) {
        return {
          fullMatch: fenceMatch[0],
          startIndex: fenceMatch.index,
          endIndex: fenceMatch.index + fenceMatch[0].length,
          parsed,
        };
      }
    } catch (_) {}
  }

  // 2. Buscar JSON crudo con "question"/"pregunta" y "options"/"opciones"
  // Estrategia rápida: desde el primer { hasta el último }
  const firstBrace = text.indexOf('{');
  if (firstBrace === -1) return null;
  const lastBrace = text.lastIndexOf('}');
  if (lastBrace > firstBrace) {
    const candidate = text.slice(firstBrace, lastBrace + 1);
    try {
      const parsed = JSON.parse(candidate);
      if (isOptionsPayload(parsed)) {
        return {
          fullMatch: candidate,
          startIndex: firstBrace,
          endIndex: lastBrace + 1,
          parsed,
        };
      }
    } catch (_) {}

    // 3. Si falló de extremo a extremo, probar parseando con balanceo de llaves {}
    let depth = 0;
    let start = -1;
    for (let i = 0; i < text.length; i++) {
      if (text[i] === '{') {
        if (depth === 0) start = i;
        depth++;
      } else if (text[i] === '}') {
        depth--;
        if (depth === 0 && start !== -1) {
          const sub = text.slice(start, i + 1);
          try {
            const subParsed = JSON.parse(sub);
            if (isOptionsPayload(subParsed)) {
              return {
                fullMatch: sub,
                startIndex: start,
                endIndex: i + 1,
                parsed: subParsed,
              };
            }
          } catch (_) {}
          start = -1;
        }
      }
    }
  }

  return null;
}

/**
 * Normaliza y cerca con ```exodo-options cualquier bloque de opciones/preguntas interactivas.
 * Garantiza que el cliente reciba un bloque bien cercado y libre de JSON crudo visible.
 */
function sanitizeAndFenceOptions(text) {
  if (!text || typeof text !== 'string') return text || '';

  // 1. Si ya tiene ```exodo-options:
  if (text.includes('```exodo-options')) {
    // Si falta el fence de cierre ``` al final (corte abrupto de red/stream)
    const afterFence = text.slice(text.indexOf('```exodo-options') + 16);
    if (!afterFence.includes('```')) {
      return text.trimEnd() + '\n```';
    }
    return text;
  }

  // 2. Buscar candidato JSON
  const candidate = extractJsonCandidate(text);
  if (!candidate) {
    return text;
  }

  const jsonStr = normalizeOptionsJson(candidate.parsed);
  const fencedBlock = '```exodo-options\n' + jsonStr + '\n```';

  const before = text.slice(0, candidate.startIndex).trim();
  const after = text.slice(candidate.endIndex).trim();

  if (before && after) {
    return `${before}\n\n${fencedBlock}\n\n${after}`;
  } else if (before) {
    return `${before}\n\n${fencedBlock}`;
  } else if (after) {
    return `${fencedBlock}\n\n${after}`;
  } else {
    return fencedBlock;
  }
}

module.exports = {
  isOptionsPayload,
  normalizeOptionsJson,
  extractJsonCandidate,
  sanitizeAndFenceOptions,
};

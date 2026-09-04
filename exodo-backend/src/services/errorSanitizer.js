'use strict';

const { REDACTED } = require('./logger');

/**
 * ============================================================================
 * errorSanitizer.js — Capa de Sanitización de Errores y Protección Anti-Fugas
 * ============================================================================
 *
 * VULNERABILIDAD CORREGIDA (2026-08-19):
 * Un error upstream de Groq (HTTP 413 / límite TPM) fue transmitido crudo al
 * stream SSE del usuario, filtrando organization IDs, URLs del vendor y tamaños
 * de payload al cliente móvil.
 *
 * REGLA ABSOLUTA:
 * Ningún texto de error de un proveedor upstream (Groq, DeepSeek/Alibaba,
 * Gemini, OpenAI embeddings, Supabase RPC) puede llegar jamás a `res.write()`.
 * Todo error de gateway se:
 *   1. LOGUEA internamente con stack trace completo ([INTERNAL_GATEWAY_ERROR]).
 *   2. Devuelve al usuario como mensaje genérico de marca (sin datos de vendor).
 *
 * Uso:
 *   const { handleGatewayError, USER_FACING_ERROR_MESSAGE } = require('./errorSanitizer');
 */

/** Mensaje único, genérico y de marca que ve el usuario ante CUALQUIER fallo upstream. */
const USER_FACING_ERROR_MESSAGE =
  'El asistente está experimentando alta demanda. Por favor, reintenta tu consulta en unos momentos.';

/** Mensaje de marca cuando el servicio está CAÍDO (no ocupado): sin tecnicismos. */
const SERVICE_DOWN_MESSAGE =
  'Éxodo no está disponible en este momento. Estamos trabajando para restablecer el servicio. Inténtalo de nuevo en unos minutos.';

/**
 * Clasifica un error para el usuario: 'down' (caído) | 'busy' (ocupado) | 'error' (genérico).
 * - down: fallos de red (DNS, refused, reset, timeout) y 5xx del proveedor.
 * - busy: 429/413/529 (límite/capacidad).
 * Nunca expone nada del vendor; solo clasifica.
 */
function classifyUserError(err) {
  const status = extractStatus(err);
  if (status != null) {
    if (status === 429 || status === 413 || status === 529) return 'busy';
    if (status >= 500) return 'down';
    return 'error';
  }
  const msg = err && err.message ? String(err.message) : String(err || '');
  if (/econnrefused|enotfound|etimedout|eai_again|socket hang up|socket.+closed|fetch failed|failed to fetch|failed host|host lookup|connection refused|connection reset|connection closed|connection error|connect error|unreachable|network request failed|timed out|timeout|econnreset|epipe|temporarily unavailable|no address|nodename/i.test(msg)) {
    return 'down';
  }
  return 'error';
}

/**
 * Error sanitizado listo para el cliente: { content, code }.
 * code: 'service_down' | 'service_busy' | 'error'. Ambos contenidos son de
 * marca y seguros (los únicos textos que pueden llegar al cliente).
 */
function userFacingError(err) {
  const kind = classifyUserError(err);
  if (kind === 'down') return { content: SERVICE_DOWN_MESSAGE, code: 'service_down' };
  if (kind === 'busy') return { content: USER_FACING_ERROR_MESSAGE, code: 'service_busy' };
  return { content: USER_FACING_ERROR_MESSAGE, code: 'error' };
}

/**
 * Extrae el código de estado HTTP de un error de proveedor, si existe.
 * Compatible con el SDK de OpenAI (err.status), errores genéricos (err.statusCode)
 * y mensajes con patrón "status: 413" / "413".
 */
function extractStatus(err) {
  if (!err) return null;
  if (typeof err.status === 'number') return err.status;
  if (typeof err.statusCode === 'number') return err.statusCode;
  if (typeof err.response?.status === 'number') return err.response.status;
  if (typeof err.message === 'string') {
    const m = err.message.match(/\b(4\d\d|5\d\d)\b/);
    if (m) return Number(m[1]);
  }
  return null;
}

/**
 * Determina si un error corresponde a una desconexión/aborto del cliente.
 * Estos NO deben emitir eventos de error al stream (el cliente ya no está).
 */
function isClientAbortError(err) {
  if (!err) return false;
  const name = String(err.name || '');
  const msg = String(err.message || '');
  return (
    name === 'AbortError' ||
    name === 'AbortSignal' ||
    msg.includes('AbortError') ||
    msg.includes('aborted') ||
    msg.includes('This operation was aborted') ||
    err.code === 'ABORT_ERR'
  );
}

/**
 * Determina si un error es de tipo "límite de tasa / capacidad" del vendor
 * (429 rate limit, 413 payload excedido, 529/503 sobrecarga). Se usa solo
 * para clasificación interna del log; NUNCA se expone al usuario.
 */
function isCapacityError(err) {
  const status = extractStatus(err);
  return status === 429 || status === 413 || status === 529 || status === 503;
}

/**
 * LOG INTERNO ÚNICAMENTE.
 * Registra el stack trace completo, vendor, modelo, status y mensaje crudo
 * en la consola del servidor. Nada de esto sale hacia el cliente.
 *
 * @param {Error} err - Error crudo del proveedor.
 * @param {object} ctx - { provider, model, phase } contexto de la llamada.
 */
function logInternalGatewayError(err, ctx = {}) {
  const provider = ctx.provider || 'unknown';
  const model = ctx.model || 'unknown';
  const status = extractStatus(err);
  const incognito = !!ctx.incognito;

  // Log estructurado requerido por la especificación de seguridad.
  // H6/#477: en turnos incógnito el mensaje crudo del vendor NO se loguea
  // (los errores 4xx pueden ecoar fragmentos del prompt); solo su clase.
  console.error('[INTERNAL_GATEWAY_ERROR]', {
    provider,
    model,
    status,
    incognito: incognito || undefined,
    error: incognito
      ? `${REDACTED} (status=${status ?? 'n/a'})`
      : (err && err.message ? err.message : String(err)),
  });

  // Stack trace completo solo en consola del servidor (sin contenido del turno).
  if (err && err.stack && !incognito) {
    console.error('[INTERNAL_GATEWAY_ERROR] stack:', err.stack);
  }
}

/**
 * Envuelve un error crudo de proveedor en un Error interno seguro de
 * propagar por la cadena de fallback del ModelRouter.
 *
 * FIX (2026-08-20): los providers (alibaba.js) importaban esta función pero
 * no existía en el module.exports, de modo que CADA error upstream lanzaba
 * `TypeError: wrapProviderError is not a function` que ocultaba la causa real
 * (401/413/429) y dejaba `status: null` en los logs internos.
 *
 * El error devuelto:
 *   - Conserva el `status` HTTP extraído (para clasificación de capacidad).
 *   - Mantiene el mensaje del vendor SOLO para logs de servidor; nunca llega
 *     al cliente porque los boundaries (modelRouter/chat.js) sanitizan.
 *   - Registra el contexto interno completo vía logInternalGatewayError.
 *
 * @param {Error} err - Error crudo del proveedor.
 * @param {string} model - Modelo que falló.
 * @param {string} phase - Fase de la llamada ('call-stream-init', etc.).
 * @param {object} [ctx] - { incognito } — H6/#477: en incógnito el mensaje
 *   del vendor NO viaja en el error ni en el log (solo status/clase).
 * @returns {Error} Error listo para re-lanzar al router.
 */
function wrapProviderError(err, model = 'unknown', phase = 'unknown', ctx = {}) {
  const status = extractStatus(err);
  const isAbort = isClientAbortError(err);
  const vendorMessage = err && err.message ? err.message : String(err);
  // En incógnito el cuerpo se redacta, pero se conserva el marcador de aborto:
  // isClientAbortError() del router depende de que el mensaje lo contenga.
  const safeBody = ctx.incognito
    ? `${REDACTED} (status=${status ?? 'n/a'}${isAbort ? ', aborted' : ''})`
    : vendorMessage;
  const wrapped = new Error(`[alibaba:${model}:${phase}] status=${status ?? 'n/a'}: ${safeBody}`);
  wrapped.status = status;
  wrapped.originalError = err;
  logInternalGatewayError(err, { provider: 'alibaba', model, phase, incognito: !!ctx.incognito });
  return wrapped;
}

/**
 * Sanitiza cualquier error de gateway y devuelve SIEMPRE un mensaje seguro
 * de marca. Este es el ÚNICO texto de error que puede llegar al cliente.
 * (Compat: devuelve string; para contenido+código usar userFacingError.)
 *
 * @param {Error} err - Error crudo del proveedor.
 * @param {object} ctx - { provider, model, phase }.
 * @returns {string} Mensaje seguro para el usuario.
 */
function handleGatewayError(err, ctx = {}) {
  logInternalGatewayError(err, ctx);
  return userFacingError(err).content;
}

/**
 * Escribe el par de eventos SSE sanitizados (error + done) y cierra el stream.
 * Garantiza que el cliente móvil reciba un cierre limpio y desbloquee su UI.
 * Si se pasa `err`, el evento error lleva contenido+código según su clase
 * (caído vs ocupado); sin `err` preserva el comportamiento anterior.
 *
 * @param {object} res - Response Express con headers SSE ya enviados.
 * @param {function} sendSse - Helper del route para escribir + flush.
 * @param {string} [partialText] - Texto parcial ya streameado (si existe).
 * @param {Error} [err] - Error crudo para clasificar (opcional).
 */
function sendSanitizedSseError(res, sendSse, partialText = '', err = null) {
  try {
    const out = err ? userFacingError(err) : { content: USER_FACING_ERROR_MESSAGE, code: 'error' };
    sendSse({ type: 'error', content: out.content, code: out.code });
    sendSse({ type: 'done', content: partialText || '', sources: [] });
  } catch (_) {
    // El socket pudo cerrarse; no hacer nada.
  }
  try {
    res.end();
  } catch (_) {
    // Ya cerrado.
  }
}

/**
 * Escudo defensivo final: detecta si un string contiene posibles fugas de
 * datos de vendor (URLs de API, org IDs, keys, payloads). Se usa para
 * auditar cualquier texto que, por error de programación, pudiera escribirse
 * al stream. Devuelve true si el texto parece contener datos sensibles.
 */
function containsVendorLeak(text) {
  if (typeof text !== 'string' || !text) return false;
  const leakPatterns = [
    /api\.groq\.com/i,
    /api\.deepseek\.com/i,
    // FIX (2026-08-25): el endpoint real usa el subdominio dashscope-intl;
    // el patrón anterior solo casaba dashscope.aliyuncs.com y dejaba pasar
    // fugas con URL del vendor.
    /dashscope(-intl)?\.aliyuncs\.com/i,
    /aliyuncs\.com/i,
    /generativelanguage\.googleapis\.com/i,
    /organization\s*[:=]/i,
    /org[_-]?[a-z0-9]{8,}/i,
    /gsk_[A-Za-z0-9]{20,}/, // Groq API key prefix
    /sk-[A-Za-z0-9]{20,}/, // OpenAI/DeepSeek key prefix
    /x-ratelimit/i,
    /tokens per minute/i,
    /please reduce the length of the messages/i,
    /request too large/i,
  ];
  return leakPatterns.some((re) => re.test(text));
}

module.exports = {
  USER_FACING_ERROR_MESSAGE,
  SERVICE_DOWN_MESSAGE,
  classifyUserError,
  userFacingError,
  extractStatus,
  isClientAbortError,
  isCapacityError,
  logInternalGatewayError,
  wrapProviderError,
  handleGatewayError,
  sendSanitizedSseError,
  containsVendorLeak,
};

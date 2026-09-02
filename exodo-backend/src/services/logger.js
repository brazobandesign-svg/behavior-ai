// src/services/logger.js
// H6 / #477 — Scrubbing de logs para chats privados (incógnito).
//
// REGLA: en turnos donde el usuario es anónimo (guest / is_anonymous) o el
// cliente marca isIncognito=true, NINGÚN texto del usuario o de la IA puede
// llegar a stdout / Cloud Run Logging. Los valores portadores de contenido
// del turno se sustituyen por [REDACTED_INCOGNITO] y los errores crudos
// (vendor/DB pueden ecoar fragmentos del prompt) se loguean solo como clase.
//
// Uso en el turno (chat.js):
//   const chatLog = createChatLogger(isIncognitoTurn);
//   chatLog.log('[chat][perf] ...', metadatos);      // metadatos: pasan tal cual
//   chatLog.content(enhancedMessage);                 // => '[REDACTED_INCOGNITO]'
//   chatLog.errorDetail(err);                         // => '[REDACTED_INCOGNITO] (status=400)'
//   logInternalGatewayError(err, { ..., incognito: chatLog.incognito });

'use strict';

const REDACTED = '[REDACTED_INCOGNITO]';

/**
 * Logger con alcance de turno. `incognito` se resuelve UNA vez por request
 * (req.body.isIncognito === true || req.user.anonymous === true) y sella
 * todos los valores sensibles de ese turno.
 */
function createChatLogger(incognito) {
  const flag = !!incognito;

  return {
    incognito: flag,

    /** Valor portador de contenido del turno: prompt, respuesta, adjuntos. */
    content(value) {
      if (!flag || value == null) return value;
      return REDACTED;
    },

    /** Mensaje de error crudo: en incógnito solo expone su clase/status. */
    errorDetail(err) {
      if (!flag) return err && err.message ? err.message : String(err);
      const kind = (err && (err.status || err.code)) || 'sin-clase';
      return `${REDACTED} (${kind})`;
    },

    // Passthrough de metadatos seguros (el scrub es explícito por valor).
    log: (...args) => console.log(...args),
    warn: (...args) => console.warn(...args),
    error: (...args) => console.error(...args),
  };
}

module.exports = { REDACTED, createChatLogger };

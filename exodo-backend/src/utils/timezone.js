'use strict';

/**
 * src/utils/timezone.js
 *
 * Cálculo inviolable de fecha local por huso horario en el servidor.
 * Inmune a que el usuario adelante o retrase la hora en los ajustes de su celular:
 * utiliza Date.now() atómico del servidor proyectado en la zona horaria del usuario.
 */

function getLocalDateKey(timeZone, nowMs = Date.now()) {
  if (timeZone && typeof timeZone === 'string') {
    try {
      const formatter = new Intl.DateTimeFormat('en-CA', {
        timeZone: timeZone.trim(),
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
      });
      return formatter.format(new Date(nowMs));
    } catch (_) {
      // Fallback si la zona horaria enviada no es IANA válida
    }
  }

  // Fallback prioritario: AST (UTC-4, República Dominicana)
  try {
    return new Intl.DateTimeFormat('en-CA', {
      timeZone: 'America/Santo_Domingo',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(new Date(nowMs));
  } catch (_) {
    return new Date(nowMs).toISOString().slice(0, 10);
  }
}

module.exports = {
  getLocalDateKey,
};

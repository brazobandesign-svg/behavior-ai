/**
 * C9: límite diario de mensajes para invitados, aplicado EN SERVIDOR.
 * Antes el tope vivía en el dispositivo (SharedPreferences/código muerto en
 * supabase_service.dart): reinstalar la app o tocar prefs lo saltaba.
 *
 * - Solo aplica a req.user.isGuest (usuarios registrados pasan de largo).
 * - Contador por IP en memoria del proceso, con reset al cambiar el día (UTC).
 * - Tope configurable con GUEST_DAILY_MESSAGES (default 30: fase de pruebas
 *   generosa según decisión cerrada #6 de la auditoría maestra).
 */
const DAILY_LIMIT = (() => {
  const n = parseInt(process.env.GUEST_DAILY_MESSAGES, 10);
  return Number.isFinite(n) && n > 0 ? n : 30;
})();

const _guestUsage = new Map(); // ip -> { date: 'YYYY-MM-DD', count }

function todayKey() {
  return new Date().toISOString().slice(0, 10);
}

function getIp(req) {
  // trust proxy=1 está activo (fix C4); req.ip ya resuelve la IP real del cliente.
  return req.ip || req.socket?.remoteAddress || 'unknown';
}

function guestLimit(req, res, next) {
  const isGuest = !!req.user?.isGuest;
  if (!isGuest) return next();

  const ip = getIp(req);
  const today = todayKey();

  // Poda perezosa: si el mapa crece demasiado, tira entradas de días pasados.
  if (_guestUsage.size > 5000) {
    for (const [k, v] of _guestUsage) {
      if (v.date !== today) _guestUsage.delete(k);
    }
  }

  let entry = _guestUsage.get(ip);
  if (!entry || entry.date !== today) {
    entry = { date: today, count: 0 };
    _guestUsage.set(ip, entry);
  }

  if (entry.count >= DAILY_LIMIT) {
    return res.status(429).json({
      error: 'guest_daily_limit',
      message:
        'Alcanzaste el límite diario de mensajes como invitado. Crea una cuenta gratuita para continuar.',
      limit: DAILY_LIMIT,
    });
  }

  entry.count += 1;
  req.guestUsageRemaining = Math.max(0, DAILY_LIMIT - entry.count);
  next();
}

module.exports = { guestLimit, DAILY_LIMIT };

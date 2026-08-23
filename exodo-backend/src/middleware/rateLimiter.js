/**
 * Rate Limiter — Éxodo by Behavior
 *
 * Piso global PRE-auth en /api/*: se aplica ANTES del middleware auth, por lo
 * que req.user no existe aquí y el keying es por IP (req.ip).
 *  - Con `trust proxy` activo (producción/Railway) cada cliente aporta su IP
 *    real → bucket por cliente. 60 req/min por IP.
 *  - En desarrollo (adb reverse / localhost) todo llega como 127.0.0.1 → el
 *    piso es compartido pero generoso; los límites estrictos por usuario
 *    pertenecen a capas post-auth (planGuard, limiters por ruta).
 * Incluye cabecera Retry-After en 429.
 *
 * Dependencia: npm install express-rate-limit
 */
const rateLimit = require('express-rate-limit');

const WINDOW_MS = 60 * 1000; // 1 minuto
const MAX_REQUESTS_PER_WINDOW = 60;

/**
 * Piso global por IP (pre-auth). Express-rate-limit v7+ requiere
 * `keyGenerator` y `handler` personalizados.
 */
const chatRateLimiter = rateLimit({
  windowMs: WINDOW_MS,
  max: MAX_REQUESTS_PER_WINDOW,
  keyGenerator: (req) => {
    return req.user?.userId || req.ip || req.connection?.remoteAddress || 'unknown';
  },
  standardHeaders: true, // devuelve RateLimit-* headers
  legacyHeaders: false,
  // Desactivar TODAS las validaciones de express-rate-limit v8+
  // (keyGeneratorIpFallback crashea en localhost con IPv6)
  validate: false,
  handler: (req, res, _next) => {
    // Fix: antes Math.ceil(60 / 1000) = 1 segundo (bug B14).
    const retryAfter = Math.ceil(WINDOW_MS / 1000); // 60 segundos
    res.set('Retry-After', String(retryAfter));
    res.status(429).json({
      error: 'too_many_requests',
      message: 'Demasiadas peticiones. Intenta de nuevo en un minuto.',
      retryAfter,
    });
  },
});

module.exports = { chatRateLimiter };

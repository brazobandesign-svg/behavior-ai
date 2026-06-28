/**
 * Rate Limiter — Éxodo by Behavior
 *
 * Limita peticiones por minuto:
 *   - Usuarios autenticados (userId):    60 req/min
 *   - Usuarios anónimos (IP):            10 req/min
 *   - Incluye cabecera Retry-After en 429.
 *
 * Dependencia: npm install express-rate-limit
 */
const rateLimit = require('express-rate-limit');

/**
 * Limita por userId (autenticado) o IP (anónimo/desarrollo).
 * Express-rate-limit v7+ requiere `keyGenerator` y `handler` personalizados.
 */
const chatRateLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minuto
  max: (req) => {
    // Autenticados tienen cupo más alto
    if (req.user?.userId) return 60;
    return 10; // anónimos: 10 por minuto
  },
  keyGenerator: (req) => {
    // Usa userId si existe, si no la IP
    return req.user?.userId || req.ip || req.connection?.remoteAddress || 'unknown';
  },
  standardHeaders: true, // devuelve RateLimit-* headers
  legacyHeaders: false,
  handler: (req, res, _next) => {
    const retryAfter = Math.ceil(60 / 1000); // 60 segundos
    res.set('Retry-After', String(retryAfter));
    res.status(429).json({
      error: 'too_many_requests',
      message: 'Demasiadas peticiones. Intenta de nuevo en un minuto.',
      retryAfter,
    });
  },
});

module.exports = { chatRateLimiter };

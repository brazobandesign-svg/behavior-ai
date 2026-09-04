const { USER_FACING_ERROR_MESSAGE, logInternalGatewayError } = require('../services/errorSanitizer');

/**
 * Middleware centralizado de manejo de errores.
 * Captura errores no manejados en las rutas y los formatea.
 *
 * SEGURIDAD (Fix 2026-08-19): el detalle crudo (stack, mensajes de vendor)
 * se registra SOLO en la consola del servidor. El cliente recibe siempre un
 * mensaje genérico de marca; jamás detalles internos, ni siquiera en dev.
 */
function errorHandler(err, req, res, _next) {
  logInternalGatewayError(err, { provider: 'gateway', model: 'express', phase: `${req.method} ${req.path}` });

  if (err.type === 'entity.parse.failed') {
    return res.status(400).json({ error: 'JSON inválido en el body del request' });
  }

  if (err.code === 'LIMIT_FILE_SIZE') {
    return res.status(400).json({
      error: 'El adjunto supera el límite permitido (15MB).',
    });
  }

  if (err.type === 'entity.too.large' || err.status === 413) {
    return res.status(413).json({
      error: 'El mensaje o adjunto excede el tamaño máximo permitido (límite excedido).',
    });
  }

  res.status(err.status || 500).json({
    error: USER_FACING_ERROR_MESSAGE,
  });
}

module.exports = errorHandler;

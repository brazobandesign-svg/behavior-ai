/**
 * Middleware centralizado de manejo de errores.
 * Captura errores no manejados en las rutas y los formatea.
 */
function errorHandler(err, req, res, _next) {
  console.error(`[ERROR] ${req.method} ${req.path}:`, err.message);

  if (err.type === 'entity.parse.failed') {
    return res.status(400).json({ error: 'JSON inválido en el body del request' });
  }

  res.status(err.status || 500).json({
    error: err.message || 'Error interno del servidor',
    ...(process.env.NODE_ENV !== 'production' && { stack: err.stack }),
  });
}

module.exports = errorHandler;

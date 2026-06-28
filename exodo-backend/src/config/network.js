require('dotenv').config();

/**
 * Configuración de red del backend.
 * Permite al usuario cambiar host/puerto/CORS sin tocar código.
 *
 * Uso típico:
 *   .env (LAN demo):     BACKEND_HOST=0.0.0.0  PORT=3000
 *   .env (producción):   BACKEND_HOST=0.0.0.0  PORT=8080  NODE_ENV=production
 *
 * El frontend debe apuntar a la URL que se imprime en consola al arrancar
 * (ver src/index.js banner).
 */
const HOST = process.env.BACKEND_HOST || '0.0.0.0';
const PORT = parseInt(process.env.PORT, 10) || 3000;
const NODE_ENV = process.env.NODE_ENV || 'development';

// CORS: en desarrollo permite todo; en producción usar lista blanca.
// Formato: CORS_ORIGIN=https://exodo.app,https://admin.exodo.app
const corsOrigins = (process.env.CORS_ORIGIN || '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

module.exports = {
  HOST,
  PORT,
  NODE_ENV,
  isProduction: NODE_ENV === 'production',
  corsOrigins: corsOrigins.length ? corsOrigins : null, // null = permitir todo
};
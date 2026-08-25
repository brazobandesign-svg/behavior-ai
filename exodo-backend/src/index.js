require('dotenv').config({ override: true });
const express = require('express');
const cors = require('cors');
const chatRoutes = require('./routes/chat');
const stripeRoutes = require('./routes/stripe');
const userRoutes = require('./routes/user');
const artifactsRoutes = require('./routes/artifacts');
const expedientesRoutes = require('./routes/expedientes');
const voiceRoutes = require('./routes/voice');
const imagesRoutes = require('./routes/images');
const copilotRoutes = require('./routes/copilot');
const errorHandler = require('./middleware/errorHandler');
const { chatRateLimiter } = require('./middleware/rateLimiter');
const { HOST, PORT, NODE_ENV, corsOrigins } = require('./config/network');

const app = express();

// C4: Detrás de reverse proxy (Railway) confiamos en 1 salto para que req.ip
// sea la IP REAL del cliente. Sin esto, req.ip es la IP del load balancer y
// TODOS los usuarios comparten un solo bucket del rate limiter (429 masivos).
// TRUST_PROXY=false la desactiva (depuración de spoofing de X-Forwarded-For).
app.set('trust proxy', process.env.TRUST_PROXY === 'false' ? false : 1);

// Middlewares globales
// CORS: fail-closed en producción — sin CORS_ORIGIN configurado, los navegadores
// quedan bloqueados (las apps nativas no usan CORS y no se afectan).
app.use(cors({
  origin: corsOrigins || (NODE_ENV === 'production' ? false : true),
  credentials: true,
}));

// Security headers (equivalente Helmet para API JSON, sin dependencia extra).
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  next();
});

app.use(express.json({
  limit: '15mb',
  verify: (req, res, buf) => {
    // Conservar el buffer RAW para la verificación de firma de Stripe.
    req.rawBody = buf;
  },
}));
app.use(express.urlencoded({ limit: '1mb', extended: true }));

// Rate limiter global en /api/* (se aplica antes de auth)
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url} - Auth: ${req.headers.authorization ? 'SI' : 'NO'}`);
  res.on('finish', () => {
    console.log(`[${new Date().toISOString()}] ${req.method} ${req.url} -> STATUS: ${res.statusCode}`);
  });
  next();
});
app.use('/api/', (req, res, next) => {
  // El webhook de Stripe y el proxy de Copilot NO pasan por el rate limiter de chat
  if (req.path === '/stripe/webhook' || req.path.startsWith('/copilot')) return next();
  return chatRateLimiter(req, res, next);
});

// Rutas
app.use('/api/chat', chatRoutes);
app.use('/api/stripe', stripeRoutes);
app.use('/api/user', userRoutes);
app.use('/api/artifacts', artifactsRoutes);
app.use('/api/expedientes', expedientesRoutes);
app.use('/api/voice', voiceRoutes);
app.use('/api/images', imagesRoutes);
app.use('/api/copilot', copilotRoutes);

// Health check — Bible: verificar que el servidor está vivo.
// Mínima superficie: sin env/versión/timestamps (auditoría A4).
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// Error handler centralizado
app.use(errorHandler);

// Iniciar servidor
app.listen(PORT, HOST, () => {
  runStartupChecks();
  // Banner con la URL exacta para el frontend (evita el problema del LG V60
  // apuntando a 'localhost' que no resuelve desde el dispositivo).
  const lanIps = getLanIps();
  console.log('');
  console.log('  ╔════════════════════════════════════════════════════════════╗');
  console.log('  ║  Éxodo Backend v1.0.0                                     ║');
  console.log(`  ║  Entorno:    ${NODE_ENV.padEnd(48)}║`);
  console.log(`  ║  Host:       ${HOST.padEnd(48)}║`);
  console.log(`  ║  Puerto:     ${String(PORT).padEnd(48)}║`);
  console.log('  ║                                                            ║');
  console.log('  ║  Endpoints disponibles:                                    ║');
  console.log(`  ║    • Local:       http://localhost:${PORT}/api/chat${' '.repeat(Math.max(0, 17 - String(PORT).length))}║`);
  if (lanIps.length > 0) {
    for (const ip of lanIps) {
      const line = `http://${ip}:${PORT}/api/chat`;
      console.log(`  ║    • LAN:         ${line.padEnd(48)}║`);
    }
  }
  console.log('  ║    • Health:      /health                                 ║');
  console.log('  ║                                                            ║');
  console.log('  ║  ⚠️  El FRONTEND debe usar la URL LAN (no localhost)      ║');
  console.log('  ║      cuando se ejecute en un dispositivo físico.            ║');
  console.log('  ╚════════════════════════════════════════════════════════════╝');
  console.log('');
});


/**
 * Verificaciones de configuración al arrancar.
 * Revisa que las API keys esenciales estén presentes y alerta si falta alguna.
 */
function runStartupChecks() {
  const { ALIBABA_CONFIG } = require('./config/models');
  const checks = [];

  const hasAlibabaKey = process.env.DASHSCOPE_API_KEY ||
                        process.env.ALIBABA_FREE_KEY ||
                        process.env.ALIBABA_API_KEY ||
                        ALIBABA_CONFIG.apiKey;
  if (!hasAlibabaKey) {
    checks.push('⚠️  DASHSCOPE_API_KEY / ALIBABA_API_KEY no configurada — Modelos Free Tier no disponibles.');
  }
  if (!process.env.GEMINI_API_KEY && !process.env.GOOGLE_API_KEY) {
    checks.push('⚠️  GEMINI_API_KEY / GOOGLE_API_KEY no configurada — Fallback de emergencia no disponible.');
  }
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_KEY) {
    checks.push('⚠️  SUPABASE_URL o SUPABASE_SERVICE_KEY no configurados — auth y DB deshabilitados.');
  }

  if (checks.length > 0) {
    console.log('  ┌──────────────────────────────────────────────────────────┐');
    checks.forEach((msg) => {
      console.log(`  │ ${msg.padEnd(57)}│`);
    });
    console.log('  └──────────────────────────────────────────────────────────┘');
  }
}

/**
 * Devuelve las IPs privadas (no loopback) de la máquina para que el
 * usuario sepa qué URL configurar en el frontend.
 */
function getLanIps() {
  const os = require('os');
  const ifaces = os.networkInterfaces();
  const ips = [];
  for (const name of Object.keys(ifaces)) {
    for (const iface of ifaces[name]) {
      // IPv4, no loopback, no virtual
      if (iface.family === 'IPv4' && !iface.internal && !name.startsWith('Virtual')) {
        ips.push(iface.address);
      }
    }
  }
  return ips;
}
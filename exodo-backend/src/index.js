require('dotenv').config({ override: true });
const express = require('express');
const cors = require('cors');
const chatRoutes = require('./routes/chat');
const errorHandler = require('./middleware/errorHandler');
const { chatRateLimiter } = require('./middleware/rateLimiter');
const { HOST, PORT, NODE_ENV, corsOrigins } = require('./config/network');

const app = express();

// Middlewares globales
// CORS configurado: en dev permite todo, en prod respeta lista blanca.
app.use(cors({
  origin: corsOrigins || true, // true = cualquiera (dev); array = whitelist (prod)
  credentials: true,
}));
app.use(express.json({ limit: '10mb' }));

// Rate limiter global en /api/* (se aplica antes de auth)
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url} - Auth: ${req.headers.authorization ? 'SI' : 'NO'}`);
  res.on('finish', () => {
    console.log(`[${new Date().toISOString()}] ${req.method} ${req.url} -> STATUS: ${res.statusCode}`);
  });
  next();
});
app.use('/api/', chatRateLimiter);

// Rutas
app.use('/api/chat', chatRoutes);

// Health check — Bible: verificar que el servidor está vivo
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'exodo-backend',
    version: '1.0.0',
    env: NODE_ENV,
    timestamp: new Date().toISOString(),
  });
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
  const checks = [];

  if (!process.env.MISTRAL_API_KEY) {
    checks.push('⚠️  MISTRAL_API_KEY no configurada — Genesis G1.1 (Mistral) no disponible.');
  }
  if (!process.env.GROQ_API_KEY) {
    checks.push('⚠️  GROQ_API_KEY no configurada — fallbacks de Groq no disponibles.');
  }
  if (!process.env.DEEPSEEK_API_KEY) {
    checks.push('⚠️  DEEPSEEK_API_KEY no configurada — modelos DeepSeek de XPi no disponibles.');
  }
  if (!process.env.GOOGLE_AI_API_KEY) {
    checks.push('⚠️  GOOGLE_AI_API_KEY no configurada — el clasificador de intención usará fallback local (keyword-based).');
  }
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_KEY) {
    checks.push('⚠️  SUPABASE_URL o SUPABASE_SERVICE_KEY no configurados — auth y DB deshabilitados.');
  }
  if (!process.env.ANTHROPIC_API_KEY) {
    checks.push('⚠️  ANTHROPIC_API_KEY no configurada — Claude Sonnet no disponible para Hazak.');
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
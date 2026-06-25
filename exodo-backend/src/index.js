require('dotenv').config();
const express = require('express');
const cors = require('cors');
const chatRoutes = require('./routes/chat');
const errorHandler = require('./middleware/errorHandler');

const app = express();
const PORT = process.env.PORT || 3000;

// Middlewares globales
app.use(cors());
app.use(express.json({ limit: '10mb' }));

// Rutas
app.use('/api/chat', chatRoutes);

// Health check — Bible: verificar que el servidor está vivo
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'exodo-backend',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
  });
});

// Error handler centralizado
app.use(errorHandler);

// Iniciar servidor
app.listen(PORT, '0.0.0.0', () => {
  console.log(`\n  ╔════════════════════════════════════════╗`);
  console.log(`  ║  Éxodo Backend v1.0.0                  ║`);
  console.log(`  ║  Puerto: ${PORT}                           ║`);
  console.log(`  ║  Éxodo by Behavior                     ║`);
  console.log(`  ╚════════════════════════════════════════╝\n`);
});

'use strict';

const express = require('express');
const https = require('https');
const auth = require('../middleware/auth');
const { chatRateLimiter } = require('../middleware/rateLimiter');

const router = express.Router();

const ALIBABA_ENDPOINT = process.env.ALIBABA_KIMI_ENDPOINT || 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions';
const SERVER_KEY = process.env.DASHSCOPE_API_KEY ||
                   process.env.ALIBABA_FREE_KEY ||
                   process.env.ALIBABA_API_KEY ||
                   '';

if (!SERVER_KEY) {
  console.warn('[Copilot Kimi Proxy] Sin DASHSCOPE_API_KEY/ALIBABA_*_KEY: el proxy responderá 503 hasta configurarla.');
}

/**
 * POST /api/copilot/kimi | /api/copilot/chat/completions
 * Sanitiza parámetros incompatibles de VS Code Copilot (como top_p)
 * y reenvía en streaming directo hacia Alibaba Cloud MaaS (Kimi K3).
 *
 * SEGURIDAD: requiere JWT válido (auth) + rate limit. La llave del
 * servidor NUNCA se revela ni se inyecta por petición anónima; el
 * header entrante del cliente se descarta siempre.
 */
router.post(['/kimi', '/chat/completions'], auth, chatRateLimiter, async (req, res) => {
  // Gate duro (QA adversarial 1.3): el middleware auth ETIQUETA a los
  // anónimos como isGuest y sigue; aquí SÍ los rechazamos antes de tocar
  // Alibaba. Sin esto, cualquier anónimo quema la cuota del servidor.
  if (!req.user || req.user.isGuest || !req.user.userId) {
    return res.status(401).json({ error: 'authentication_required' });
  }

  if (!SERVER_KEY) {
    return res.status(503).json({ error: 'proxy_unavailable' });
  }

  const body = { ...req.body };

  // Eliminar top_p para evitar el error 400 en Kimi K3
  delete body.top_p;

  // Asegurar modelo kimi-k3 si viene vacío o genérico
  if (!body.model || String(body.model).includes('kimi')) {
    body.model = 'kimi-k3';
  }

  const payload = JSON.stringify(body);
  const targetUrl = new URL(ALIBABA_ENDPOINT);

  const options = {
    hostname: targetUrl.hostname,
    port: targetUrl.port || 443,
    path: targetUrl.pathname,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${SERVER_KEY}`,
      'Content-Length': Buffer.byteLength(payload),
      'Accept': req.headers.accept || 'application/json, text/event-stream',
    },
  };

  const proxyReq = https.request(options, (proxyRes) => {
    res.status(proxyRes.statusCode);
    for (const [k, v] of Object.entries(proxyRes.headers)) {
      try {
        res.setHeader(k, v);
      } catch (_) {}
    }
    proxyRes.pipe(res);
  });

  proxyReq.on('error', (err) => {
    console.error('[Copilot Kimi Proxy] Error conectando a Alibaba:', err.message);
    if (!res.headersSent) {
      res.status(502).json({ error: 'proxy_error' });
    } else {
      res.end();
    }
  });

  res.on('close', () => {
    if (!res.writableEnded) {
      proxyReq.destroy();
    }
  });

  proxyReq.write(payload);
  proxyReq.end();
});

module.exports = router;

'use strict';

const express = require('express');
const https = require('https');

const router = express.Router();

const ALIBABA_ENDPOINT = process.env.ALIBABA_KIMI_ENDPOINT || 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions';
const DEFAULT_KEY = process.env.DASHSCOPE_API_KEY ||
                    process.env.ALIBABA_FREE_KEY ||
                    process.env.ALIBABA_API_KEY ||
                    '';

/**
 * POST /api/copilot/kimi or /api/copilot/chat/completions
 * Sanitiza parámetros incompatibles de VS Code Copilot (como top_p)
 * y reenvía en streaming directo hacia Alibaba Cloud MaaS (Kimi K3).
 */
async function handleKimiProxy(req, res) {
  const body = { ...req.body };

  // Eliminar top_p para evitar el error 400 en Kimi K3
  delete body.top_p;

  // Asegurar modelo kimi-k3 si viene vacío o genérico
  if (!body.model || body.model.includes('kimi')) {
    body.model = 'kimi-k3';
  }

  const payload = JSON.stringify(body);
  const targetUrl = new URL(ALIBABA_ENDPOINT);
  
  // Usar la API key del header de Copilot si está presente, o el fallback del .env
  const authHeader = req.headers.authorization && !req.headers.authorization.includes('${input')
    ? req.headers.authorization
    : `Bearer ${DEFAULT_KEY}`;

  const options = {
    hostname: targetUrl.hostname,
    port: targetUrl.port || 443,
    path: targetUrl.pathname,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': authHeader,
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
      res.status(502).json({ error: 'proxy_error', message: err.message });
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
}

router.use(handleKimiProxy);

module.exports = router;

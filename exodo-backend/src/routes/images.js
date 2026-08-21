'use strict';

/**
 * src/routes/images.js
 *
 * Endpoint de generación de imágenes con DashScope (Plan Hazak):
 *   - POST /api/images/generate
 */

const express = require('express');
const auth = require('../middleware/auth');
const { planGuard } = require('../middleware/planGuard');
const { generateImage } = require('../services/imageGen');
const { chatRateLimiter } = require('../middleware/rateLimiter');

const router = express.Router();

router.post('/generate', auth, planGuard, chatRateLimiter, async (req, res) => {
  try {
    const { prompt, size } = req.body || {};
    if (!prompt || typeof prompt !== 'string' || !prompt.trim()) {
      return res.status(400).json({ error: 'El campo "prompt" es requerido' });
    }

    const { userId, plan } = req.user || {};

    const result = await generateImage(prompt, { size });

    return res.status(200).json({
      url: result.url,
      model: result.model,
      prompt: prompt.trim(),
    });
  } catch (err) {
    console.error('[images] Error generando imagen:', err.message);
    return res.status(500).json({ error: 'image_generation_failed', message: err.message });
  }
});

module.exports = router;

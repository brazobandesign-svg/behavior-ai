'use strict';

/**
 * src/routes/images.js
 *
 * Endpoint de generación de imágenes con DashScope (Plan XPi):
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

    // P1 auditoría: enforce de plan antes de procesar el prompt (coste real
    // de DashScope solo para suscriptores XPi).
    if (plan !== 'hazak') {
      return res.status(403).json({
        error: 'plan_upgrade_required',
        message: 'La generación de imágenes requiere una suscripción al Plan XPi activa.',
      });
    }

    // Tope mensual de imágenes (PLAN_CONFIG.monthlyVisionLimit): planGuard ya
    // cargó req.usage con monthlyVisionUsed/monthlyVisionLimit desde la DB.
    const visionUsed = req.usage?.monthlyVisionUsed || 0;
    const visionLimit = req.usage?.monthlyVisionLimit || 0;
    if (visionLimit > 0 && visionUsed >= visionLimit) {
      return res.status(429).json({
        error: 'image_limit_reached',
        message: `Alcanzaste tu límite de ${visionLimit} imágenes al mes. Se renueva el próximo mes.`,
      });
    }

    const result = await generateImage(prompt, { size });

    // Contabilizar la imagen generada (mismo RPC atómico que los tokens).
    try {
      const { updateTokenUsage } = require('../services/tokenCounter');
      await updateTokenUsage(userId, 0, true, req.usage);
    } catch (e) {
      console.warn('[images] No se pudo contabilizar la imagen:', e.message);
    }

    return res.status(200).json({
      url: result.url,
      model: result.model,
      prompt: prompt.trim(),
    });
  } catch (err) {
    console.error('[images] Error generando imagen:', err.message);
    return res.status(502).json({
      error: 'image_generation_failed',
      message: 'No se pudo generar la imagen. Por favor intenta de nuevo.',
    });
  }
});

module.exports = router;

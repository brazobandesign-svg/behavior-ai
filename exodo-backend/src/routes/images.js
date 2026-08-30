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

    const { userId, plan, isGuest } = req.user || {};

    // P1 auditoría: enforce de plan antes de procesar el prompt (coste real
    // de DashScope). G1.1 (free) puede generar pocas imágenes al día (3);
    // XPi 25/día. Invitados: bloqueados — Groq NO ofrece generación de
    // imágenes (solo texto/whisper), así que no hay ruta $0 para ellos.
    if (isGuest) {
      return res.status(403).json({
        error: 'plan_upgrade_required',
        message: 'La generación de imágenes requiere una cuenta gratuita. Crea una para usarla.',
      });
    }
    const dailyImagesUsed = req.usage?.dailyImagesUsed || 0;
    const dailyImagesLimit = req.usage?.dailyImagesLimit || 0;
    if (dailyImagesLimit > 0 && dailyImagesUsed >= dailyImagesLimit) {
      return res.status(429).json({
        error: 'image_daily_limit_reached',
        message: `Alcanzaste tu límite de ${dailyImagesLimit} imágenes por hoy. Se renueva mañana.`,
        dailyImagesUsed,
        dailyImagesLimit,
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

    // Contabilizar la imagen generada: contador DIARIO en memoria (planGuard
    // lo lee en cada request) + RPC atómica mensual para el registro.
    try {
      const { getMemUsageMap } = require('../middleware/planGuard');
      const mem = getMemUsageMap().get(userId);
      if (mem) {
        const today = new Date(Date.now() - 4 * 60 * 60 * 1000).toISOString().slice(0, 10);
        if (mem.lastImageReset !== today) {
          mem.dailyImagesUsed = 1;
          mem.lastImageReset = today;
        } else {
          mem.dailyImagesUsed = (mem.dailyImagesUsed || 0) + 1;
        }
      }
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

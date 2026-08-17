const express = require('express');
const router = express.Router();
const auth = require('../middleware/auth');
const { planGuard } = require('../middleware/planGuard');

/**
 * GET /api/user/usage
 * Endpoint para el embudo de conversión y vista de Ajustes/Perfil.
 * Metadatos limpios: CERO nombres de proveedores comerciales expuestos al cliente.
 */
router.get('/usage', auth, planGuard, (req, res) => {
  const isGuest = !!req.user.isGuest;
  const { plan } = req.user;
  const usage = req.usage || {};

  if (isGuest) {
    return res.json({
      isGuest: true,
      plan: 'guest',
      dailyTokensLimit: 0,
      requiresAuth: true,
      savedToCloud: false,
      proPriceUsd: 4.99,
    });
  }

  res.json({
    isGuest: false,
    plan: plan || 'genesis',
    dailyTokensUsed: usage.dailyTokensUsed || 0,
    dailyTokensLimit: usage.dailyTokensLimit || 6000,
    monthlyVisionUsed: usage.monthlyVisionUsed || 0,
    monthlyVisionLimit: usage.monthlyVisionLimit || 3,
    isDegraded: !!req.user.isDegraded,
    requiresAuth: false,
    savedToCloud: true,
    proPriceUsd: 4.99,
  });
});

module.exports = router;

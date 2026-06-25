const supabase = require('../config/supabase');
const { PLANS } = require('../config/models');

/**
 * Middleware de guardia de plan.
 * Verifica tokens diarios disponibles ANTES de llamar a cualquier API.
 * Bible sección 03: límite por tokens diarios, no por mensajes.
 * Período = fecha del día (se resetea a medianoche).
 */
async function planGuard(req, res, next) {
  const { userId, plan, anonymous } = req.user;

  // Usuarios anónimos (desarrollo) pasan sin restricción
  if (anonymous || !supabase) {
    return next();
  }

  const today = new Date().toISOString().split('T')[0]; // '2026-06-25'
  const planConfig = PLANS[plan] || PLANS.genesis;

  try {
    // Buscar o crear registro de uso para hoy
    let { data: usage, error } = await supabase
      .from('user_usage')
      .select('id, tokens_used, tokens_limit')
      .eq('user_id', userId)
      .eq('period', today)
      .single();

    if (error && error.code === 'PGRST116') {
      // No existe registro para hoy → crear uno nuevo (reseteo diario automático)
      const { data: newUsage } = await supabase
        .from('user_usage')
        .insert({
          user_id: userId,
          tokens_used: 0,
          tokens_limit: planConfig.tokensPerDay,
          period: today,
        })
        .select()
        .single();
      usage = newUsage;
    }

    if (!usage) {
      return res.status(500).json({ error: 'Error consultando uso de tokens' });
    }

    if (usage.tokens_used >= usage.tokens_limit) {
      return res.status(403).json({
        error: 'limite_alcanzado',
        message: 'Alcanzaste tu capacidad de hoy. Se reinicia mañana a las 12:00 AM.',
        upgrade_message: plan === 'genesis'
          ? 'Activa Hazak para continuar ahora sin interrupciones.'
          : null,
        reset_at: today + 'T04:00:00Z', // medianoche AST (UTC-4)
        tokens_used: usage.tokens_used,
        tokens_limit: usage.tokens_limit,
      });
    }

    // Adjuntar datos de uso al request para tokenCounter
    req.usage = {
      id: usage.id,
      tokens_used: usage.tokens_used,
      tokens_limit: usage.tokens_limit,
    };

    next();
  } catch (err) {
    console.error('[planGuard] Error:', err.message);
    return res.status(500).json({ error: 'Error verificando límite de uso' });
  }
}

module.exports = planGuard;

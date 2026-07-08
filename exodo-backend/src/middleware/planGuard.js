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

  // Usar zona horaria AST (UTC-4) para que el reset sea a medianoche local
  const now = new Date();
  const astOffset = 4 * 60 * 60 * 1000; // UTC-4
  const astDate = new Date(now.getTime() - astOffset);
  const today = astDate.toISOString().split('T')[0]; // '2026-06-25'
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
      const { data: newUsage, error: insErr } = await supabase
        .from('user_usage')
        .insert({
          user_id: userId,
          tokens_used: 0,
          tokens_limit: planConfig.tokensPerDay,
          period: today,
        })
        .select()
        .single();
      if (insErr || !newUsage) {
        console.warn(`[planGuard] No se pudo crear user_usage en DB (${insErr?.message || 'null'}). Fallback a memoria.`);
        req.usage = { id: null, tokens_used: 0, tokens_limit: planConfig.tokensPerDay };
        return next();
      }
      usage = newUsage;
    } else if (error || !usage) {
      console.warn(`[planGuard] Error consultando user_usage (${error?.message || 'null'}). Fallback a memoria para no bloquear chat.`);
      req.usage = { id: null, tokens_used: 0, tokens_limit: planConfig.tokensPerDay };
      return next();
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
    console.warn('[planGuard] Excepción en planGuard:', err.message);
    req.usage = { id: null, tokens_used: 0, tokens_limit: planConfig.tokensPerDay };
    return next();
  }
}

module.exports = planGuard;

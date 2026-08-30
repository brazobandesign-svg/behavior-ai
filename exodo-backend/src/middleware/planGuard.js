const supabase = require('../config/supabase');
const { PLAN_CONFIG } = require('../config/models');

const _memUsage = new Map();

// P1 auditoría: TTL de sincronización del caché local con el contador atómico
// en DB (RPC increment_user_usage, 005_atomic_usage.sql). En Cloud Run
// multi-instancia otras réplicas incrementan la DB; pasado este TTL se
// relee la DB en vez de confiar en el mapa local (_memUsage) indefinidamente.
const USAGE_SYNC_TTL_MS = 30_000;

function getAstDates() {
  const now = new Date();
  const astOffset = 4 * 60 * 60 * 1000; // UTC-4
  const astDate = new Date(now.getTime() - astOffset);
  const currentDate = astDate.toISOString().split('T')[0];
  const currentMonth = currentDate.substring(0, 7);
  return { currentDate, currentMonth };
}

/**
 * Middleware de Guardia de Plan con Blindaje Total para Cuentas Guest.
 * 
 * Regla de Oro:
 * - Cuentas Guest / Anónimas -> Forzadas a Groq Modo Eco ($0.00).
 * - Cuentas Registradas Free -> 6,000 tokens diarios en DeepSeek V4 Flash.
 * - Cuentas Registradas Pro -> 50,000 tokens diarios en DeepSeek V4 Pro.
 */
async function planGuard(req, res, next) {
  const { userId, plan, isGuest } = req.user;

  // 1. BLINDAJE DE GUESTS: Modo Eco directo sin tocar base de datos ni saldo de DeepSeek
  if (isGuest || plan === 'guest' || !userId) {
    req.user.isGuest = true;
    req.user.isDegraded = false;
    req.usage = {
      isGuest: true,
      dailyTokensUsed: 0,
      dailyTokensLimit: 0,
      monthlyVisionUsed: 0,
      monthlyVisionLimit: 1,
      isDegraded: false,
    };
    return next();
  }

  const isPro = (plan === 'pro' || plan === 'hazak');
  const planKey = isPro ? 'pro' : 'free';
  const config = PLAN_CONFIG[planKey];
  const { currentDate, currentMonth } = getAstDates();

  // 2. Revisar memoria para usuarios registrados (solo si está fresca; si no,
  //    re-sincronizar desde DB más abajo)
  const now = Date.now();
  let mem = _memUsage.get(userId);
  if (mem && now - (mem.ts || 0) < USAGE_SYNC_TTL_MS) {
    if (mem.lastTokenReset !== currentDate) {
      mem.dailyTokensUsed = 0;
      mem.lastTokenReset = currentDate;
    }
    if (mem.lastVisionReset !== currentMonth) {
      mem.monthlyVisionUsed = 0;
      mem.lastVisionReset = currentMonth;
    }

    const isDegraded = !isPro && (mem.dailyTokensUsed >= config.dailyTokensLimit);
    req.user.isDegraded = isDegraded;
    req.usage = {
      id: mem.id || null,
      isGuest: false,
      dailyTokensUsed: mem.dailyTokensUsed,
      dailyTokensLimit: config.dailyTokensLimit,
      monthlyVisionUsed: mem.monthlyVisionUsed,
      monthlyVisionLimit: config.monthlyVisionLimit,
      isDegraded,
      _memMode: true,
      _userId: userId,
    };
    // ENFORCEMENT REAL (antes el límite era decorativo: isDegraded se calculaba
    // y nadie lo consumía). Cuota diaria agotada => 429 con mensaje claro.
    if (mem.dailyTokensUsed >= config.dailyTokensLimit) {
      return res.status(429).json({
        error: 'daily_limit_reached',
        message: `Alcanzaste tu límite diario de ${config.dailyTokensLimit.toLocaleString('en-US')} tokens. Tu cuota se renueva mañana.`,
        dailyTokensUsed: mem.dailyTokensUsed,
        dailyTokensLimit: config.dailyTokensLimit,
      });
    }
    return next();
  }

  // 3. Consultar / sincronizar DB para usuarios registrados
  try {
    let { data: usage, error } = await supabase
      .from('user_usage')
      .select('*')
      .eq('user_id', userId)
      .single();

    if (error && error.code === 'PGRST116') {
      const insertPayload = {
        user_id: userId,
        tokens_used: 0,
        tokens_limit: config.dailyTokensLimit,
        period: currentDate,
      };

      const { data: created } = await supabase
        .from('user_usage')
        .insert(insertPayload)
        .select()
        .single();

      usage = created || { id: null, tokens_used: 0, tokens_limit: config.dailyTokensLimit, period: currentDate };
    } else if (error || !usage) {
      usage = { id: null, tokens_used: 0, tokens_limit: config.dailyTokensLimit, period: currentDate };
    }

    let dailyTokensUsed = usage.tokens_used || 0;
    let monthlyVisionUsed = usage.images_used || 0;
    let lastTokenReset = usage.period || currentDate;
    let lastVisionReset = (usage.period || currentDate).substring(0, 7);

    if (lastTokenReset !== currentDate) {
      dailyTokensUsed = 0;
      lastTokenReset = currentDate;
      await supabase.from('user_usage').update({ tokens_used: 0, period: currentDate }).eq('user_id', userId);
    }

    if (lastVisionReset !== currentMonth) {
      monthlyVisionUsed = 0;
      lastVisionReset = currentMonth;
      await supabase.from('user_usage').update({ images_used: 0 }).eq('user_id', userId);
    }

    const isDegraded = !isPro && (dailyTokensUsed >= config.dailyTokensLimit);
    req.user.isDegraded = isDegraded;

    const userState = {
      id: usage.id || null,
      isGuest: false,
      dailyTokensUsed,
      dailyTokensLimit: config.dailyTokensLimit,
      monthlyVisionUsed,
      monthlyVisionLimit: config.monthlyVisionLimit,
      lastTokenReset,
      lastVisionReset,
      isDegraded,
      ts: Date.now(), // marca de frescura para USAGE_SYNC_TTL_MS
    };

    _memUsage.set(userId, userState);
    req.usage = userState;

    // ENFORCEMENT REAL: idéntico al path de caché. Cuota diaria agotada => 429.
    if (dailyTokensUsed >= config.dailyTokensLimit) {
      return res.status(429).json({
        error: 'daily_limit_reached',
        message: `Alcanzaste tu límite diario de ${config.dailyTokensLimit.toLocaleString('en-US')} tokens. Tu cuota se renueva mañana.`,
        dailyTokensUsed,
        dailyTokensLimit: config.dailyTokensLimit,
      });
    }

    next();
  } catch (err) {
    console.warn('[planGuard] Excepción en planGuard:', err.message);
    req.user.isDegraded = false;
    req.usage = {
      id: null,
      isGuest: false,
      dailyTokensUsed: 0,
      dailyTokensLimit: config.dailyTokensLimit,
      monthlyVisionUsed: 0,
      monthlyVisionLimit: config.monthlyVisionLimit,
      isDegraded: false,
    };
    return next();
  }
}

function getMemUsageMap() {
  return _memUsage;
}

module.exports = {
  planGuard,
  getMemUsageMap,
};

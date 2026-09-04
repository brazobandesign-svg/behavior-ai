const supabase = require('../config/supabase');
const { PLAN_CONFIG } = require('../config/models');

const { getLocalDateKey } = require('../utils/timezone');

const _memUsage = new Map();

// P1 auditoría: TTL de sincronización del caché local con el contador atómico
// en DB (RPC increment_user_usage, 005_atomic_usage.sql). En Cloud Run
// multi-instancia otras réplicas incrementan la DB; pasado este TTL se
// relee la DB en vez de confiar en el mapa local (_memUsage) indefinidamente.
const USAGE_SYNC_TTL_MS = 30_000;

function getLocalDates(req, nowMs = Date.now()) {
  const tz = req?.headers?.['x-timezone'] || req?.body?.timezone || req?.query?.timezone;
  const currentDate = getLocalDateKey(tz, nowMs);
  const currentMonth = currentDate.substring(0, 7);
  return { currentDate, currentMonth };
}

/**
 * Middleware de Guardia de Plan con Blindaje Total para Cuentas Guest.
 * 
 * Regla de Oro:
 * - Cuentas Guest / Anónimas -> Forzadas a Modo Eco ($0.00).
 * - Cuentas Registradas Free -> 6,000 tokens diarios.
 * - Cuentas Registradas Pro -> 50,000 tokens diarios.
 * - Visión ilimitada para todos los usuarios.
 */
async function planGuard(req, res, next) {
  const { userId, plan, isGuest } = req.user;

  // 1. BLINDAJE DE GUESTS: Modo Eco directo sin tocar base de datos ni saldo
  if (isGuest || plan === 'guest' || !userId) {
    req.user.isGuest = true;
    req.user.isDegraded = false;
    req.usage = {
      isGuest: true,
      dailyTokensUsed: 0,
      dailyTokensLimit: 0,
      monthlyVisionUsed: 0,
      monthlyVisionLimit: Infinity,
      isDegraded: false,
    };
    return next();
  }

  const isPro = (plan === 'pro' || plan === 'hazak');
  const planKey = isPro ? 'pro' : 'free';
  const config = PLAN_CONFIG[planKey];
  const { currentDate, currentMonth } = getLocalDates(req);

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

    // Reset perezoso del contador diario de imágenes (AST).
    const todayKey = currentDate;
    if (mem.lastImageReset !== todayKey) {
      mem.dailyImagesUsed = 0;
      mem.lastImageReset = todayKey;
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
      dailyImagesUsed: mem.dailyImagesUsed || 0,
      dailyImagesLimit: config.dailyImagesLimit || 0,
      isDegraded,
      _memMode: true,
      _userId: userId,
    };
    // DOCTRINA ÉXODO (soft cap): cuota agotada => isDegraded=true y el flujo
    // CONTINÚA (producción enrutará a Groq Modo Eco; jamás 429 duro).
    // El contador atómico sigue siendo el trigger de la degradación.
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
      // Contador diario de imágenes: vive en memoria. Al re-sincronizar desde
      // DB (TTL vencido) se PRESERVA el conteo del día si la entrada anterior
      // es de hoy — sin esto, cada resync regalaría 3/25 imágenes más.
      dailyImagesUsed:
        (mem && mem.lastImageReset === currentDate ? mem.dailyImagesUsed || 0 : 0),
      dailyImagesLimit: config.dailyImagesLimit || 0,
      lastImageReset: currentDate,
      lastTokenReset,
      lastVisionReset,
      isDegraded,
      ts: Date.now(), // marca de frescura para USAGE_SYNC_TTL_MS
    };

    _memUsage.set(userId, userState);
    req.usage = userState;

    // DOCTRINA ÉXODO (soft cap): idéntico al path de caché — sin 429.
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

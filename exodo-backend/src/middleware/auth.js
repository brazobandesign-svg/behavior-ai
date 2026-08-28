const supabase = require('../config/supabase');

// C1 (TTFT): caché de sesiones verificadas. Ver constantes en auth().
const _sessionCache = new Map();
const SESSION_TTL_MS = 60_000;
const SESSION_CACHE_MAX = 500;

/**
 * Middleware de autenticación.
 * Verifica JWT de Supabase Auth en el header Authorization.
 * 
 * Detección de Invitados:
 * - Si no hay token o user.is_anonymous === true -> req.user.isGuest = true, plan = 'guest'.
 * - Si es usuario registrado (Google/Apple/Email) -> req.user.isGuest = false, plan = profile.plan || 'genesis'.
 */
async function auth(req, res, next) {
  const token = req.headers.authorization?.split('Bearer ')[1];

  if (!token) {
    req.user = { userId: null, plan: 'guest', anonymous: true, isGuest: true };
    return next();
  }

  if (!supabase) {
    req.user = { userId: null, plan: 'guest', anonymous: true, isGuest: true };
    return next();
  }

  // C1 (TTFT): caché de sesión corta. Antes CADA mensaje pagaba 2 viajes de
  // red (getUser + profiles). TTL 60s: suficiente para una conversación activa,
  // corto para que cambios de plan/rol se propaguen rápido.
  const now = Date.now();
  const cached = _sessionCache.get(token);
  if (cached && now - cached.ts < SESSION_TTL_MS) {
    cached.ts = now; // deslizante mientras la conversación esté activa
    req.user = cached.reqUser;
    return next();
  }

  const __authT0 = Date.now();
  try {
    const { data: { user }, error } = await supabase.auth.getUser(token);

    if (error || !user) {
      req.user = { userId: null, plan: 'guest', anonymous: true, isGuest: true };
      return next();
    }

    const isGuest = user.is_anonymous === true;

    let profile = null;
    if (!isGuest) {
      try {
        const { data } = await supabase
          .from('profiles')
          .select('plan, full_name, onboarding')
          .eq('id', user.id)
          .single();
        profile = data;
      } catch (_) {}
    }

    req.user = {
      userId: user.id,
      email: user.email || null,
      plan: isGuest ? 'guest' : (profile?.plan || 'genesis'),
      fullName: profile?.full_name || (isGuest ? 'Invitado Éxodo' : null),
      onboarding: profile?.onboarding || null,
      anonymous: isGuest,
      isGuest: isGuest,
    };

    // Guardar en caché con tope de tamaño (evict simple del más viejo).
    if (_sessionCache.size >= SESSION_CACHE_MAX) {
      const oldest = _sessionCache.keys().next().value;
      if (oldest !== undefined) _sessionCache.delete(oldest);
    }
    _sessionCache.set(token, { reqUser: req.user, ts: Date.now() });
    const authMs = Date.now() - __authT0;
    if (authMs > 5) console.log(`[auth][perf] miss ${authMs}ms`);

    next();
  } catch (err) {
    console.error('[auth] Error verificando token:', err.message);
    // P2 auditoría: si el cliente envió token y no pudimos verificarlo por
    // un fallo de red/timeout hacia Supabase, NO degradar a guest (daría
    // cuota guest a un usuario legítimo y enmascararía el incidente).
    if (token) {
      return res.status(503).json({
        error: 'auth_service_unavailable',
        message: 'Servicio de autenticación no disponible temporalmente.',
      });
    }
    req.user = { userId: null, plan: 'guest', anonymous: true, isGuest: true };
    next();
  }
}

module.exports = auth;

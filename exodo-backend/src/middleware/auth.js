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
  const authHeader = req.headers.authorization;

  if (!authHeader) {
    req.user = { userId: null, plan: 'guest', anonymous: true, isGuest: true };
    return next();
  }

  // Si envió Authorization pero está malformado o no es Bearer
  if (!authHeader.toLowerCase().startsWith('bearer ') || authHeader.length <= 7) {
    return res.status(401).json({
      error: 'invalid_token',
      message: 'Cabecera Authorization inválida o malformada (se espera Bearer <token>)',
    });
  }

  const token = authHeader.slice(7).trim();
  if (!token) {
    return res.status(401).json({
      error: 'invalid_token',
      message: 'Token de autorización vacío',
    });
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
    // PERF (TTFT): perfilar el payload del JWT (sin verificar firma — la
    // verificación la hace getUser abajo) para conocer el `sub` ANTES del
    // roundtrip y lanzar el SELECT de profiles EN PARALELO con getUser.
    // Antes: getUser → profiles secuenciales = 2 RTT de latencia por miss
    // de caché. Si getUser falla, el perfil paralelo se descarta (no se
    // usa jamás un perfil de un token no verificado).
    let jwtSub = null;
    try {
      const payloadPart = token.split('.')[1];
      const payload = JSON.parse(Buffer.from(payloadPart, 'base64').toString('utf8'));
      if (typeof payload.sub === 'string' && payload.sub) jwtSub = payload.sub;
    } catch (_) {}

    const profilesPromise = jwtSub
      ? supabase
          .from('profiles')
          .select('plan, full_name, onboarding')
          .eq('id', jwtSub)
          .single()
          .then((r) => r.data)
          .catch(() => null)
      : Promise.resolve(null);

    const { data: { user }, error } = await supabase.auth.getUser(token);

    if (error || !user) {
      return res.status(401).json({
        error: 'invalid_token',
        message: 'Token de sesión inválido o expirado',
      });
    }

    const isGuest = user.is_anonymous === true;

    let profile = null;
    if (!isGuest && jwtSub === user.id) {
      // El SELECT ya voló en paralelo; solo falta esperarlo.
      profile = await profilesPromise;
    }

    // DECISIÓN DEL DUEÑO (30-ago): brazobandesign@gmail.com es la cuenta
    // interna sagrada — SIEMPRE Pro (hazak), incluso post-lanzamiento,
    // independientemente del plan en la DB. Lista en env para futuro.
    const adminEmails = (process.env.ADMIN_EMAILS || 'brazobandesign@gmail.com')
      .split(',').map((e) => e.trim().toLowerCase()).filter(Boolean);
    const isAdmin = !isGuest && adminEmails.includes((user.email || '').toLowerCase());

    req.user = {
      userId: user.id,
      email: user.email || null,
      plan: isAdmin ? 'hazak' : (isGuest ? 'guest' : (profile?.plan || 'genesis')),
      isAdmin,
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

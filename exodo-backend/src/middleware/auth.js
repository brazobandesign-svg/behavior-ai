const supabase = require('../config/supabase');

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
      plan: isGuest ? 'guest' : (profile?.plan || 'genesis'),
      fullName: profile?.full_name || (isGuest ? 'Invitado Éxodo' : null),
      onboarding: profile?.onboarding || null,
      anonymous: isGuest,
      isGuest: isGuest,
    };

    next();
  } catch (err) {
    console.error('[auth] Error verificando token:', err.message);
    req.user = { userId: null, plan: 'guest', anonymous: true, isGuest: true };
    next();
  }
}

module.exports = auth;

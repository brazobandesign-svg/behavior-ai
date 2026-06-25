const supabase = require('../config/supabase');

/**
 * Middleware de autenticación.
 * Verifica JWT de Supabase Auth en el header Authorization.
 * Si no hay token, permite acceso anónimo con plan genesis (para desarrollo).
 */
async function auth(req, res, next) {
  const token = req.headers.authorization?.split('Bearer ')[1];

  if (!token) {
    // Modo desarrollo: usuario anónimo con plan genesis
    req.user = { userId: null, plan: 'genesis', anonymous: true };
    return next();
  }

  if (!supabase) {
    req.user = { userId: null, plan: 'genesis', anonymous: true };
    return next();
  }

  try {
    const { data: { user }, error } = await supabase.auth.getUser(token);

    if (error || !user) {
      return res.status(401).json({ error: 'Token inválido o expirado' });
    }

    const { data: profile } = await supabase
      .from('profiles')
      .select('plan, full_name, onboarding')
      .eq('id', user.id)
      .single();

    req.user = {
      userId: user.id,
      plan: profile?.plan || 'genesis',
      fullName: profile?.full_name || null,
      onboarding: profile?.onboarding || null,
      anonymous: false,
    };

    next();
  } catch (err) {
    console.error('[auth] Error verificando token:', err.message);
    return res.status(500).json({ error: 'Error de autenticación' });
  }
}

module.exports = auth;

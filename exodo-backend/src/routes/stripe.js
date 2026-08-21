const express = require('express');
const Stripe = require('stripe');
const supabase = require('../config/supabase');
const auth = require('../middleware/auth');
const { createStripeIdempotencyMiddleware } = require('../middleware/stripeIdempotency');
const dbPool = require('../config/database');

const router = express.Router();

// Inicializar Stripe solo si hay secret key configurada
function getStripe() {
  const key = process.env.STRIPE_SECRET_KEY;
  if (!key) return null;
  return Stripe(key);
}

/**
 * POST /api/stripe/checkout
 * Crea una Stripe Checkout Session para suscripción mensual Hazak.
 * Requiere autenticación (no anónimo).
 */
router.post('/checkout', auth, async (req, res) => {
  const stripe = getStripe();
  if (!stripe) {
    return res.status(503).json({
      error: 'stripe_not_configured',
      message: 'Pasarela de pagos en configuración.',
    });
  }

  // Plan mensual ($4.99) vs anual ($49.99). isAnnual viene del body.
  const { isAnnual } = req.body || {};
  const { userId, plan, anonymous } = req.user;
  if (anonymous || !userId) {
    return res.status(401).json({ error: 'Inicia sesión para suscribirte' });
  }

  // Si ya es Hazak, no crear otra suscripción.
  if (plan === 'hazak') {
    return res.status(400).json({ error: 'Ya tienes el plan Hazak activo' });
  }

  // Resolver email del usuario autenticado si no venía en req.user.
  if (!req.user.email) {
    try {
      const { data: profile } = await supabase
        .from('profiles')
        .select('email')
        .eq('id', userId)
        .single();
      if (profile?.email) req.user.email = profile.email;
    } catch (_) {}
  }
  if (!req.user.email && typeof req.body?.email === 'string' && req.body.email.includes('@')) {
    req.user.email = req.body.email;
  }

  const frontendUrl = process.env.FRONTEND_URL || 'https://exodo.behavior.do';

  try {
    const session = await stripe.checkout.sessions.create({
      payment_method_types: ['card'],
      mode: 'subscription',
      line_items: [{
        quantity: 1,
        price_data: {
          currency: 'usd',
          unit_amount: isAnnual ? 4999 : 499, // centavos USD
          recurring: { interval: isAnnual ? 'year' : 'month' },
          product_data: {
            name: isAnnual ? 'Hazak Anual' : 'Hazak Mensual',
          },
        },
      }],
      client_reference_id: userId,
      metadata: { userId, plan: 'hazak' },
      success_url: `${frontendUrl}/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${frontendUrl}/canceled`,
      customer_email: req.user.email || undefined,
    });

    return res.json({ success: true, url: session.url, sessionId: session.id });
  } catch (err) {
    console.error('[stripe] Error creando checkout session:', err.message);
    return res.status(500).json({ error: 'Error al crear la sesión de pago' });
  }
});

/**
 * POST /api/stripe/webhook
 * Recibe webhooks de Stripe de forma IDEMPOTENTE y ATOMICA.
 * La funcion RPC `transition_subscription` es la unica capa duena de reclamar
 * el evento, transicionar la suscripcion y marcarlo (idempotencia por event_id).
 *
 * Eventos objetivo:
 *   - checkout.session.completed    -> activa la suscripcion (status 'active').
 *   - customer.subscription.deleted -> cancela la suscripcion (status 'canceled').
 */
const stripeWebhookMiddleware = (() => {
  if (!dbPool || !process.env.STRIPE_SECRET_KEY || !process.env.STRIPE_WEBHOOK_SECRET) {
    console.warn('[stripe] Idempotencia no disponible: verifica DATABASE_URL, STRIPE_SECRET_KEY y STRIPE_WEBHOOK_SECRET en .env');
    return null;
  }
  try {
    return createStripeIdempotencyMiddleware({
      stripeSecretKey: process.env.STRIPE_SECRET_KEY,
      webhookSecret: process.env.STRIPE_WEBHOOK_SECRET,
      pool: dbPool,
      logger: console,
    });
  } catch (err) {
    console.warn('[stripe] Middleware de idempotencia no disponible:', err.message);
    return null;
  }
})();

router.post('/webhook', stripeWebhookMiddleware || ((req, res) => {
  res.status(503).send('Webhook no configurado (verifica DATABASE_URL y STRIPE_* en .env)');
}));

/**
 * POST /api/stripe/portal
 * Abre el Stripe Customer Portal para gestionar/cancelar suscripción.
 */
router.post('/portal', auth, async (req, res) => {
  const stripe = getStripe();
  if (!stripe) {
    return res.status(503).json({ error: 'Stripe no configurado' });
  }

  const { userId, anonymous } = req.user;
  if (anonymous || !userId) {
    return res.status(401).json({ error: 'Autenticación requerida' });
  }

  try {
    const { data: sub } = await supabase
      .from('subscriptions')
      .select('provider_sub_id')
      .eq('user_id', userId)
      .eq('provider', 'stripe')
      .order('created_at', { ascending: false })
      .limit(1)
      .single();

    if (!sub?.provider_sub_id) {
      return res.status(404).json({ error: 'No tienes suscripción activa' });
    }

    const subscription = await stripe.subscriptions.retrieve(sub.provider_sub_id);
    const customerId = subscription.customer;

    const origin = req.headers.origin || 'https://behavior-ai-production.up.railway.app';
    const portalSession = await stripe.billingPortal.sessions.create({
      customer: customerId,
      return_url: origin,
    });

    return res.json({ url: portalSession.url });
  } catch (err) {
    console.error('[stripe] Error creando portal session:', err.message);
    return res.status(500).json({ error: 'Error al abrir el portal de gestión' });
  }
});

module.exports = router;

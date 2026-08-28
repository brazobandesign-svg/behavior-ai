const express = require('express');
const Stripe = require('stripe');
const supabase = require('../config/supabase');
const auth = require('../middleware/auth');
const { createStripeIdempotencyMiddleware } = require('../middleware/stripeIdempotency');
const dbPool = require('../config/database');
// Servicio blindado para fallback y sincronización (TAREA 2)
const stripeService = require('../services/stripeService');

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
        ...(isAnnual 
          ? {
              price_data: {
                currency: 'usd',
                unit_amount: 4999, // centavos USD
                recurring: { interval: 'year' },
                product_data: { name: 'Hazak Anual' },
              }
            } 
          : {
              // P0 auditoría: precio mensual parametrizado por entorno.
              // El fallback es el price ID de pruebas ($0.50) para no romper staging.
              price: process.env.STRIPE_PRICE_ID_MONTHLY || 'price_1U92MtBg1fTdi6UM67WbnavU',
            }
        ),
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
 * Recibe webhooks de Stripe de forma IDEMPOTENTE y ATOMICA. Blindado para Cloud Run.
 * La funcion RPC `transition_subscription` es la unica capa duena de reclamar
 * el evento, transicionar la suscripcion y marcarlo (idempotencia por event_id).
 *
 * Eventos objetivo (idempotentes):
 *   - checkout.session.completed    -> activa la suscripcion (status 'active') => plan='hazak' / is_pro=true
 *   - customer.subscription.deleted -> cancela la suscripcion (status 'canceled') => plan='free'/'genesis' / is_pro=false
 *   - customer.subscription.updated -> sincroniza estado actual (active/trialing => hazak, resto => free)
 *
 * Seguridad:
 *   - Valida firma criptográfica con stripe.webhooks.constructEvent(req.rawBody, sig, endpointSecret)
 *   - Responde 200 OK inmediato ante errores downstream para evitar reintentos de Stripe
 *   - Raw body preservado via express.json({verify: (req,res,buf)=> req.rawBody=buf}) o express.raw()
 */
const stripeWebhookMiddleware = (() => {
  const stripeSecret = process.env.STRIPE_SECRET_KEY;
  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;

  if (!stripeSecret || !webhookSecret) {
    console.warn('[stripe] Idempotencia no disponible: verifica STRIPE_SECRET_KEY y STRIPE_WEBHOOK_SECRET en .env');
    return null;
  }

  // Ruta preferida: pg Pool + RPC atómico (performance óptima, FOR UPDATE)
  if (dbPool) {
    try {
      return createStripeIdempotencyMiddleware({
        stripeSecretKey: stripeSecret,
        webhookSecret,
        pool: dbPool,
        logger: console,
      });
    } catch (err) {
      console.warn('[stripe] Middleware pg no disponible, probando fallback Supabase:', err.message);
    }
  } else {
    console.warn('[stripe] DATABASE_URL no configurado: pg Pool no disponible, usando fallback Supabase.');
  }

  // Fallback blindado: valida firma y delega a stripeService (Supabase RPC/directo)
  // Mantiene idempotencia via webhook_events + Supabase, y responde 200 OK siempre.
  console.info('[stripe] Webhook en modo fallback Supabase (sin pg Pool).');
  const stripe = Stripe(stripeSecret);
  return async function stripeSupabaseFallbackMiddleware(req, res) {
    const signature = req.headers['stripe-signature'];
    if (!signature) {
      res.status(400).json({ error: 'Falta el header Stripe-Signature' });
      return;
    }

    // Obtener rawBody de forma robusta para Cloud Run
    let rawBody = null;
    if (Buffer.isBuffer(req.rawBody)) rawBody = req.rawBody;
    else if (typeof req.rawBody === 'string') rawBody = Buffer.from(req.rawBody, 'utf8');
    else if (Buffer.isBuffer(req.body)) rawBody = req.body;
    else if (typeof req.body === 'string') rawBody = Buffer.from(req.body, 'utf8');
    else {
      console.error('[stripe] Cuerpo RAW no disponible en fallback');
      res.status(400).json({ error: 'Cuerpo RAW no disponible' });
      return;
    }

    let event;
    try {
      // Validación criptográfica blindada
      event = stripe.webhooks.constructEvent(rawBody, signature, webhookSecret);
    } catch (err) {
      console.error('[stripe] Firma inválida (fallback):', err.message);
      res.status(400).json({ error: 'Firma del webhook inválida' });
      return;
    }

    try {
      const outcome = await stripeService.processStripeEvent(event, rawBody);
      // Siempre 200 para evitar reintentos, incluso en error downstream
      res.status(200).json({ received: true, ...outcome });
    } catch (err) {
      console.error(`[stripe] Fallback error evento ${event.id}:`, err.message);
      res.status(200).json({ received: true, error: 'Error interno procesando webhook', details: err.message, processed: false });
    }
  };
})();

// Nota: el webhook debe recibir el raw body exacto. index.js ya captura req.rawBody
// via express.json({ verify: (req,res,buf)=> req.rawBody=buf }). Para Cloud Run,
// también soportamos express.raw() si se monta antes del json parser.
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

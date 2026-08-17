const express = require('express');
const Stripe = require('stripe');
const supabase = require('../config/supabase');
const auth = require('../middleware/auth');

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
    return res.status(503).json({ error: 'Stripe no configurado en el servidor' });
  }

  const { userId, plan, anonymous } = req.user;
  if (anonymous || !userId) {
    return res.status(401).json({ error: 'Inicia sesión para suscribirte' });
  }

  // Si ya es Hazak, no crear otra suscripción
  if (plan === 'hazak') {
    return res.status(400).json({ error: 'Ya tienes el plan Hazak activo' });
  }

  const priceId = process.env.STRIPE_PRICE_ID;
  if (!priceId) {
    return res.status(503).json({ error: 'Precio de Stripe no configurado' });
  }

  // URLs de retorno — el frontend pasa el origin para redirigir correctamente
  const origin = req.headers.origin || req.body?.origin || 'https://behavior-ai-production.up.railway.app';
  const successUrl = `${origin}/#/checkout/success`;
  const cancelUrl = `${origin}/#/checkout/cancel`;

  try {
    // Buscar si ya existe un customer en Stripe para este usuario
    const { data: existingSub } = await supabase
      .from('subscriptions')
      .select('provider_sub_id')
      .eq('user_id', userId)
      .eq('provider', 'stripe')
      .order('created_at', { ascending: false })
      .limit(1)
      .single();

    let customerId;
    if (existingSub?.provider_sub_id) {
      try {
        const sub = await stripe.subscriptions.retrieve(existingSub.provider_sub_id);
        customerId = sub.customer;
      } catch {
        // Suscripción vieja/cancelada, crear customer nuevo
      }
    }

    // Crear Checkout Session
    const session = await stripe.checkout.sessions.create({
      mode: 'subscription',
      line_items: [{ price: priceId, quantity: 1 }],
      success_url: successUrl,
      cancel_url: cancelUrl,
      client_reference_id: userId,
      ...(customerId ? { customer: customerId } : {}),
      metadata: {
        user_id: userId,
      },
    });

    res.json({ url: session.url });
  } catch (err) {
    console.error('[stripe] Error creando checkout session:', err.message);
    res.status(500).json({ error: 'Error al crear la sesión de pago' });
  }
});

/**
 * POST /api/stripe/webhook
 * Recibe webhooks de Stripe. NO usa express.json (usa raw body para validar firma).
 * Actualiza profiles.plan a 'hazak' y registra en subscriptions.
 */
// Este router se monta con express.json() global, pero Stripe necesita raw body.
// Se maneja con un middleware especial en index.js que captura el raw body para esta ruta.
router.post('/webhook', express.raw({ type: 'application/json' }), async (req, res) => {
  const stripe = getStripe();
  if (!stripe) {
    return res.status(503).send('Stripe no configurado');
  }

  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
  if (!webhookSecret) {
    return res.status(503).send('Webhook secret no configurado');
  }

  let event;
  try {
    // Si el body ya fue parseado por express.json(), usarlo directamente
    const payload = Buffer.isBuffer(req.body) ? req.body : JSON.stringify(req.body);
    const sig = req.headers['stripe-signature'];
    event = stripe.webhooks.constructEvent(payload, sig, webhookSecret);
  } catch (err) {
    console.error('[stripe] Webhook signature verification failed:', err.message);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  try {
    switch (event.type) {
      case 'checkout.session.completed': {
        const session = event.data.object;
        const userId = session.client_reference_id || session.metadata?.user_id;

        if (userId && supabase) {
          // Actualizar plan del usuario a hazak
          await supabase
            .from('profiles')
            .update({ plan: 'hazak' })
            .eq('id', userId);

          // Registrar suscripción
          await supabase
            .from('subscriptions')
            .insert({
              user_id: userId,
              plan: 'hazak',
              status: 'active',
              provider: 'stripe',
              provider_sub_id: session.subscription,
              current_period_end: null, // Se actualiza en invoice.paid
            });
        }
        break;
      }

      case 'customer.subscription.updated':
      case 'customer.subscription.deleted': {
        const sub = event.data.object;
        const status = sub.status === 'active' ? 'active' :
                       sub.status === 'canceled' ? 'cancelled' :
                       sub.status === 'past_due' ? 'past_due' :
                       sub.status;

        if (supabase) {
          // Actualizar estado de la suscripción en DB
          await supabase
            .from('subscriptions')
            .update({
              status,
              current_period_end: sub.current_period_end
                ? new Date(sub.current_period_end * 1000).toISOString()
                : null,
            })
            .eq('provider_sub_id', sub.id);

          // Si se canceló, bajar plan a genesis
          if (sub.status === 'canceled') {
            const userId = sub.metadata?.user_id;
            if (userId) {
              await supabase
                .from('profiles')
                .update({ plan: 'genesis' })
                .eq('id', userId);
            }
          }
        }
        break;
      }

      case 'invoice.paid': {
        const invoice = event.data.object;
        const subId = invoice.subscription;
        if (subId && supabase) {
          await supabase
            .from('subscriptions')
            .update({
              status: 'active',
              current_period_end: invoice.lines?.data?.[0]?.period?.end
                ? new Date(invoice.lines.data[0].period.end * 1000).toISOString()
                : null,
            })
            .eq('provider_sub_id', subId);
        }
        break;
      }

      default:
        // Evento no manejado, pero responder 200 para que Stripe no reintente
        break;
    }

    res.json({ received: true });
  } catch (err) {
    console.error('[stripe] Error procesando webhook:', err.message);
    res.status(500).json({ error: 'Error interno procesando webhook' });
  }
});

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
    // Buscar subscription del usuario
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

    res.json({ url: portalSession.url });
  } catch (err) {
    console.error('[stripe] Error creando portal session:', err.message);
    res.status(500).json({ error: 'Error al abrir el portal de gestión' });
  }
});

module.exports = router;

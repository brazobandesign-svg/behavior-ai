'use strict';

/**
 * src/middleware/stripeIdempotency.js
 *
 * Middleware/helper para procesar webhooks de Stripe de forma IDEMPOTENTE y
 * ATÓMICA. La función RPC `transition_subscription` (ver §3.1) es la ÚNICA capa
 * dueña de reclamar el evento, transicionar la suscripción y marcarlo. Este
 * middleware:
 *   1. Verifica la firma del webhook (stripe.webhooks.constructEvent).
 *   2. Discrimina eventos objetivo ANTES de tocar la base de datos.
 *   3. Normaliza campos "expandibles" de Stripe (string | { id }).
 *   4. Invoca `transition_subscription` (una sola sentencia atómica) y LEE su
 *      retorno (processed / result / subscription_id) para decidir la respuesta.
 *
 * Eventos objetivo:
 *   - checkout.session.completed    -> activa la suscripción (status 'active').
 *   - customer.subscription.deleted -> cancela la suscripción (status 'canceled').
 *
 * Dependencias (CommonJS): librería oficial 'stripe' y cliente 'pg'.
 */

const Stripe = require('stripe');

const PROVIDER = 'stripe';

const TARGET_EVENTS = new Set([
  'checkout.session.completed',
  'customer.subscription.deleted',
]);

/** Resultados que devuelve transition_subscription (contrato con el SQL). */
const RESULT = {
  PROCESSED: 'processed',
  DUPLICATE: 'duplicate',
  IGNORED: 'ignored',
};

/** Normaliza un campo expandible de Stripe (string | { id }) a su id. */
function normalizeId(value) {
  if (typeof value === 'string') return value;
  if (value && typeof value.id === 'string') return value.id;
  return null;
}

/**
 * @param {object} config
 * @param {string} config.stripeSecretKey  Clave secreta de Stripe (sk_...).
 * @param {string} config.webhookSecret    Secreto de firma del endpoint (whsec_...).
 * @param {import('pg').Pool} config.pool  Pool de PostgreSQL.
 * @param {object} [config.logger]         Logger opcional (por defecto console).
 */
function createStripeIdempotencyMiddleware({ stripeSecretKey, webhookSecret, pool, logger }) {
  if (!stripeSecretKey) {
    throw new Error('[stripeIdempotency] "stripeSecretKey" es obligatorio.');
  }
  if (!webhookSecret) {
    throw new Error('[stripeIdempotency] "webhookSecret" es obligatorio (whsec_...).');
  }
  if (!pool || typeof pool.query !== 'function') {
    throw new Error('[stripeIdempotency] "pool" debe ser un pg.Pool válido.');
  }

  const log = logger || console;
  const stripe = new Stripe(stripeSecretKey);

  function getRawBody(req) {
    if (Buffer.isBuffer(req.rawBody)) return req.rawBody;
    if (typeof req.rawBody === 'string') return Buffer.from(req.rawBody, 'utf8');
    if (Buffer.isBuffer(req.body)) return req.body;
    if (typeof req.body === 'string') return Buffer.from(req.body, 'utf8');
    throw new Error('[stripeIdempotency] No hay cuerpo RAW. Monte la ruta con express.raw().');
  }

  return async function stripeIdempotencyMiddleware(req, res) {
    const signature = req.headers['stripe-signature'];
    if (!signature) {
      res.status(400).json({ error: 'Falta el header Stripe-Signature' });
      return;
    }

    let rawBody;
    try {
      rawBody = getRawBody(req);
    } catch (err) {
      log.error('[stripeIdempotency]', err.message);
      res.status(400).json({ error: 'Cuerpo RAW no disponible' });
      return;
    }

    let event;
    try {
      event = stripe.webhooks.constructEvent(rawBody, signature, webhookSecret);
    } catch (err) {
      log.error('[stripeIdempotency] Firma inválida:', err.message);
      res.status(400).json({ error: 'Firma del webhook inválida' });
      return;
    }

    // Discriminar eventos objetivo ANTES de tocar la BD.
    if (!TARGET_EVENTS.has(event.type)) {
      res.status(200).json({ received: true, ignored: true });
      return;
    }

    // Normalizar campos expandibles.
    let customerId = null;
    let subscriptionId = null;
    let userId = null;
    if (event.type === 'checkout.session.completed') {
      const session = event.data.object;
      customerId = normalizeId(session.customer);
      subscriptionId = normalizeId(session.subscription);
      userId = normalizeId(session.client_reference_id || session.metadata?.userId);
      // Pago único (mode 'payment') o sesión sin suscripción: nada que activar.
      if (!subscriptionId) {
        res.status(200).json({ received: true, ignored: true, reason: 'no_subscription' });
        return;
      }
    } else if (event.type === 'customer.subscription.deleted') {
      const subscription = event.data.object;
      customerId = normalizeId(subscription.customer);
      subscriptionId = normalizeId(subscription.id);
      userId = normalizeId(subscription.metadata?.userId);
    }

    let payloadObj = null;
    try {
      payloadObj = JSON.parse(rawBody.toString('utf8'));
    } catch (_) {
      payloadObj = null;
    }

    try {
      // Única sentencia atómica: la función reclama, transiciona (FOR UPDATE),
      // actualiza profiles.plan y marca el evento, todo en una transacción.
      const result = await pool.query(
        'SELECT * FROM transition_subscription($1, $2, $3, $4, $5, $6, $7)',
        [event.id, PROVIDER, event.type, customerId, subscriptionId, payloadObj, userId]
      );
      const outcome = result.rows[0] || {};

      // duplicate/ignored/processed -> todos ACK 200 (Stripe deja de reintentar).
      res.status(200).json({
        received: true,
        result: outcome.result,
        processed: outcome.processed,
        subscriptionId: outcome.subscription_id,
      });
    } catch (err) {
      // Fallo: la transacción de la función se revirtió; el evento queda SIN
      // registrar, por lo que Stripe lo reintentará (idempotencia preservada).
      log.error(`[stripeIdempotency] Error procesando evento ${event.id} (${event.type}):`, err);
      res.status(500).json({ error: 'Error interno procesando webhook' });
    }
  };
}

module.exports = {
  createStripeIdempotencyMiddleware,
  PROVIDER,
  TARGET_EVENTS,
  RESULT,
};

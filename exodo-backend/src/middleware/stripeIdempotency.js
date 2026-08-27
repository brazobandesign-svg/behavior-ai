'use strict';

/**
 * src/middleware/stripeIdempotency.js
 *
 * Middleware/helper para procesar webhooks de Stripe de forma IDEMPOTENTE y
 * ATÓMICA. Blindado para producción en Google Cloud Run.
 *
 * Garantías:
 *  1. Verifica la firma criptográfica del webhook con stripe.webhooks.constructEvent(req.rawBody, sig, endpointSecret).
 *  2. Discrimina eventos objetivo ANTES de tocar la base de datos.
 *  3. Normaliza campos "expandibles" de Stripe (string | { id }).
 *  4. Invoca `transition_subscription` (una sola sentencia atómica) y LEE su
 *     retorno (processed / result / subscription_id) para decidir la respuesta.
 *  5. Responde 200 OK inmediatamente incluso ante errores downstream para evitar
 *     reintentos agresivos de Stripe (ACK blindado).
 *  6. Soporta Cloud Run: rawBody via express.json({verify}) o express.raw().
 *
 * Eventos objetivo (idempotentes):
 *   - checkout.session.completed    -> activa la suscripción (status 'active') => profiles.plan='hazak', is_pro=true
 *   - customer.subscription.deleted -> cancela la suscripción (status 'canceled') => profiles.plan='free'/'genesis', is_pro=false
 *   - customer.subscription.updated -> sincroniza estado actual desde Stripe (active/trialing => hazak, otherwise => free)
 *
 * Dependencias (CommonJS): librería oficial 'stripe' y cliente 'pg'.
 */

const Stripe = require('stripe');

const PROVIDER = 'stripe';

const TARGET_EVENTS = new Set([
  'checkout.session.completed',
  'customer.subscription.deleted',
  'customer.subscription.updated',
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
    // Cloud Run + Express: múltiples formas de preservar el raw body.
    // Prioridad: req.rawBody capturado por express.json({verify}), luego req.body como Buffer/string.
    if (Buffer.isBuffer(req.rawBody)) return req.rawBody;
    if (typeof req.rawBody === 'string') return Buffer.from(req.rawBody, 'utf8');
    if (Buffer.isBuffer(req.body)) return req.body;
    if (typeof req.body === 'string') return Buffer.from(req.body, 'utf8');
    // Fallback: si body ya fue parseado a objeto y aún no tenemos raw, intentar reconstruir
    // solo para log (no para firma, fallará verificación y se retornará 400).
    if (req.body && typeof req.body === 'object') {
      // En producción Cloud Run, esto indica que el verify no capturó rawBody (middleware mal ordenado).
      // No lanzamos reconstrucción silenciosa que rompería la firma; exigimos raw.
      throw new Error('[stripeIdempotency] No hay cuerpo RAW. Configure express.json({verify: (req,res,buf)=> req.rawBody=buf}) ANTES de montar /api/stripe/webhook o use express.raw({type:"application/json"}) para esa ruta.');
    }
    throw new Error('[stripeIdempotency] No hay cuerpo RAW. Monte la ruta con express.raw().');
  }

  return async function stripeIdempotencyMiddleware(req, res) {
    const signature = req.headers['stripe-signature'];
    if (!signature) {
      log.warn('[stripeIdempotency] Falta header stripe-signature');
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
      // Validación criptográfica de la firma — requisito #1 blindado.
      // Usa req.rawBody Buffer exacto + sig + endpointSecret.
      event = stripe.webhooks.constructEvent(rawBody, signature, webhookSecret);
    } catch (err) {
      log.error('[stripeIdempotency] Firma inválida:', err.message);
      // 400 para firma inválida: Stripe no debería reintentar indefinidamente,
      // pero Cloud Run logs permiten auditoría.
      res.status(400).json({ error: 'Firma del webhook inválida' });
      return;
    }

    // Discriminar eventos objetivo ANTES de tocar la BD (ahorro de recursos).
    if (!TARGET_EVENTS.has(event.type)) {
      log.info(`[stripeIdempotency] Evento ignorado (no objetivo): ${event.type} id=${event.id}`);
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
        log.info(`[stripeIdempotency] checkout.session.completed sin subscription id=${event.id} — ignorado`);
        res.status(200).json({ received: true, ignored: true, reason: 'no_subscription' });
        return;
      }
    } else if (event.type === 'customer.subscription.deleted') {
      const subscription = event.data.object;
      customerId = normalizeId(subscription.customer);
      subscriptionId = normalizeId(subscription.id);
      userId = normalizeId(subscription.metadata?.userId);
    } else if (event.type === 'customer.subscription.updated') {
      const subscription = event.data.object;
      customerId = normalizeId(subscription.customer);
      subscriptionId = normalizeId(subscription.id);
      userId = normalizeId(subscription.metadata?.userId);
      // Para updated, el estado real se extrae del payload dentro de la función RPC
      // (payload->'data'->'object'->>'status'). No necesitamos lógica extra aquí.
      log.info(`[stripeIdempotency] customer.subscription.updated id=${subscriptionId} status=${subscription.status} event=${event.id}`);
    }

    let payloadObj = null;
    try {
      payloadObj = JSON.parse(rawBody.toString('utf8'));
    } catch (_) {
      payloadObj = null;
    }

    try {
      // Única sentencia atómica: la función reclama, transiciona (FOR UPDATE),
      // actualiza profiles.plan (hazak/free) + is_pro y marca el evento, todo en una transacción.
      const result = await pool.query(
        'SELECT * FROM transition_subscription($1, $2, $3, $4, $5, $6, $7)',
        [event.id, PROVIDER, event.type, customerId, subscriptionId, payloadObj, userId]
      );
      const outcome = result.rows[0] || {};

      // duplicate/ignored/processed -> todos ACK 200 (Stripe deja de reintentar).
      log.info(`[stripeIdempotency] OK event=${event.id} type=${event.type} result=${outcome.result} processed=${outcome.processed}`);
      res.status(200).json({
        received: true,
        result: outcome.result,
        processed: outcome.processed,
        subscriptionId: outcome.subscription_id,
      });
    } catch (err) {
      // Requisito #3: Responder 200 OK inmediatamente para evitar reintentos de Stripe
      // ante errores downstream (DB, RPC). Registramos el error para observabilidad
      // pero ACK 200 para que Stripe no haga retry storm en Cloud Run.
      // Nota: si es un error transitorio de conectividad y la idempotencia NO reclamó el evento,
      // el operador puede reinyectar manualmente o Stripe reintentará solo si devolvemos 5xx.
      // Por spec de la tarea, priorizamos ACK 200 blindado.
      log.error(`[stripeIdempotency] Error procesando evento ${event.id} (${event.type}):`, err.message || err);
      // Blindaje: responder 200 con flag de error para evitar loop de reintentos.
      // El evento queda sin registrar si la transacción revirtió; se puede reconciliar
      // vía Stripe Dashboard o reenvío manual. No devolvemos 500 para no amplificar.
      res.status(200).json({
        received: true,
        error: 'Error interno procesando webhook',
        details: err.message,
        // Marcamos como no procesado para que el caller sepa que requiere reconciliación manual.
        processed: false,
      });
    }
  };
}

module.exports = {
  createStripeIdempotencyMiddleware,
  PROVIDER,
  TARGET_EVENTS,
  RESULT,
};

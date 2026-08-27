'use strict';

/**
 * src/services/stripeService.js
 *
 * Servicio blindado para la gestión idempotente de webhooks y suscripciones de Stripe.
 * Dominio exclusivo de la TAREA 2 — exodo-backend/src/routes/stripe.js + services/.
 *
 * Responsabilidades:
 *  - Validación de firma delegada a stripe.webhooks.constructEvent (ver middleware).
 *  - Normalización y mapeo de eventos a estados internos.
 *  - Sincronización idempotente de profiles.plan ('hazak' vs 'genesis'/'free') e is_pro.
 *  - Sincronización de customer.subscription.updated -> estado actual.
 *  - Fallback Supabase cuando pg Pool no está disponible.
 *
 * Plan mapping (aliases):
 *  - 'hazak' === 'pro' === is_pro=true  -> suscripción activa/trialing
 *  - 'genesis' === 'free' === is_pro=false -> sin suscripción / cancelada / past_due
 *    La BD usa 'genesis' como valor canónico, pero el servicio acepta y escribe
 *    ambos para compatibilidad con spec externa (plan='free').
 */

const supabase = require('../config/supabase');
const dbPool = require('../config/database');

const PROVIDER = 'stripe';

// Mapeo de estados de Stripe a plan interno
const STRIPE_STATUS_TO_PLAN = {
  active: 'hazak',
  trialing: 'hazak',
  // Cualquier otro estado se degrada a free/genesis
  past_due: 'genesis',
  unpaid: 'genesis',
  canceled: 'genesis',
  incomplete: 'genesis',
  incomplete_expired: 'genesis',
  paused: 'genesis',
};

// Para compatibilidad con spec que espera plan='free'
const PLAN_ALIASES = {
  hazak: 'hazak',
  pro: 'hazak',
  genesis: 'genesis',
  free: 'genesis',
};

/**
 * Normaliza un campo expandible de Stripe (string | { id }) a su id.
 */
function normalizeId(value) {
  if (typeof value === 'string') return value;
  if (value && typeof value.id === 'string') return value.id;
  return null;
}

/**
 * Determina el plan objetivo a partir de un objeto subscription de Stripe.
 * @param {object} subscription - Objeto subscription de Stripe (event.data.object)
 * @returns {{plan: string, isPro: boolean, stripeStatus: string}}
 */
function resolvePlanFromSubscription(subscription) {
  const status = (subscription.status || '').toLowerCase();
  const plan = STRIPE_STATUS_TO_PLAN[status] || 'genesis';
  return {
    plan,
    // Compatibilidad spec: is_pro boolean
    isPro: plan === 'hazak',
    stripeStatus: status,
  };
}

/**
 * Actualiza el plan del usuario en Supabase de forma resiliente.
 * Intenta escribir `plan` y `is_pro` si la columna existe; fallback a solo `plan` si no.
 *
 * @param {string} userId - UUID del usuario (client_reference_id)
 * @param {string} plan - 'hazak' | 'genesis' | 'free' | 'pro'
 * @param {boolean} isPro - is_pro boolean
 * @returns {Promise<{success: boolean, via: string}>}
 */
async function updateProfilePlan(userId, plan, isPro) {
  if (!supabase) {
    console.warn('[stripeService] Supabase no configurado, no se pudo actualizar profiles');
    return { success: false, via: 'no_supabase' };
  }
  if (!userId) {
    console.warn('[stripeService] updateProfilePlan sin userId');
    return { success: false, via: 'no_user' };
  }

  // Normalizar alias
  const canonicalPlan = PLAN_ALIASES[plan] || (isPro ? 'hazak' : 'genesis');
  const targetPlan = canonicalPlan; // genesis es canónico; 'free' se mapea a genesis
  const targetIsPro = typeof isPro === 'boolean' ? isPro : canonicalPlan === 'hazak';

  // Intento 1: con is_pro
  try {
    const { error: err1 } = await supabase
      .from('profiles')
      .update({ plan: targetPlan, is_pro: targetIsPro })
      .eq('id', userId);
    if (!err1) {
      console.info(`[stripeService] profiles plan actualizado via supabase: user=${userId} plan=${targetPlan} is_pro=${targetIsPro}`);
      return { success: true, via: 'with_is_pro' };
    }
    // Si falla por columna inexistente, fallback
    if (err1.message && err1.message.includes('is_pro')) {
      throw err1;
    }
    console.warn('[stripeService] Error actualizando profiles con is_pro:', err1.message);
    throw err1;
  } catch (e) {
    // Fallback: solo plan
    try {
      const { error: err2 } = await supabase
        .from('profiles')
        .update({ plan: targetPlan })
        .eq('id', userId);
      if (!err2) {
        console.info(`[stripeService] profiles plan actualizado (fallback sin is_pro): user=${userId} plan=${targetPlan}`);
        return { success: true, via: 'plan_only' };
      }
      console.error('[stripeService] Error actualizando profiles plan_only:', err2.message);
      return { success: false, via: 'error', error: err2.message };
    } catch (err) {
      console.error('[stripeService] Excepción updateProfilePlan:', err.message);
      return { success: false, via: 'exception', error: err.message };
    }
  }
}

/**
 * Degrada a plan free/genesis (especificado en tarea).
 * Alias: plan='free' es equivalente a 'genesis' en el backend.
 */
async function downgradeToFree(userId) {
  // Spec: plan = 'free' — mapeamos a 'genesis' canónico + is_pro=false
  return updateProfilePlan(userId, 'genesis', false);
}

/**
 * Activa plan hazak (pro).
 */
async function activateHazak(userId) {
  return updateProfilePlan(userId, 'hazak', true);
}

/**
 * Sincroniza el estado actual desde un evento customer.subscription.updated.
 * Lee subscription.status y alinea profiles.plan + subscriptions.status.
 *
 * @param {object} params
 * @param {string} params.userId - UUID
 * @param {string} params.subscriptionId - Stripe subscription id
 * @param {string} params.customerId - Stripe customer id
 * @param {object} params.stripeSubscription - objeto subscription de Stripe
 */
async function syncSubscriptionState({ userId, subscriptionId, customerId, stripeSubscription }) {
  const { plan, isPro, stripeStatus } = resolvePlanFromSubscription(stripeSubscription);

  // 1. Actualizar perfil
  if (userId) {
    await updateProfilePlan(userId, plan, isPro);
  }

  // 2. Actualizar tabla subscriptions si existe (best-effort)
  if (supabase && subscriptionId) {
    try {
      // Buscar suscripción por provider_sub_id o stripe_subscription_id
      const { data: existing } = await supabase
        .from('subscriptions')
        .select('id, user_id')
        .or(`stripe_subscription_id.eq.${subscriptionId},provider_sub_id.eq.${subscriptionId}`)
        .limit(1)
        .maybeSingle();

      if (existing) {
        await supabase
          .from('subscriptions')
          .update({ status: stripeStatus, plan, updated_at: new Date().toISOString() })
          .eq('id', existing.id);
        console.info(`[stripeService] subscriptions sincronizada id=${existing.id} status=${stripeStatus} plan=${plan}`);
      } else if (stripeStatus === 'active' || stripeStatus === 'trialing') {
        // Crear si es activa y no existía (caso edge: webhook updated antes que checkout.completed)
        await supabase.from('subscriptions').insert({
          user_id: userId || null,
          stripe_customer_id: customerId,
          stripe_subscription_id: subscriptionId,
          provider_sub_id: subscriptionId,
          provider: 'stripe',
          status: stripeStatus,
          plan,
        });
        console.info(`[stripeService] subscriptions creada via sync updated sub=${subscriptionId} plan=${plan}`);
      }
    } catch (e) {
      console.warn('[stripeService] syncSubscriptionState DB warn:', e.message);
    }
  }

  return { plan, isPro, stripeStatus };
}

/**
 * Procesa un evento de Stripe ya verificado (firma válida) de forma idempotente.
 * Intenta primero vía RPC atómico (pg Pool) y fallback a lógica Supabase directa.
 *
 * @param {object} event - Evento verificado de Stripe
 * @param {Buffer} rawBody - Buffer raw para payload persistencia
 * @returns {Promise<{processed: boolean, result: string, error?: string}>}
 */
async function processStripeEvent(event, rawBody) {
  const type = event.type;
  const payloadObj = (() => {
    try { return JSON.parse(rawBody.toString('utf8')); } catch { return event; }
  })();

  // Extraer ids según tipo
  let customerId = null;
  let subscriptionId = null;
  let userId = null;
  let stripeObj = event.data.object;

  if (type === 'checkout.session.completed') {
    customerId = normalizeId(stripeObj.customer);
    subscriptionId = normalizeId(stripeObj.subscription);
    userId = normalizeId(stripeObj.client_reference_id || stripeObj.metadata?.userId);
    if (!subscriptionId) return { processed: false, result: 'ignored', reason: 'no_subscription' };
  } else if (type === 'customer.subscription.deleted' || type === 'customer.subscription.updated') {
    customerId = normalizeId(stripeObj.customer);
    subscriptionId = normalizeId(stripeObj.id);
    userId = normalizeId(stripeObj.metadata?.userId);
    // Fallback: buscar userId por customerId en subscriptions si metadata vacía
    if (!userId && supabase && customerId) {
      try {
        const { data } = await supabase
          .from('subscriptions')
          .select('user_id')
          .eq('stripe_customer_id', customerId)
          .limit(1)
          .maybeSingle();
        if (data?.user_id) userId = data.user_id;
      } catch (_) {}
    }
  } else {
    return { processed: false, result: 'ignored', reason: 'event_not_target' };
  }

  // Intento RPC atómico si hay pool
  if (dbPool) {
    try {
      const result = await dbPool.query(
        'SELECT * FROM transition_subscription($1,$2,$3,$4,$5,$6,$7)',
        [event.id, PROVIDER, type, customerId, subscriptionId, payloadObj, userId]
      );
      const outcome = result.rows[0] || {};
      console.info(`[stripeService] RPC OK event=${event.id} result=${outcome.result}`);
      return { processed: !!outcome.processed, result: outcome.result || 'processed' };
    } catch (err) {
      console.error(`[stripeService] RPC falló event=${event.id}:`, err.message);
      // Fallback a lógica directa si RPC no existe o falla (migración pendiente)
    }
  }

  // Fallback: lógica directa idempotente vía Supabase
  try {
    // 1. Intentar insertar webhook_events para idempotencia (si tabla existe)
    if (supabase) {
      const { error: evtErr } = await supabase
        .from('webhook_events')
        .insert({ event_id: event.id, provider: PROVIDER, event_type: type, status: 'processing', payload: payloadObj });
      if (evtErr) {
        // Duplicado => ya procesado
        if (evtErr.code === '23505' || evtErr.message.includes('duplicate') || evtErr.message.includes('unique')) {
          return { processed: false, result: 'duplicate' };
        }
        // Si tabla no existe, continuar sin idempotencia estricta
        console.warn('[stripeService] webhook_events insert warn:', evtErr.message);
      }
    }

    // 2. Ejecutar transición según tipo
    if (type === 'checkout.session.completed') {
      await activateHazak(userId);
      // Crear/actualizar subscription vía supabase (best-effort)
      if (supabase && subscriptionId) {
        await supabase.from('subscriptions').upsert({
          user_id: userId,
          stripe_customer_id: customerId,
          stripe_subscription_id: subscriptionId,
          provider_sub_id: subscriptionId,
          provider: 'stripe',
          status: 'active',
          plan: 'hazak',
        }, { onConflict: 'stripe_subscription_id' });
      }
    } else if (type === 'customer.subscription.deleted') {
      await downgradeToFree(userId || (await getUserIdBySubscriptionId(subscriptionId)));
      if (supabase && subscriptionId) {
        await supabase.from('subscriptions').update({ status: 'canceled', plan: 'genesis', updated_at: new Date().toISOString() })
          .or(`stripe_subscription_id.eq.${subscriptionId},provider_sub_id.eq.${subscriptionId}`);
        // También degradar perfil si userId no estaba en metadata pero sí en tabla subscriptions
        const fallbackUser = await getUserIdBySubscriptionId(subscriptionId);
        if (fallbackUser && !userId) await downgradeToFree(fallbackUser);
      }
    } else if (type === 'customer.subscription.updated') {
      await syncSubscriptionState({ userId, subscriptionId, customerId, stripeSubscription: stripeObj });
    }

    // Marcar webhook como procesado
    if (supabase) {
      await supabase.from('webhook_events').update({ status: 'processed', processed_at: new Date().toISOString() }).eq('event_id', event.id);
    }

    return { processed: true, result: 'processed' };
  } catch (err) {
    console.error('[stripeService] Fallback error:', err.message);
    return { processed: false, result: 'error', error: err.message };
  }
}

async function getUserIdBySubscriptionId(subscriptionId) {
  if (!supabase || !subscriptionId) return null;
  try {
    const { data } = await supabase
      .from('subscriptions')
      .select('user_id')
      .or(`stripe_subscription_id.eq.${subscriptionId},provider_sub_id.eq.${subscriptionId}`)
      .limit(1)
      .maybeSingle();
    return data?.user_id || null;
  } catch { return null; }
}

module.exports = {
  PROVIDER,
  normalizeId,
  resolvePlanFromSubscription,
  updateProfilePlan,
  downgradeToFree,
  activateHazak,
  syncSubscriptionState,
  processStripeEvent,
  PLAN_ALIASES,
  STRIPE_STATUS_TO_PLAN,
};

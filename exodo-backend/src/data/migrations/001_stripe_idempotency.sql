-- =====================================================================
-- Módulo 2 — Migración SQL (UP)
-- Stripe: idempotencia de webhooks + transición atómica de suscripciones
-- PostgreSQL >= 9.5 · comentarios en español · identificadores en inglés
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 0. Tabla de suscripciones (SE ASUME YA EXISTENTE — no se crea aquí).
--    Esquema mínimo esperado:
--
--      subscriptions (
--          id                      BIGSERIAL PRIMARY KEY,
--          stripe_customer_id      TEXT,
--          stripe_subscription_id  TEXT,
--          status                  TEXT  -- trialing/active/past_due/canceled/incomplete
--      )
--
--    ÍNDICE ÚNICO OBLIGATORIO (necesario para el upsert atómico del
--    checkout y para evitar duplicados bajo concurrencia — ver §3.2):
-- ---------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_subscriptions_stripe_subscription_id
    ON subscriptions (stripe_subscription_id);

-- ---------------------------------------------------------------------
-- 1. Tabla de eventos de webhook (registro de idempotencia).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS webhook_events (
    id            BIGSERIAL   PRIMARY KEY,
    event_id      TEXT        NOT NULL,
    provider      TEXT        NOT NULL DEFAULT 'stripe',
    event_type    TEXT        NOT NULL,
    status        TEXT        NOT NULL DEFAULT 'processing'
                  CHECK (status IN ('processing','processed','duplicate','ignored','failed')),
    payload       JSONB,
    error_message TEXT,
    processed_at  TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_webhook_events_event_id UNIQUE (event_id)
);

COMMENT ON TABLE webhook_events IS
    'Registro de idempotencia de eventos de webhook (Stripe). event_id es único.';
COMMENT ON COLUMN webhook_events.status IS
    'Ciclo de vida: processing -> processed | duplicate | ignored | failed.';
COMMENT ON COLUMN webhook_events.processed_at IS
    'Timestamp de procesamiento exitoso (misma transacción que la transición de suscripción).';

-- ---------------------------------------------------------------------
-- 2. Función RPC de transición atómica de suscripción.
--
--    CONTRATO (lo consume el middleware Node.js):
--      Params:  (p_event_id, p_provider, p_event_type,
--                p_stripe_customer_id, p_stripe_subscription_id, p_payload)
--      Retorno: TABLE (processed BOOLEAN, result TEXT, subscription_id BIGINT)
--        result = 'processed' -> transición aplicada (o idempotente)
--        result = 'duplicate' -> evento ya procesado: ACK y descartar
--        result = 'ignored'   -> evento reconocido sin acción de suscripción
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION transition_subscription(
    p_event_id               TEXT,
    p_provider               TEXT,
    p_event_type             TEXT,
    p_stripe_customer_id     TEXT,
    p_stripe_subscription_id TEXT,
    p_payload                JSONB DEFAULT NULL
)
RETURNS TABLE (
    processed       BOOLEAN,
    result          TEXT,
    subscription_id BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_webhook_id     BIGINT;
    v_sub_id         BIGINT;
    v_new_status     TEXT;
    v_current_status TEXT;
BEGIN
    -- (1) IDEMPOTENCIA: reclamar el evento. Si event_id ya existe -> duplicate.
    INSERT INTO webhook_events (event_id, provider, event_type, status, payload)
    VALUES (p_event_id, p_provider, p_event_type, 'processing', p_payload)
    ON CONFLICT (event_id) DO NOTHING
    RETURNING id INTO v_webhook_id;

    IF v_webhook_id IS NULL THEN
        RETURN QUERY SELECT FALSE::BOOLEAN, 'duplicate'::TEXT, NULL::BIGINT;
        RETURN;
    END IF;

    -- (2) Mapeo de tipo de evento -> estado objetivo.
    IF p_event_type = 'checkout.session.completed' THEN
        v_new_status := 'active';
    ELSIF p_event_type = 'customer.subscription.deleted' THEN
        v_new_status := 'canceled';
    ELSE
        UPDATE webhook_events SET status = 'ignored', processed_at = now()
         WHERE id = v_webhook_id;
        RETURN QUERY SELECT TRUE::BOOLEAN, 'ignored'::TEXT, NULL::BIGINT;
        RETURN;
    END IF;

    -- (3) ATOMICIDAD: bloquear la fila de la suscripción (FOR UPDATE).
    SELECT id, status
      INTO v_sub_id, v_current_status
      FROM subscriptions
     WHERE stripe_subscription_id = p_stripe_subscription_id
       FOR UPDATE;

    IF v_sub_id IS NULL THEN
        IF p_event_type = 'checkout.session.completed' THEN
            -- Crear (upsert protegido por índice único; sin duplicados bajo concurrencia).
            INSERT INTO subscriptions (stripe_customer_id, stripe_subscription_id, status)
            VALUES (p_stripe_customer_id, p_stripe_subscription_id, v_new_status)
            ON CONFLICT (stripe_subscription_id) DO UPDATE SET status = EXCLUDED.status
            RETURNING id INTO v_sub_id;
        ELSE
            -- 'deleted' sin fila local: nada que cancelar; evento queda procesado.
            UPDATE webhook_events SET status = 'processed', processed_at = now()
             WHERE id = v_webhook_id;
            RETURN QUERY SELECT TRUE::BOOLEAN, 'processed'::TEXT, NULL::BIGINT;
            RETURN;
        END IF;
    ELSE
        -- (4) Validación de máquina de estados (transición idempotente / ilegal).
        IF v_current_status = v_new_status THEN
            NULL; -- ya en el estado objetivo: idempotente, no sobrescribir.
        ELSIF v_current_status = 'canceled' AND v_new_status = 'active' THEN
            UPDATE subscriptions SET status = v_new_status WHERE id = v_sub_id; -- re-suscripción
        ELSIF v_new_status = 'canceled'
              AND v_current_status IN ('canceled','incomplete','incomplete_expired') THEN
            NULL; -- cancelación idempotente o de estados terminales.
        ELSE
            UPDATE subscriptions SET status = v_new_status WHERE id = v_sub_id;
        END IF;
    END IF;

    -- (5) Cierre: marcar procesado EN LA MISMA transacción.
    UPDATE webhook_events SET status = 'processed', processed_at = now()
     WHERE id = v_webhook_id;

    RETURN QUERY SELECT TRUE::BOOLEAN, 'processed'::TEXT, v_sub_id;
END;
$$;

COMMENT ON FUNCTION transition_subscription(TEXT, TEXT, TEXT, TEXT, TEXT, JSONB) IS
    'Transiciona atómicamente el estado de una suscripción según el evento Stripe, con idempotencia por event_id.';

COMMIT;

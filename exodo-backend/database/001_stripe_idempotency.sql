-- =====================================================================
-- 001_stripe_idempotency.sql
-- Stripe: idempotencia de webhooks + transición atómica de suscripciones
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 0. Tabla de suscripciones e índice único obligatorio.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS subscriptions (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    plan                   TEXT DEFAULT 'genesis',
    status                 TEXT DEFAULT 'active',
    provider               TEXT DEFAULT 'stripe',
    provider_sub_id        TEXT,
    stripe_customer_id     TEXT,
    stripe_subscription_id TEXT,
    current_period_end     TIMESTAMPTZ,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Asegurar columnas si la tabla ya existía
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='subscriptions' AND column_name='stripe_subscription_id') THEN
        ALTER TABLE subscriptions ADD COLUMN stripe_subscription_id TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='subscriptions' AND column_name='stripe_customer_id') THEN
        ALTER TABLE subscriptions ADD COLUMN stripe_customer_id TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='subscriptions' AND column_name='provider_sub_id') THEN
        ALTER TABLE subscriptions ADD COLUMN provider_sub_id TEXT;
    END IF;
END $$;

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

-- ---------------------------------------------------------------------
-- 2. Función RPC de transición atómica de suscripción.
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
        OR provider_sub_id = p_stripe_subscription_id
       FOR UPDATE;

    IF v_sub_id IS NULL THEN
        IF p_event_type = 'checkout.session.completed' THEN
            INSERT INTO subscriptions (stripe_customer_id, stripe_subscription_id, provider_sub_id, status)
            VALUES (p_stripe_customer_id, p_stripe_subscription_id, p_stripe_subscription_id, v_new_status)
            ON CONFLICT (stripe_subscription_id) DO UPDATE SET status = EXCLUDED.status;
            RETURN QUERY SELECT TRUE::BOOLEAN, 'processed'::TEXT, NULL::BIGINT;
            RETURN;
        ELSE
            UPDATE webhook_events SET status = 'processed', processed_at = now()
             WHERE id = v_webhook_id;
            RETURN QUERY SELECT TRUE::BOOLEAN, 'processed'::TEXT, NULL::BIGINT;
            RETURN;
        END IF;
    ELSE
        IF v_current_status = v_new_status THEN
            NULL;
        ELSIF v_current_status = 'canceled' AND v_new_status = 'active' THEN
            UPDATE subscriptions SET status = v_new_status WHERE id = v_sub_id;
        ELSIF v_new_status = 'canceled'
              AND v_current_status IN ('canceled','incomplete','incomplete_expired') THEN
            NULL;
        ELSE
            UPDATE subscriptions SET status = v_new_status WHERE id = v_sub_id;
        END IF;
    END IF;

    -- (4) Cierre: marcar procesado EN LA MISMA transacción.
    UPDATE webhook_events SET status = 'processed', processed_at = now()
     WHERE id = v_webhook_id;

    RETURN QUERY SELECT TRUE::BOOLEAN, 'processed'::TEXT, v_sub_id;
END;
$$;

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON TABLE webhook_events TO authenticated, service_role;
GRANT ALL ON TABLE subscriptions TO authenticated, service_role;

COMMIT;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

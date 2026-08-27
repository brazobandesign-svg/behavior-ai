-- =====================================================================
-- ÉXODO BY BEHAVIOR — SCRIPT CONSOLIDADO DE PRODUCCIÓN (SUPABASE SQL)
-- Fecha: 2026-08-27 (Blindado Cloud Run + 3 eventos Stripe)
-- Instrucciones: Abre el SQL Editor de tu Dashboard de Supabase, pega
-- este script completo y haz clic en "Run".
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 0. EXTENSIÓN PROFILES PARA SPEC is_pro + alias free/genesis
-- ---------------------------------------------------------------------
-- Compatibilidad TAREA 2: spec exige is_pro boolean y plan='free' vs 'hazak'
-- La app usa 'genesis' como canónico para free; aquí soportamos ambos.
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_pro BOOLEAN DEFAULT FALSE;
-- Comentario: is_pro = true  <=> plan in ('hazak','pro'); is_pro=false <=> plan in ('genesis','free')

-- ---------------------------------------------------------------------
-- 1. TABLA WEBHOOK_EVENTS (CREACIÓN / MIGRACIÓN IDEMPOTENTE)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS webhook_events (
    id           BIGSERIAL PRIMARY KEY,
    event_id     TEXT,
    provider     TEXT NOT NULL DEFAULT 'stripe',
    event_type   TEXT,
    status       TEXT NOT NULL DEFAULT 'processing',
    payload      JSONB,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at TIMESTAMPTZ
);

ALTER TABLE webhook_events ADD COLUMN IF NOT EXISTS event_id TEXT;
ALTER TABLE webhook_events ADD COLUMN IF NOT EXISTS provider TEXT NOT NULL DEFAULT 'stripe';
ALTER TABLE webhook_events ADD COLUMN IF NOT EXISTS event_type TEXT;
ALTER TABLE webhook_events ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'processing';
ALTER TABLE webhook_events ADD COLUMN IF NOT EXISTS payload JSONB;
ALTER TABLE webhook_events ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE webhook_events ADD COLUMN IF NOT EXISTS processed_at TIMESTAMPTZ;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_webhook_events_event_id') THEN
        ALTER TABLE webhook_events ADD CONSTRAINT uq_webhook_events_event_id UNIQUE (event_id);
    END IF;
EXCEPTION WHEN OTHERS THEN
    NULL;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_webhook_events_status
    ON webhook_events (status, created_at);

-- RLS en webhook_events (solo accesible por backend con service_role)
ALTER TABLE webhook_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS webhook_events_service_role ON webhook_events;
CREATE POLICY webhook_events_service_role ON webhook_events
    FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- ---------------------------------------------------------------------
-- 2. TABLA SUBSCRIPTIONS (CREACIÓN / MIGRACIÓN IDEMPOTENTE)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS subscriptions (
    id BIGSERIAL PRIMARY KEY
);

ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS stripe_customer_id TEXT;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS stripe_subscription_id TEXT;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS provider TEXT NOT NULL DEFAULT 'stripe';
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS provider_sub_id TEXT;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'incomplete';
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS plan TEXT NOT NULL DEFAULT 'genesis';
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'subscriptions_stripe_subscription_id_key') THEN
        ALTER TABLE subscriptions ADD CONSTRAINT subscriptions_stripe_subscription_id_key UNIQUE (stripe_subscription_id);
    END IF;
EXCEPTION WHEN OTHERS THEN
    NULL;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_subscriptions_user
    ON subscriptions (user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_stripe_sub
    ON subscriptions (stripe_subscription_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_stripe_cust
    ON subscriptions (stripe_customer_id);

-- RLS en subscriptions: usuarios solo ven su propia suscripción (lectura)
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS subscriptions_select_own ON subscriptions;
CREATE POLICY subscriptions_select_own ON subscriptions
    FOR SELECT TO authenticated
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS subscriptions_service_role ON subscriptions;
CREATE POLICY subscriptions_service_role ON subscriptions
    FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- ---------------------------------------------------------------------
-- 3. FUNCIÓN RPC TRANSITION_SUBSCRIPTION (REVOCADA DE POSTGREST PÚBLICO)
--    Blindada para 3 eventos: checkout.session.completed, customer.subscription.deleted,
--    customer.subscription.updated. Maneja plan='hazak'/'genesis'/'free' + is_pro.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION transition_subscription(
    p_event_id               TEXT,
    p_provider               TEXT,
    p_event_type             TEXT,
    p_stripe_customer_id     TEXT,
    p_stripe_subscription_id TEXT,
    p_payload                JSONB DEFAULT NULL,
    p_user_id                TEXT DEFAULT NULL
)
RETURNS TABLE (
    processed       BOOLEAN,
    result          TEXT,
    subscription_id BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_webhook_id     BIGINT;
    v_sub_id         BIGINT;
    v_new_status     TEXT;
    v_current_status TEXT;
    v_target_user_id UUID;
    v_payload_status TEXT;
BEGIN
    -- Hardening: sin event_id la idempotencia es imposible (NULL != NULL en PG).
    IF p_event_id IS NULL OR p_event_id = '' THEN
        RAISE EXCEPTION 'transition_subscription: p_event_id es obligatorio';
    END IF;

    -- Parsear UUID de usuario si se proveyó
    IF p_user_id IS NOT NULL AND p_user_id != '' THEN
        BEGIN
            v_target_user_id := p_user_id::UUID;
        EXCEPTION WHEN OTHERS THEN
            v_target_user_id := NULL;
        END;
    END IF;

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
    ELSIF p_event_type = 'customer.subscription.updated' THEN
        -- Sincronizar estado actual: extraer status del payload
        BEGIN
            v_payload_status := COALESCE(p_payload->'data'->'object'->>'status', 'active');
        EXCEPTION WHEN OTHERS THEN
            v_payload_status := 'active';
        END;
        IF v_payload_status IN ('active','trialing') THEN
            v_new_status := 'active';
        ELSIF v_payload_status = 'canceled' THEN
            v_new_status := 'canceled';
        ELSE
            -- past_due, unpaid, incomplete, incomplete_expired, paused -> almacenar tal cual
            v_new_status := v_payload_status;
        END IF;
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
            INSERT INTO subscriptions (user_id, stripe_customer_id, stripe_subscription_id, provider_sub_id, status, plan, provider)
            VALUES (v_target_user_id, p_stripe_customer_id, p_stripe_subscription_id, p_stripe_subscription_id, v_new_status, 'hazak', 'stripe')
            ON CONFLICT (stripe_subscription_id) DO UPDATE 
               SET status = EXCLUDED.status,
                   user_id = COALESCE(EXCLUDED.user_id, subscriptions.user_id),
                   plan = 'hazak',
                   updated_at = now()
            RETURNING id INTO v_sub_id;

            -- Activar el plan Hazak en el perfil del usuario (con is_pro)
            IF v_target_user_id IS NOT NULL THEN
                BEGIN
                    UPDATE profiles SET plan = 'hazak', is_pro = true WHERE id = v_target_user_id;
                EXCEPTION WHEN undefined_column THEN
                    UPDATE profiles SET plan = 'hazak' WHERE id = v_target_user_id;
                END;
            END IF;

            UPDATE webhook_events SET status = 'processed', processed_at = now()
             WHERE id = v_webhook_id;
            RETURN QUERY SELECT TRUE::BOOLEAN, 'processed'::TEXT, v_sub_id;
            RETURN;
        ELSIF p_event_type = 'customer.subscription.updated' AND v_new_status = 'active' THEN
            -- Updated activo sin fila previa: crear (edge: webhook updated antes que checkout)
            INSERT INTO subscriptions (user_id, stripe_customer_id, stripe_subscription_id, provider_sub_id, status, plan, provider)
            VALUES (v_target_user_id, p_stripe_customer_id, p_stripe_subscription_id, p_stripe_subscription_id, v_new_status, 'hazak', 'stripe')
            ON CONFLICT (stripe_subscription_id) DO UPDATE 
               SET status = EXCLUDED.status,
                   plan = 'hazak',
                   updated_at = now()
            RETURNING id INTO v_sub_id;
            IF v_target_user_id IS NOT NULL THEN
                BEGIN
                    UPDATE profiles SET plan = 'hazak', is_pro = true WHERE id = v_target_user_id;
                EXCEPTION WHEN undefined_column THEN
                    UPDATE profiles SET plan = 'hazak' WHERE id = v_target_user_id;
                END;
            END IF;
            UPDATE webhook_events SET status = 'processed', processed_at = now()
             WHERE id = v_webhook_id;
            RETURN QUERY SELECT TRUE::BOOLEAN, 'processed'::TEXT, v_sub_id;
            RETURN;
        ELSE
            UPDATE webhook_events SET status = 'processed', processed_at = now()
             WHERE id = v_webhook_id;
            RETURN QUERY SELECT TRUE::BOOLEAN, 'processed'::TEXT, NULL::BIGINT;
            RETURN;
        END IF;
    ELSE
        IF v_current_status = v_new_status THEN
            -- Idempotente pero para updated sincronizar plan por si diverge
            IF p_event_type = 'customer.subscription.updated' THEN
                IF v_new_status = 'active' THEN
                    UPDATE subscriptions SET status = 'active', plan = 'hazak', updated_at = now() WHERE id = v_sub_id;
                    IF v_target_user_id IS NOT NULL THEN
                        BEGIN UPDATE profiles SET plan = 'hazak', is_pro = true WHERE id = v_target_user_id; EXCEPTION WHEN undefined_column THEN UPDATE profiles SET plan = 'hazak' WHERE id = v_target_user_id; END;
                    ELSE
                        BEGIN UPDATE profiles SET plan = 'hazak', is_pro = true WHERE id IN (SELECT user_id FROM subscriptions WHERE id = v_sub_id AND user_id IS NOT NULL); EXCEPTION WHEN undefined_column THEN UPDATE profiles SET plan = 'hazak' WHERE id IN (SELECT user_id FROM subscriptions WHERE id = v_sub_id AND user_id IS NOT NULL); END;
                    END IF;
                ELSE
                    UPDATE subscriptions SET status = v_new_status, plan = 'genesis', updated_at = now() WHERE id = v_sub_id;
                    BEGIN UPDATE profiles SET plan = 'genesis', is_pro = false WHERE id IN (SELECT user_id FROM subscriptions WHERE id = v_sub_id AND user_id IS NOT NULL); EXCEPTION WHEN undefined_column THEN UPDATE profiles SET plan = 'genesis' WHERE id IN (SELECT user_id FROM subscriptions WHERE id = v_sub_id AND user_id IS NOT NULL); END;
                    IF v_target_user_id IS NOT NULL THEN
                        BEGIN UPDATE profiles SET plan = 'genesis', is_pro = false WHERE id = v_target_user_id; EXCEPTION WHEN undefined_column THEN UPDATE profiles SET plan = 'genesis' WHERE id = v_target_user_id; END;
                    END IF;
                END IF;
            END IF;
            NULL;
        ELSIF v_new_status = 'active' AND v_current_status <> 'active' THEN
            -- Reactivación desde cualquier estado no-activo: alinear siempre el plan.
            UPDATE subscriptions SET status = 'active', plan = 'hazak', updated_at = now() WHERE id = v_sub_id;
            IF v_target_user_id IS NOT NULL THEN
                BEGIN UPDATE profiles SET plan = 'hazak', is_pro = true WHERE id = v_target_user_id; EXCEPTION WHEN undefined_column THEN UPDATE profiles SET plan = 'hazak' WHERE id = v_target_user_id; END;
            ELSE
                BEGIN UPDATE profiles SET plan = 'hazak', is_pro = true WHERE id IN (SELECT user_id FROM subscriptions WHERE id = v_sub_id AND user_id IS NOT NULL); EXCEPTION WHEN undefined_column THEN UPDATE profiles SET plan = 'hazak' WHERE id IN (SELECT user_id FROM subscriptions WHERE id = v_sub_id AND user_id IS NOT NULL); END;
            END IF;
        ELSIF v_new_status = 'canceled'
              AND v_current_status IN ('canceled','incomplete','incomplete_expired') THEN
            NULL;
        ELSE
            -- Transición genérica
            IF v_new_status = 'active' THEN
                UPDATE subscriptions SET status = v_new_status, plan = 'hazak', updated_at = now() WHERE id = v_sub_id;
                IF v_target_user_id IS NOT NULL THEN
                    BEGIN UPDATE profiles SET plan = 'hazak', is_pro = true WHERE id = v_target_user_id; EXCEPTION WHEN undefined_column THEN UPDATE profiles SET plan = 'hazak' WHERE id = v_target_user_id; END;
                END IF;
                BEGIN UPDATE profiles SET plan = 'hazak', is_pro = true WHERE id IN (SELECT user_id FROM subscriptions WHERE id = v_sub_id AND user_id IS NOT NULL); EXCEPTION WHEN undefined_column THEN UPDATE profiles SET plan = 'hazak' WHERE id IN (SELECT user_id FROM subscriptions WHERE id = v_sub_id AND user_id IS NOT NULL); END;
            ELSE
                UPDATE subscriptions SET status = v_new_status, plan = 'genesis', updated_at = now() WHERE id = v_sub_id;
                -- Degradar a plan='free'/'genesis' + is_pro=false (spec)
                IF v_new_status IN ('canceled','past_due','unpaid','incomplete','incomplete_expired','paused') THEN
                    BEGIN UPDATE profiles SET plan = 'genesis', is_pro = false WHERE id IN (SELECT user_id FROM subscriptions WHERE id = v_sub_id AND user_id IS NOT NULL); EXCEPTION WHEN undefined_column THEN UPDATE profiles SET plan = 'genesis' WHERE id IN (SELECT user_id FROM subscriptions WHERE id = v_sub_id AND user_id IS NOT NULL); END;
                    -- Alias spec: plan='free' es equivalente a 'genesis'; dejamos 'genesis' como canónico
                    IF v_target_user_id IS NOT NULL THEN
                        BEGIN UPDATE profiles SET plan = 'genesis', is_pro = false WHERE id = v_target_user_id; EXCEPTION WHEN undefined_column THEN UPDATE profiles SET plan = 'genesis' WHERE id = v_target_user_id; END;
                    END IF;
                END IF;
            END IF;
        END IF;
    END IF;

    -- (4) Cierre: marcar procesado EN LA MISMA transacción.
    UPDATE webhook_events SET status = 'processed', processed_at = now()
     WHERE id = v_webhook_id;

    RETURN QUERY SELECT TRUE::BOOLEAN, 'processed'::TEXT, v_sub_id;
END;
$$;

-- REVOCAR EJECUCIÓN PÚBLICA DE transition_subscription (Cierra vector PostgREST RPC)
REVOKE EXECUTE ON FUNCTION transition_subscription(TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION transition_subscription(TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, TEXT) TO service_role, postgres;

-- ---------------------------------------------------------------------
-- 4. TRIGGER DE SEGURIDAD EN PROFILES (INSERT + UPDATE BLINDADOS)
--    Soporta alias: 'genesis'/'free' = free tier, 'hazak'/'pro' = pro tier
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION protect_profile_plan()
RETURNS trigger AS $$
BEGIN
    -- En INSERT: impedir que un registro nuevo se cree directamente como 'hazak'/'pro'
    IF TG_OP = 'INSERT' THEN
        IF NEW.plan IS NOT NULL AND NEW.plan NOT IN ('genesis','free') AND current_user NOT IN ('service_role', 'postgres', 'supabase_admin') THEN
            RAISE EXCEPTION 'No puedes auto-asignarte un plan de pago al registrarte';
        END IF;
    END IF;

    -- En UPDATE: impedir que el cliente modifique su plan
    IF TG_OP = 'UPDATE' THEN
        IF NEW.plan IS DISTINCT FROM OLD.plan AND current_user NOT IN ('service_role', 'postgres', 'supabase_admin') THEN
            RAISE EXCEPTION 'No tienes permiso para modificar directamente el plan de suscripción';
        END IF;
    END IF;

    RETURN NEW;
END;
-- FIX NO-OP: como INVOKER, current_user es quien ejecuta el DML
-- (authenticated/anon -> bloqueado | postgres/service_role -> permitido).
-- Con SECURITY DEFINER current_user siempre era el owner y el IF nunca disparaba.
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_protect_profile_plan ON profiles;
CREATE TRIGGER trg_protect_profile_plan
    BEFORE INSERT OR UPDATE ON profiles
    FOR EACH ROW
    EXECUTE FUNCTION protect_profile_plan();

-- ---------------------------------------------------------------------
-- 5. RAG PGVECTOR: MATCH_CHUNKS CON SECURITY DEFINER Y SEARCH_PATH
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION match_chunks(
  query_embedding vector(1536),
  match_count     int  default 10,
  filter          jsonb default '{}'::jsonb
)
RETURNS TABLE (
  id            uuid,
  document_id   uuid,
  content       text,
  similarity    float,
  metadata      jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    c.id,
    c.document_id,
    c.content,
    1 - (c.embedding <=> query_embedding) AS similarity,
    jsonb_build_object(
      'short_name', d.short_name,
      'title', d.title,
      'doc_type', d.doc_type,
      'version', d.version,
      'page', c.page_number,
      'section', c.section,
      'subsection', c.subsection,
      'nivel', c.nivel,
      'ciclo', c.ciclo,
      'grado', c.grado,
      'area_curricular', c.area_curricular,
      'competencias_fundamentales', c.competencia_fundamental,
      'competencia_especifica', c.competencia_especifica,
      'indicadores_logro', c.indicadores_logro,
      'ejes_tematicos', c.ejes_tematicos,
      'periodo', c.periodo,
      'confidence_label', c.confidence_label,
      'is_definition', c.is_definition,
      'has_table', c.has_table
    ) AS metadata
  FROM minerd_chunks c
  JOIN minerd_documents d ON c.document_id = d.id
  WHERE (
    filter = '{}'::jsonb
    OR (
      (filter->>'nivel' IS NULL OR c.nivel::text = filter->>'nivel')
      AND (filter->>'ciclo' IS NULL OR c.ciclo::text = filter->>'ciclo')
      AND (filter->>'grado' IS NULL OR c.grado = filter->>'grado')
      AND (filter->>'area_curricular' IS NULL OR c.area_curricular ILIKE '%' || (filter->>'area_curricular') || '%')
    )
  )
  ORDER BY c.embedding <=> query_embedding
  LIMIT match_count;
$$;

-- Permisos estrictos mínimos
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT SELECT ON TABLE subscriptions TO authenticated;
GRANT ALL ON TABLE subscriptions TO service_role;
GRANT ALL ON TABLE webhook_events TO service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- 006_supabase_grants_new_keys.sql — Compatibilidad app móvil con era nueva
-- de API Keys de Supabase (2026-08-25)
--
-- SÍNTOMA: consultas REST con anon/publishable devuelven 42501
-- ("Grant the required privileges to the current role...") aunque la llave
-- autentique: las tablas de la app perdieron los GRANT para esos roles.
--
-- FIX: re-otorgar privilegios DML mínimos. RLS sigue gobernando QUÉ filas
-- ve cada usuario; esto solo devuelve el PERMISO de tipo de operación.
-- Idempotente. Ejecutar en Supabase SQL Editor.
-- ============================================================================

-- Perfil: lectura/escritura propia (RLS limita a auth.uid())
GRANT SELECT, INSERT, UPDATE ON TABLE public.profiles TO authenticated;

-- Conversaciones y mensajes: CRUD propio
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.conversations TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.messages TO authenticated;

-- Expedientes y artefactos: CRUD propio
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['artifacts', 'expedientes'] LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=t) THEN
      EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO authenticated', t);
    END IF;
  END LOOP;
END $$;

-- Suscripciones: solo lectura para el dueño (escritura = service_role/webhook)
GRANT SELECT ON TABLE public.subscriptions TO authenticated;

-- Catálogo curricular MINERD: lectura pública autenticada
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['minerd_documents', 'minerd_chunks'] LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=t) THEN
      EXECUTE format('GRANT SELECT ON TABLE public.%I TO authenticated', t);
    END IF;
  END LOOP;
END $$;

-- Secuencias asociadas a tablas con columnas serial (necesarias para INSERT)
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema='public'
  LOOP
    EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE public.%I TO authenticated', r.sequence_name);
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';

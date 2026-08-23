-- ============================================================================
-- grants_fix_2026-08-21.sql
--
-- Grants de acceso API tras aplicar apply_pending_bundle_2026-08-21.sql.
-- Las migraciones 002/003/004 otorgaban permisos a anon/authenticated pero
-- NO a service_role (el rol del backend con SUPABASE_SERVICE_KEY), lo que
-- provocaba HTTP 403 "permission denied" en tablas y RPCs.
--
-- Ejecutar en Supabase SQL Editor. Idempotente.
-- ============================================================================

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- MINERD: lectura para todos los roles de la API (RLS filtra el contenido),
-- escritura/ingesta solo para el backend (service_role).
GRANT SELECT ON minerd_documents, minerd_chunks TO anon, authenticated, service_role;
GRANT INSERT, UPDATE, DELETE ON minerd_documents, minerd_chunks TO service_role;

-- Telemetría RAG: solo el backend.
GRANT ALL ON minerd_query_log TO service_role;

-- Artefactos publicados: backend (service_role) + usuarios autenticados;
-- lectura pública anónima para los enlaces compartidos.
GRANT SELECT, INSERT, UPDATE, DELETE ON published_artifacts TO authenticated, service_role;
GRANT SELECT ON published_artifacts TO anon;

-- Expedientes: backend (service_role, única vía de acceso de la app) + usuarios.
GRANT SELECT, INSERT, UPDATE, DELETE ON expedientes TO authenticated, service_role;

-- Funciones RPC
GRANT EXECUTE ON FUNCTION increment_views(text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION match_chunks(vector(1536), int, jsonb) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hybrid_search(text, vector(1536), int, jsonb, float) TO anon, authenticated, service_role;

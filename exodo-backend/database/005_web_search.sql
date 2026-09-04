-- ============================================================================
-- 005_web_search.sql
--
-- Búsqueda web viva ($0, failover Serper->Brave->Tavily->Exa->Jina).
-- Tres tablas pequeñas:
--   web_search_cache           caché global con TTL (7 días) delante de todo.
--   web_search_usage            tope diario por usuario (Free 5 / Pro 30).
--   web_search_provider_usage   tope mensual por proveedor + breaker global.
-- El backend usa SERVICE_KEY (bypass RLS); las políticas cubren lecturas
-- propias por si algún día se expone con anon key.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Caché global de consultas
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS web_search_cache (
  query_hash  text        PRIMARY KEY,
  query       text        NOT NULL,
  results     jsonb       NOT NULL DEFAULT '[]'::jsonb,
  provider    text        NOT NULL DEFAULT 'unknown',
  created_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE web_search_cache ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS web_search_cache_select_all ON web_search_cache;
CREATE POLICY web_search_cache_select_all ON web_search_cache
  FOR SELECT USING (true);

-- ----------------------------------------------------------------------------
-- Uso diario por usuario (topes Free/Pro)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS web_search_usage (
  user_id uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  day     date        NOT NULL,
  count   integer     NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, day)
);

ALTER TABLE web_search_usage ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS web_search_usage_select_own ON web_search_usage;
CREATE POLICY web_search_usage_select_own ON web_search_usage
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS web_search_usage_insert_own ON web_search_usage;
CREATE POLICY web_search_usage_insert_own ON web_search_usage
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS web_search_usage_update_own ON web_search_usage;
CREATE POLICY web_search_usage_update_own ON web_search_usage
  FOR UPDATE USING (auth.uid() = user_id);

-- ----------------------------------------------------------------------------
-- Uso mensual por proveedor (topes free tier + breaker global)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS web_search_provider_usage (
  provider text        NOT NULL,
  month    date        NOT NULL,
  count    integer     NOT NULL DEFAULT 0,
  PRIMARY KEY (provider, month)
);

ALTER TABLE web_search_provider_usage ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS web_search_provider_usage_select_all ON web_search_provider_usage;
CREATE POLICY web_search_provider_usage_select_all ON web_search_provider_usage
  FOR SELECT USING (true);

-- Limpieza: el caché viejo se ignora por fecha en la query (TTL 7 días);
-- este índice acelera esa lectura.
CREATE INDEX IF NOT EXISTS idx_web_search_cache_created
  ON web_search_cache (created_at DESC);

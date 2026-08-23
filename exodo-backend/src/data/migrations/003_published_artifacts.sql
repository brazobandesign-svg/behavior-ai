-- ============================================================================
-- 003_published_artifacts.sql
--
-- Tabla y políticas para el sistema Cloud Artifacts de Éxodo.
-- Permite a los usuarios publicar artefactos generados por el chat (HTML,
-- Markdown, Mermaid, SVG, código) y compartirlos vía URL corta.
--
-- Aplicar con:
--   psql "$DATABASE_URL" -f src/data/migrations/003_published_artifacts.sql
--   -- o desde Supabase SQL Editor (pegar todo el bloque).
--
-- Dependencias: tabla profiles (001), gen_random_uuid() (pgcrypto).
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- Tabla principal
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS published_artifacts (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  slug            text        NOT NULL UNIQUE,
  user_id         uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title           text        NOT NULL CHECK (char_length(title) BETWEEN 1 AND 200),
  description     text        CHECK (description IS NULL OR char_length(description) <= 500),
  kind            text        NOT NULL CHECK (kind IN ('html','markdown','mermaid','svg','code','react')),
  language        text        CHECK (language IS NULL OR char_length(language) <= 40),
  source_code     text        NOT NULL CHECK (char_length(source_code) BETWEEN 1 AND 200000),
  metadata        jsonb       NOT NULL DEFAULT '{}'::jsonb,
  is_public       boolean     NOT NULL DEFAULT true,
  views_count     integer     NOT NULL DEFAULT 0 CHECK (views_count >= 0),
  expires_at      timestamptz,                              -- null = permanente (hazak)
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Índices
-- ---------------------------------------------------------------------------

-- Búsqueda por slug
CREATE UNIQUE INDEX IF NOT EXISTS idx_published_artifacts_slug
  ON published_artifacts (slug);

-- Listado por usuario (mis artefactos).
CREATE INDEX IF NOT EXISTS idx_published_artifacts_user_created
  ON published_artifacts (user_id, created_at DESC);

-- Limpieza de expirados: usado por cron semanal.
CREATE INDEX IF NOT EXISTS idx_published_artifacts_expires
  ON published_artifacts (expires_at)
  WHERE expires_at IS NOT NULL;

-- Listado público reciente
CREATE INDEX IF NOT EXISTS idx_published_artifacts_public_recent
  ON published_artifacts (created_at DESC)
  WHERE is_public = true;

-- ---------------------------------------------------------------------------
-- Trigger updated_at
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION trg_set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS published_artifacts_set_updated_at ON published_artifacts;
CREATE TRIGGER published_artifacts_set_updated_at
  BEFORE UPDATE ON published_artifacts
  FOR EACH ROW
  EXECUTE FUNCTION trg_set_updated_at();

-- ---------------------------------------------------------------------------
-- Función: incrementar vistas de forma atómica
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION increment_views(p_slug text)
RETURNS integer AS $$
DECLARE
  v_new integer;
BEGIN
  UPDATE published_artifacts
     SET views_count = views_count + 1
   WHERE slug = p_slug
     AND is_public = true
     AND (expires_at IS NULL OR expires_at > now())
  RETURNING views_count INTO v_new;

  RETURN COALESCE(v_new, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE ALL ON FUNCTION increment_views(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION increment_views(text) TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

ALTER TABLE published_artifacts ENABLE ROW LEVEL SECURITY;

-- Lectura pública: cualquiera puede ver artefactos públicos no expirados.
DROP POLICY IF EXISTS published_artifacts_read_public ON published_artifacts;
CREATE POLICY published_artifacts_read_public ON published_artifacts
  FOR SELECT
  TO anon, authenticated
  USING (
    is_public = true
    AND (expires_at IS NULL OR expires_at > now())
  );

-- Inserción: sólo el propio usuario autenticado.
DROP POLICY IF EXISTS published_artifacts_insert_own ON published_artifacts;
CREATE POLICY published_artifacts_insert_own ON published_artifacts
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Actualización: sólo el dueño.
DROP POLICY IF EXISTS published_artifacts_update_own ON published_artifacts;
CREATE POLICY published_artifacts_update_own ON published_artifacts
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Borrado: sólo el dueño.
DROP POLICY IF EXISTS published_artifacts_delete_own ON published_artifacts;
CREATE POLICY published_artifacts_delete_own ON published_artifacts
  FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON published_artifacts TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON published_artifacts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON published_artifacts TO service_role;
GRANT EXECUTE ON FUNCTION increment_views(text) TO service_role;

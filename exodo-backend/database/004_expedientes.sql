-- ============================================================================
-- 004_expedientes.sql
--
-- Módulo "Expedientes": almacén privado de documentos/tablas/interactivos
-- generados por el usuario. Cada registro pertenece a un único usuario y
-- está protegido por Row Level Security (auth.uid() = user_id).
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- Tabla principal
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS expedientes (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  chat_id         text,
  title           text        NOT NULL,
  category        text        NOT NULL CHECK (category IN ('documento', 'tabla', 'interactivo')),
  file_format     text        NOT NULL CHECK (file_format IN ('docx', 'xlsx', 'pdf', 'html', 'svg', 'md')),
  content_payload text        NOT NULL,
  metadata        jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Índices
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_expedientes_user_id
  ON expedientes (user_id);

CREATE INDEX IF NOT EXISTS idx_expedientes_category
  ON expedientes (user_id, category);

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

DROP TRIGGER IF EXISTS expedientes_set_updated_at ON expedientes;
CREATE TRIGGER expedientes_set_updated_at
  BEFORE UPDATE ON expedientes
  FOR EACH ROW
  EXECUTE FUNCTION trg_set_updated_at();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

ALTER TABLE expedientes ENABLE ROW LEVEL SECURITY;

-- Lectura: sólo el dueño.
DROP POLICY IF EXISTS expedientes_select_own ON expedientes;
CREATE POLICY expedientes_select_own ON expedientes
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- Inserción: sólo el propio usuario autenticado.
DROP POLICY IF EXISTS expedientes_insert_own ON expedientes;
CREATE POLICY expedientes_insert_own ON expedientes
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Actualización: sólo el dueño.
DROP POLICY IF EXISTS expedientes_update_own ON expedientes;
CREATE POLICY expedientes_update_own ON expedientes
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Borrado: sólo el dueño.
DROP POLICY IF EXISTS expedientes_delete_own ON expedientes;
CREATE POLICY expedientes_delete_own ON expedientes
  FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON expedientes TO authenticated, service_role;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

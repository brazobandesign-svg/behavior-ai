-- ============================================================================
-- 007_delete_user_account.sql — P0 auditoría pre-lanzamiento: borrado real
-- de cuentas.
--
-- Problema 1: no existía política RLS de DELETE para `profiles`, por lo que el
-- intento de borrado desde el cliente (app_state.deleteAccount) fallaba
-- silenciosamente con RLS y el perfil quedaba huérfano en la nube.
--
-- Problema 2: borrar solo el perfil dejaba auth.users, conversations y
-- expedientes vivos (datos personales sin purga).
--
-- Solución: política DELETE propia + RPC `delete_user_account()` SECURITY
-- DEFINER que purga en cascada (profiles, conversations, expedientes) y
-- elimina al usuario técnico de auth.users. Idempotente.
-- ============================================================================

-- 1. Política RLS DELETE para profiles (el dueño borra su propio perfil)
DROP POLICY IF EXISTS profiles_delete_own ON profiles;
CREATE POLICY profiles_delete_own ON profiles
    FOR DELETE TO authenticated
    USING (id = auth.uid());

-- 2. Función RPC para purga total (profiles + conversations + expedientes + auth.users)
CREATE OR REPLACE FUNCTION delete_user_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Borrar datos del usuario en cascada
  DELETE FROM profiles WHERE id = auth.uid();
  DELETE FROM conversations WHERE user_id = auth.uid();
  DELETE FROM expedientes WHERE user_id = auth.uid();
  -- Purgar usuario de autenticación técnica
  DELETE FROM auth.users WHERE id = auth.uid();
END;
$$;

GRANT EXECUTE ON FUNCTION delete_user_account() TO authenticated;

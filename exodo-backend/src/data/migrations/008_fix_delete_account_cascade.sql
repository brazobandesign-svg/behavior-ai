-- ============================================================================
-- 008_fix_delete_account_cascade.sql — Fix P0: el borrado de cuenta fallaba
-- en silencio.
--
-- Causa raíz: user_usage.user_id → profiles(id) WITHOUT ON DELETE CASCADE.
-- La RPC delete_user_account() borraba profiles PRIMERO; el FK de user_usage
-- revientaba el statement → la RPC lanzaba excepción → el cliente reintentaba
→ fallaba igual → return silencioso (el usuario veía que "no pasaba nada").
--
-- Fix: (1) cascada permanente en user_usage; (2) la RPC borra user_usage
-- ANTES de profiles (defensa en profundidad); (3) purga también 
-- refresh_tokens residuales no es necesario (auth cascada sola).
-- Idempotente: puede ejecutarse N veces.
-- ============================================================================

-- 1. Cascada permanente user_usage → profiles
ALTER TABLE public.user_usage
  DROP CONSTRAINT IF EXISTS user_usage_user_id_fkey;
ALTER TABLE public.user_usage
  ADD CONSTRAINT user_usage_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- 2. RPC corregida (mismo contrato). Nota: Stripe subscriptions.user_id es
--    ON DELETE SET NULL — el registro de billing queda huérfano a propósito
--    (auditoría de Stripe, no es dato personal del usuario).
CREATE OR REPLACE FUNCTION public.delete_user_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Contabilidad primero (FK hacia profiles sin depender de cascadas)
  DELETE FROM user_usage WHERE user_id = auth.uid();
  -- Contenido del usuario (messages se va por CASCADE de conversations)
  DELETE FROM conversations WHERE user_id = auth.uid();
  DELETE FROM expedientes WHERE user_id = auth.uid();
  DELETE FROM published_artifacts WHERE user_id = auth.uid();
  -- Perfil y usuario técnico
  DELETE FROM profiles WHERE id = auth.uid();
  DELETE FROM auth.users WHERE id = auth.uid();
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_user_account() TO authenticated;

-- ============================================================================
-- 005_atomic_usage.sql — C7: Contador de uso BLINDADO y ATÓMICO
-- Problema: el backend hacía read-modify-write del total en memoria y lo
-- sobrescribía con UPDATE absoluto → lost-updates entre requests concurrentes
-- y entre réplicas (Railway), y pérdida del delta en cada restart.
--
-- Solución: RPC que INCREMENTA dentro de Postgres con rollover diario/mensual
-- calculado en zona AST (America/Santo_Domingo), igual que la lógica JS.
-- Idempotente: puede ejecutarse N veces.
-- ============================================================================

create or replace function public.increment_user_usage(
  p_user_id uuid,
  p_tokens integer,
  p_images integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today text;
  v_month text;
begin
  v_today := to_char((now() at time zone 'America/Santo_Domingo'), 'YYYY-MM-DD');
  v_month := substr(v_today, 1, 7);

  update user_usage set
    tokens_used = case
      when period = v_today then coalesce(tokens_used, 0) + greatest(coalesce(p_tokens, 1), 1)
      else greatest(coalesce(p_tokens, 1), 1)
    end,
    images_used = case
      when substr(period, 1, 7) = v_month then coalesce(images_used, 0) + coalesce(p_images, 0)
      else coalesce(p_images, 0)
    end,
    period = v_today,
    updated_at = now()
  where user_id = p_user_id;

  if not found then
    insert into user_usage (user_id, tokens_used, tokens_limit, images_used, period, updated_at)
    values (
      p_user_id,
      greatest(coalesce(p_tokens, 1), 1),
      6000, -- límite Genesis/free por defecto; planGuard lo ajusta al leer
      coalesce(p_images, 0),
      v_today,
      now()
    );
  end if;
end;
$$;

-- Solo el service_role debe invocar la contabilidad de uso.
revoke execute on function public.increment_user_usage(uuid, integer, integer) from public, anon, authenticated;

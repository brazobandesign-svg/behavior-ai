-- ═══════════════════════════════════════════════════════════
-- ÉXODO BY BEHAVIOR — Esquema de Base de Datos (Supabase)
-- Bible sección 07 — Ejecutar en el SQL Editor de Supabase
-- ═══════════════════════════════════════════════════════════

-- Habilitar pgvector para RAG dominicano
create extension if not exists vector with schema public;

-- PROFILES: extiende auth.users de Supabase Auth
create table profiles (
  id            uuid references auth.users primary key,
  full_name     text,
  plan          text default 'genesis',   -- 'genesis' | 'hazak'
  avatar_url    text,
  onboarding    jsonb,                     -- perfil detectado: 'docente' | 'abogado' | 'general'
  created_at    timestamp default now()
);

create table user_usage (
  id              uuid default gen_random_uuid() primary key,
  user_id         uuid references profiles(id),
  tokens_used     bigint default 0,
  tokens_limit    bigint default 15000,   -- Genesis: 15k | Hazak: 150k
  period          date,                    -- '2026-06-25' (diario, se resetea)
  updated_at      timestamp default now(),
  unique(user_id, period)
);

-- GUEST_IP_LIMITS: contador de mensajes para usuarios anónimos (invitados) por IP
-- Se usa la dirección IP pública como clave y se reinicia cada 24 horas.
create table guest_ip_limits (
  id            uuid default gen_random_uuid() primary key,
  ip            text not null unique,
  messages_sent int default 0,
  reset_time    timestamp with time zone,
  created_at    timestamp default now()
);

-- CONVERSATIONS: hilos de conversación
create table conversations (
  id            uuid default gen_random_uuid() primary key,
  user_id       uuid references profiles(id),
  title         text,                      -- auto-generado del primer mensaje
  model_plan    text,                      -- 'genesis' | 'hazak'
  is_incognito  boolean default false,     -- si true, no guardar mensajes
  created_at    timestamp default now(),
  updated_at    timestamp default now()
);

-- MESSAGES: mensajes individuales (no guardar si is_incognito=true)
create table messages (
  id                uuid default gen_random_uuid() primary key,
  conversation_id   uuid references conversations(id) on delete cascade,
  role              text not null,          -- 'user' | 'assistant'
  content           text not null,
  intent_detected   text,                   -- 'REDACCION' | 'SIMPLE' | 'RAZONAMIENTO' | 'DOCUMENTO' | 'IMAGEN'
  model_called      text,                   -- modelo real que respondió (interno, no mostrar al user)
  tokens_input      int,
  tokens_output     int,
  created_at        timestamp default now()
);

-- SUBSCRIPTIONS: estado de suscripciones
create table subscriptions (
  id                    uuid default gen_random_uuid() primary key,
  user_id               uuid references profiles(id),
  plan                  text,               -- 'hazak'
  status                text,               -- 'active' | 'cancelled' | 'past_due' | 'trialing'
  provider              text,               -- 'stripe' | 'google_play'
  provider_sub_id       text,
  current_period_end    timestamp,
  created_at            timestamp default now()
);

-- RAG_DOCUMENTS: contexto dominicano (MINERD, legal, etc.)
create table rag_documents (
  id          uuid default gen_random_uuid() primary key,
  title       text not null,
  category    text,                          -- 'minerd' | 'legal' | 'empresarial' | 'general'
  content     text not null,
  embedding   vector(1536),                  -- para búsqueda semántica (pgvector)
  source_url  text,
  created_at  timestamp default now()
);

-- RLS: habilitar Row Level Security en todas las tablas de usuario
alter table profiles      enable row level security;
alter table user_usage    enable row level security;
alter table conversations enable row level security;
alter table messages      enable row level security;
alter table subscriptions enable row level security;
alter table guest_ip_limits enable row level security;

-- ═══════════════════════════════════════════════════════════
-- POLÍTICAS RLS — agregar DESPUÉS de habilitar RLS.
-- Sin estas policies, TODAS las queries desde el cliente devuelven
-- 401/403 silencioso (PostgREST respeta RLS con anon + authenticated).
-- El service_role (usado por el backend Node) bypasea RLS, por eso
-- el backend puede leer/escribir sin problema, pero el cliente Flutter
-- queda bloqueado.
-- ═══════════════════════════════════════════════════════════

-- ─── PROFILES ────────────────────────────────────────────────
-- El usuario solo puede ver/editar su propio perfil.
drop policy if exists "profiles_select_own"      on profiles;
drop policy if exists "profiles_insert_own"      on profiles;
drop policy if exists "profiles_update_own"      on profiles;
create policy "profiles_select_own" on profiles
  for select using (auth.uid() = id);
create policy "profiles_insert_own" on profiles
  for insert with check (auth.uid() = id);
create policy "profiles_update_own" on profiles
  for update using (auth.uid() = id);

-- ─── USER_USAGE ──────────────────────────────────────────────
drop policy if exists "user_usage_select_own"   on user_usage;
drop policy if exists "user_usage_insert_own"   on user_usage;
drop policy if exists "user_usage_update_own"   on user_usage;
create policy "user_usage_select_own" on user_usage
  for select using (auth.uid() = user_id);
create policy "user_usage_insert_own" on user_usage
  for insert with check (auth.uid() = user_id);
create policy "user_usage_update_own" on user_usage
  for update using (auth.uid() = user_id);

-- ─── CONVERSATIONS ───────────────────────────────────────────
drop policy if exists "conversations_select_own"  on conversations;
drop policy if exists "conversations_insert_own"  on conversations;
drop policy if exists "conversations_update_own"  on conversations;
drop policy if exists "conversations_delete_own"  on conversations;
create policy "conversations_select_own" on conversations
  for select using (auth.uid() = user_id);
create policy "conversations_insert_own" on conversations
  for insert with check (auth.uid() = user_id);
create policy "conversations_update_own" on conversations
  for update using (auth.uid() = user_id);
create policy "conversations_delete_own" on conversations
  for delete using (auth.uid() = user_id);

-- ─── MESSAGES ────────────────────────────────────────────────
-- Solo se accede a messages si la conversación pertenece al usuario.
drop policy if exists "messages_select_via_conv"  on messages;
drop policy if exists "messages_insert_via_conv"  on messages;
drop policy if exists "messages_delete_via_conv"  on messages;
create policy "messages_select_via_conv" on messages
  for select using (
    exists (
      select 1 from conversations c
      where c.id = messages.conversation_id
        and c.user_id = auth.uid()
    )
  );
create policy "messages_insert_via_conv" on messages
  for insert with check (
    exists (
      select 1 from conversations c
      where c.id = messages.conversation_id
        and c.user_id = auth.uid()
    )
  );
create policy "messages_delete_via_conv" on messages
  for delete using (
    exists (
      select 1 from conversations c
      where c.id = messages.conversation_id
        and c.user_id = auth.uid()
    )
  );

-- ─── SUBSCRIPTIONS ───────────────────────────────────────────
drop policy if exists "subscriptions_select_own" on subscriptions;
create policy "subscriptions_select_own" on subscriptions
  for select using (auth.uid() = user_id);
-- INSERT/UPDATE/DELETE solo desde service_role (backend).

-- ─── RAG_DOCUMENTS ───────────────────────────────────────────
-- Catálogo de dominio (MINERD, legal, etc.) — lectura pública.
drop policy if exists "rag_documents_select_public" on rag_documents;
create policy "rag_documents_select_public" on rag_documents
  for select using (true);
-- INSERT/UPDATE/DELETE solo desde service_role.

-- ─── GUEST_IP_LIMITS ─────────────────────────────────────────
-- Lectura, inserción y actualización pública para control anti-abuso por IP
drop policy if exists "guest_ip_limits_select_public" on guest_ip_limits;
drop policy if exists "guest_ip_limits_insert_public" on guest_ip_limits;
drop policy if exists "guest_ip_limits_update_public" on guest_ip_limits;
create policy "guest_ip_limits_select_public" on guest_ip_limits
  for select using (true);
create policy "guest_ip_limits_insert_public" on guest_ip_limits
  for insert with check (true);
create policy "guest_ip_limits_update_public" on guest_ip_limits
  for update using (true);

-- ═══════════════════════════════════════════════════════════
-- NOTA OPERATIVA
-- ─────────────────────────────────────────────────────────────
-- Para que el backend Node pueda escribir (service_role bypassa RLS):
--   • SUPABASE_SERVICE_KEY debe ser la key "service_role", NO "anon".
--   • Está en: Supabase Dashboard → Settings → API → service_role.
-- Para que el cliente Flutter pueda escribir (anon + authenticated):
--   • Las policies de arriba son suficientes.
--   • SUPABASE_ANON_KEY se usa en lib/services/supabase_service.dart
--     y está separada del service_role (eso es correcto).
-- ═══════════════════════════════════════════════════════════

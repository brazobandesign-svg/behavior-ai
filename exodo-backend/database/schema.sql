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

-- USER_USAGE: contador de tokens por período diario
create table user_usage (
  id              uuid default gen_random_uuid() primary key,
  user_id         uuid references profiles(id),
  tokens_used     bigint default 0,
  tokens_limit    bigint default 15000,   -- Genesis: 15k | Hazak: 150k
  period          date,                    -- '2026-06-25' (diario, se resetea)
  updated_at      timestamp default now(),
  unique(user_id, period)
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

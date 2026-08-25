-- ═══════════════════════════════════════════════════════════════════════════════
-- minerd_schema.sql
-- Éxodo by Behavior — Esquema de grounding RAG MINERD
-- ═══════════════════════════════════════════════════════════════════════════════
--
-- OBJETIVO: Almacenar los documentos oficiales del MINERD (Ley General de
-- Educación, diseños curriculares, guías pedagógicas) y permitir búsqueda
-- semántica + full-text sobre los chunks pedagógicos, con metadatos de
-- nivel/ciclo/grado/área/competencia.
--
-- DIMENSIÓN DE EMBEDDING: 1536 (compatible con text-embedding-3-small de
-- OpenAI y la mayoría de modelos multilingües). Si cambias de modelo:
--   ALTER TABLE minerd_chunks ALTER COLUMN embedding TYPE vector(<nueva_dim>);
--   REINDEX INDEX idx_minerd_chunks_embedding;
--
-- REQUISITOS: Postgres 15+ con extensión pgvector habilitada en Supabase.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── Extensiones ─────────────────────────────────────────────────────────────

create extension if not exists vector;
create extension if not exists pg_trgm;
create extension if not exists pgcrypto;            -- gen_random_uuid()

-- ─── Enums ───────────────────────────────────────────────────────────────────

create type minerd_nivel as enum (
  'inicial',
  'primario',
  'secundario',
  'transversal'
);

create type minerd_ciclo as enum (
  '1er_ciclo',
  '2do_ciclo',
  'N/A'
);

create type minerd_doc_type as enum (
  'ley',
  'ordenanza',
  'diseno',
  'guia',
  'plan',
  'reglamento',
  'resolucion'
);

create type minerd_confidence as enum (
  'high',     -- Contiene definición, tabla, cita literal
  'medium',   -- Desarrollo conceptual o procedimental
  'low'       -- Prólogo, portada, índice, anexos
);

-- ─── Tabla: minerd_documents ────────────────────────────────────────────────
-- Documentos fuente canónicos. Una fila por PDF / documento indexado.

create table minerd_documents (
  id              uuid primary key default gen_random_uuid(),
  short_name      text not null unique,                 -- "ORD-1-2021", "DC-PRIM-1C-2021"
  title           text not null,                        -- Título oficial completo
  doc_type        minerd_doc_type not null,
  version         text,                                 -- "2021", "1997", "1ra-ed"
  published_at    date,
  source_url      text,                                 -- URL oficial de descarga
  local_path      text,                                 -- ruta en storage
  file_hash       text not null,                        -- sha256
  total_pages     int,
  language        text not null default 'es-DO',
  status          text not null default 'active',       -- 'active' | 'superseded' | 'draft'
  superseded_by   uuid references minerd_documents(id) on delete set null,
  metadata        jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint minerd_documents_short_name_length_chk check (char_length(short_name) between 4 and 32),
  constraint minerd_documents_title_length_chk       check (char_length(title) <= 300),
  constraint minerd_documents_status_chk            check (status in ('active', 'superseded', 'draft'))
);

create index idx_minerd_documents_status on minerd_documents(status) where status = 'active';
create index idx_minerd_documents_type   on minerd_documents(doc_type);
create index idx_minerd_documents_year   on minerd_documents(published_at);
create index idx_minerd_documents_meta   on minerd_documents using gin(metadata);

-- ─── Tabla: minerd_chunks ─────────────────────────────────────────────────
-- Fragmentos semánticos con embedding y metadatos pedagógicos.

create table minerd_chunks (
  id                          uuid primary key default gen_random_uuid(),
  document_id                 uuid not null references minerd_documents(id) on delete cascade,
  chunk_index                 int not null,              -- posición dentro del documento
  content                     text not null,             -- texto del chunk
  content_tokens              int,                       -- tokens estimados
  embedding                   vector(1536),              -- AJUSTAR si cambias de modelo

  -- Localización jerárquica dentro del documento
  page_number                 int,
  section                     text,                      -- "Capítulo III", "Artículo 12"
  subsection                  text,
  paragraph_index             int,

  -- Metadatos pedagógicos (RAG grounding)
  nivel                       minerd_nivel,
  ciclo                       minerd_ciclo,
  grado                       text,                      -- '1'..'6' | null
  area_curricular             text,                      -- "Matemáticas", "Lengua Española", ...
  competencia_fundamental     text[],                    -- ["Comunicación", "Pensamiento Lógico, Creativo y Crítico", ...]
  competencia_especifica      text,                      -- texto literal de la CE
  indicadores_logro           text[],                    -- array de indicadores asociados
  ejes_tematicos              text[],                    -- ["Numeración", "Geometría", ...]
  periodo                     text,                      -- "I", "II", "III", "IV", "anual"

  -- Señales de calidad
  has_table                   boolean not null default false,
  has_list                    boolean not null default false,
  is_definition               boolean not null default false,
  is_citation                 boolean not null default false,
  confidence_label            minerd_confidence not null default 'medium',

  -- Búsqueda full-text (BM25-like)
  content_tsv                 tsvector,

  created_at                  timestamptz not null default now(),

  unique (document_id, chunk_index)
);

-- Índices
create index idx_minerd_chunks_document           on minerd_chunks(document_id, chunk_index);
create index idx_minerd_chunks_nivel_ciclo_grado  on minerd_chunks(nivel, ciclo, grado);
create index idx_minerd_chunks_area               on minerd_chunks(area_curricular);
create index idx_minerd_chunks_cf                 on minerd_chunks using gin(competencia_fundamental);
create index idx_minerd_chunks_ejes              on minerd_chunks using gin(ejes_tematicos);
create index idx_minerd_chunks_indicadores        on minerd_chunks using gin(indicadores_logro);
create index idx_minerd_chunks_tsv                on minerd_chunks using gin(content_tsv);
create index idx_minerd_chunks_embedding          on minerd_chunks using ivfflat (embedding vector_cosine_ops) with (lists = 100);
create index idx_minerd_chunks_confidence         on minerd_chunks(confidence_label) where confidence_label = 'high';

-- ─── Función: actualizar tsvector automáticamente ───────────────────────────
-- Trigger BEFORE INSERT/UPDATE que recompone el tsvector con pesos por campo.
-- Peso A: contenido principal. Peso B: competencia fundamental. Peso C: contexto pedagógico.

create or replace function minerd_chunks_update_tsv()
returns trigger
language plpgsql
as $$
begin
  new.content_tsv :=
    setweight(to_tsvector('spanish', coalesce(new.content, '')), 'A') ||
    setweight(to_tsvector('spanish', coalesce(array_to_string(new.competencia_fundamental, ' '), '')), 'B') ||
    setweight(to_tsvector('spanish', coalesce(new.area_curricular, '')), 'C') ||
    setweight(to_tsvector('spanish', coalesce(array_to_string(new.ejes_tematicos, ' '), '')), 'C') ||
    setweight(to_tsvector('spanish', coalesce(array_to_string(new.indicadores_logro, ' '), '')), 'C') ||
    setweight(to_tsvector('spanish', coalesce(new.competencia_especifica, '')), 'C');
  return new;
end;
$$;

create trigger trg_minerd_chunks_tsv
  before insert or update of content, competencia_fundamental, area_curricular,
    ejes_tematicos, indicadores_logro, competencia_especifica
  on minerd_chunks
  for each row execute function minerd_chunks_update_tsv();

-- ─── Función: updated_at automático ────────────────────────────────────────

create or replace function minerd_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger trg_minerd_documents_updated_at
  before update on minerd_documents
  for each row execute function minerd_set_updated_at();

-- ─── RLS ────────────────────────────────────────────────────────────────────
-- El corpus MINERD es público para lectura. La escritura solo la hace el
-- service role (backend de Éxodo) durante la ingestion, que bypasea RLS.

alter table minerd_documents enable row level security;
alter table minerd_chunks    enable row level security;

-- Lectura pública: todos pueden leer documentos activos y sus chunks
create policy "minerd_documents_public_read"
  on minerd_documents
  for select
  to anon, authenticated
  using (status = 'active');

create policy "minerd_chunks_public_read"
  on minerd_chunks
  for select
  to anon, authenticated
  using (
    exists (
      select 1
      from minerd_documents d
      where d.id = minerd_chunks.document_id
        and d.status = 'active'
    )
  );

-- Escritura: solo service role (bypasea RLS automáticamente).
-- No creamos policies para INSERT/UPDATE/DELETE; el service role las omite.

-- ─── Función RPC: match_chunks (búsqueda semántica con filtros pedagógicos) ─

create or replace function match_chunks(
  query_embedding vector(1536),
  match_count     int  default 10,
  filter          jsonb default '{}'::jsonb
)
returns table (
  id            uuid,
  document_id   uuid,
  content       text,
  similarity    float,
  metadata      jsonb
)
language sql
stable
security definer
as $$
  select
    c.id,
    c.document_id,
    c.content,
    1 - (c.embedding <=> query_embedding) as similarity,
    jsonb_build_object(
      'short_name', d.short_name,
      'title', d.title,
      'doc_type', d.doc_type,
      'version', d.version,
      'page', c.page_number,
      'section', c.section,
      'subsection', c.subsection,
      'nivel', c.nivel,
      'ciclo', c.ciclo,
      'grado', c.grado,
      'area_curricular', c.area_curricular,
      'competencias_fundamentales', c.competencia_fundamental,
      'competencia_especifica', c.competencia_especifica,
      'indicadores_logro', c.indicadores_logro,
      'ejes_tematicos', c.ejes_tematicos,
      'periodo', c.periodo,
      'confidence_label', c.confidence_label,
      'is_definition', c.is_definition,
      'has_table', c.has_table
    ) as metadata
  from minerd_chunks c
  join minerd_documents d on c.document_id = d.id
  where d.status = 'active'
    and (
      filter = '{}'::jsonb
      or (
        (filter->>'nivel' is null or c.nivel::text = filter->>'nivel')
        and (filter->>'ciclo' is null or c.ciclo::text = filter->>'ciclo')
        and (filter->>'grado' is null or c.grado = filter->>'grado')
        and (filter->>'area_curricular' is null or c.area_curricular = filter->>'area_curricular')
        and (filter->>'periodo' is null or c.periodo = filter->>'periodo')
        and (
          (filter->>'competencia_fundamental') is null
          or c.competencia_fundamental @> array[filter->>'competencia_fundamental']
        )
        and (
          (filter->>'eje_tematico') is null
          or c.ejes_tematicos @> array[filter->>'eje_tematico']
        )
        and (filter->>'short_name' is null or d.short_name = filter->>'short_name')
        and (
          (filter->>'min_similarity') is null
          or (1 - (c.embedding <=> query_embedding)) >= (filter->>'min_similarity')::float
        )
      )
    )
  order by c.embedding <=> query_embedding
  limit greatest(match_count, 1);
$$;

grant execute on function match_chunks(vector(1536), int, jsonb) to anon, authenticated, service_role;

-- ─── Función RPC: hybrid_search (vectorial + full-text) ────────────────────────

create or replace function hybrid_search(
  query_text       text,
  query_embedding  vector(1536),
  match_count      int  default 10,
  filter           jsonb default '{}'::jsonb,
  semantic_weight  float default 0.7
)
returns table (
  id            uuid,
  document_id   uuid,
  content       text,
  score         float,
  semantic      float,
  fulltext      float,
  metadata      jsonb
)
language sql
stable
as $$
  with sem as (
    select c.id, 1 - (c.embedding <=> query_embedding) as s
    from minerd_chunks c
    join minerd_documents d on c.document_id = d.id
    where d.status = 'active'
    order by c.embedding <=> query_embedding
    limit 50
  ),
  fts as (
    select c.id,
           ts_rank_cd(c.content_tsv, websearch_to_tsquery('spanish', query_text)) as s
    from minerd_chunks c
    join minerd_documents d on c.document_id = d.id
    where d.status = 'active'
      and c.content_tsv @@ websearch_to_tsquery('spanish', query_text)
    order by s desc
    limit 50
  ),
  combined as (
    select coalesce(sem.id, fts.id) as id,
           coalesce(sem.s, 0) * semantic_weight
         + coalesce(fts.s, 0) * (1 - semantic_weight) as score,
           coalesce(sem.s, 0) as semantic,
           coalesce(fts.s, 0) as fulltext
    from sem
    full outer join fts on sem.id = fts.id
  )
  select
    c.id,
    c.document_id,
    c.content,
    combined.score,
    combined.semantic,
    combined.fulltext,
    jsonb_build_object(
      'short_name', d.short_name,
      'title', d.title,
      'doc_type', d.doc_type,
      'page', c.page_number,
      'section', c.section,
      'subsection', c.subsection,
      'nivel', c.nivel,
      'ciclo', c.ciclo,
      'grado', c.grado,
      'area_curricular', c.area_curricular,
      'competencias_fundamentales', c.competencia_fundamental,
      'competencia_especifica', c.competencia_especifica,
      'indicadores_logro', c.indicadores_logro,
      'ejes_tematicos', c.ejes_tematicos,
      'periodo', c.periodo,
      'confidence_label', c.confidence_label
    ) as metadata
  from combined
  join minerd_chunks c on c.id = combined.id
  join minerd_documents d on c.document_id = d.id
  where
    (filter = '{}'::jsonb)
    or (
      (filter->>'nivel' is null or c.nivel::text = filter->>'nivel')
      and (filter->>'ciclo' is null or c.ciclo::text = filter->>'ciclo')
      and (filter->>'grado' is null or c.grado = filter->>'grado')
      and (filter->>'area_curricular' is null or c.area_curricular = filter->>'area_curricular')
      and (
        (filter->>'competencia_fundamental') is null
        or c.competencia_fundamental @> array[filter->>'competencia_fundamental']
      )
    )
  order by combined.score desc
  limit greatest(match_count, 1);
$$;

grant execute on function hybrid_search(text, vector(1536), int, jsonb, float) to anon, authenticated, service_role;

-- ─── Tabla: minerd_query_log (telemetría opcional) ────────────────────────────

create table if not exists minerd_query_log (
  id              uuid primary key default gen_random_uuid(),
  query_text      text not null,
  matched_doc_ids uuid[],
  top_similarity  float,
  user_plan       text,
  chunks_returned int,
  latency_ms      int,
  created_at      timestamptz not null default now()
);

create index idx_minerd_query_log_created on minerd_query_log(created_at desc);
create index idx_minerd_query_log_plan     on minerd_query_log(user_plan);

alter table minerd_query_log enable row level security;
create policy "minerd_query_log_service_only"
  on minerd_query_log for all
  to service_role
  using (true)
  with check (true);

-- ─── Grants de acceso API ────────────────────────────────────────────────────
-- service_role = backend (SUPABASE_SERVICE_KEY). Sin estos GRANTs, PostgREST
-- responde 403 "permission denied" aunque las policies RLS permitan el acceso.

grant usage on schema public to anon, authenticated, service_role;
grant select on minerd_documents, minerd_chunks to anon, authenticated, service_role;
grant insert, update, delete on minerd_documents, minerd_chunks to service_role;
grant all on minerd_query_log to service_role;

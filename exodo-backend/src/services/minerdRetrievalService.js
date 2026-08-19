'use strict';

/**
 * ============================================================================
 * minerdRetrievalService.js — Recuperación semántica para grounding MINERD
 * ============================================================================
 *
 * Dado un query del docente, genera su embedding (OpenAI text-embedding-3-small,
 * 1536 dim) y consulta la RPC `match_chunks` de Supabase (pgvector cosine
 * similarity), aplicando filtros pedagógicos opcionales y devolviendo los
 * chunks formateados y ordenados por similitud.
 *
 * Filtros opcionales (mapeados al `filter` jsonb de match_chunks):
 *   - nivel   -> filter.nivel            ('inicial'|'primario'|'secundario'|'transversal')
 *   - ciclo   -> filter.ciclo            ('1er_ciclo'|'2do_ciclo'|'N/A')
 *   - grado   -> filter.grado            ('1'..'6')
 *   - area    -> filter.area_curricular  ('Matemáticas', 'Lengua Española', ...)
 */

const OpenAI = require('openai');
const supabase = require('../config/supabase');

const EMBEDDING_MODEL = 'text-embedding-3-small';
const DEFAULT_LIMIT = 5;
const MAX_LIMIT = 20;

/**
 * Error tipado para fallos del servicio de recuperación.
 */
class MinerdRetrievalError extends Error {
  constructor(message, code, details) {
    super(message);
    this.name = 'MinerdRetrievalError';
    this.code = code;
    this.details = details || null;
    if (Error.captureStackTrace) Error.captureStackTrace(this, this.constructor);
  }
}

let _openai = null;

/**
 * Cliente OpenAI perezoso. Lanza si OPENAI_API_KEY no está configurada.
 */
function getOpenAI() {
  if (!process.env.OPENAI_API_KEY) {
    throw new MinerdRetrievalError(
      'OPENAI_API_KEY no está configurada en .env',
      'MISSING_OPENAI_KEY'
    );
  }
  if (!_openai) {
    _openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  }
  return _openai;
}

/**
 * Genera el embedding (number[]) del query con text-embedding-3-small.
 */
async function embedQuery(query) {
  const openai = getOpenAI();
  const response = await openai.embeddings.create({
    model: EMBEDDING_MODEL,
    input: String(query).replace(/\n+/g, ' ').trim(),
  });
  const embedding = response.data && response.data[0] && response.data[0].embedding;
  if (!Array.isArray(embedding) || embedding.length === 0) {
    throw new MinerdRetrievalError(
      'Embedding vacío devuelto por OpenAI',
      'EMPTY_EMBEDDING'
    );
  }
  return embedding;
}

/**
 * Construye el `filter` jsonb para match_chunks a partir de las opciones.
 */
function buildFilter({ nivel, ciclo, grado, area }) {
  const filter = {};
  if (nivel) filter.nivel = String(nivel);
  if (ciclo) filter.ciclo = String(ciclo);
  if (grado !== undefined && grado !== null && String(grado) !== '') {
    filter.grado = String(grado);
  }
  if (area) filter.area_curricular = String(area);
  return filter;
}

/**
 * Formatea una fila devuelta por match_chunks (id, document_id, content,
 * similarity, metadata jsonb) a un objeto plano y legible.
 */
function formatChunk(row) {
  const m = (row && row.metadata) || {};
  return {
    id: row.id,
    document_id: row.document_id,
    content: row.content,
    similarity: Number.isFinite(row.similarity) ? row.similarity : null,
    source: {
      short_name: m.short_name || null,
      title: m.title || null,
      doc_type: m.doc_type || null,
      version: m.version || null,
      page: m.page ?? null,
      section: m.section || null,
      subsection: m.subsection || null,
    },
    nivel: m.nivel || null,
    ciclo: m.ciclo || null,
    grado: m.grado || null,
    area_curricular: m.area_curricular || null,
    competencias_fundamentales: Array.isArray(m.competencias_fundamentales)
      ? m.competencias_fundamentales
      : [],
    competencia_especifica: m.competencia_especifica || null,
    indicadores_logro: Array.isArray(m.indicadores_logro) ? m.indicadores_logro : [],
    ejes_tematicos: Array.isArray(m.ejes_tematicos) ? m.ejes_tematicos : [],
    periodo: m.periodo || null,
    confidence_label: m.confidence_label || null,
    is_definition: !!m.is_definition,
    has_table: !!m.has_table,
  };
}

/**
 * Recupera chunks del corpus MINERD por similitud semántica (coseno).
 *
 * @param {string} query Texto de la consulta del docente.
 * @param {object} [options]
 * @param {string} [options.nivel]    'inicial'|'primario'|'secundario'|'transversal'
 * @param {string} [options.ciclo]    '1er_ciclo'|'2do_ciclo'|'N/A'
 * @param {string|number} [options.grado] '1'..'6'
 * @param {string} [options.area]     p. ej. 'Matemáticas'
 * @param {number} [options.limit=5]  Nº máximo de chunks (1..20)
 * @returns {Promise<{ query: string, count: number, chunks: Array<object> }>}
 */
async function searchMinerdChunks(query, options = {}) {
  const q = String(query || '').trim();
  if (!q) {
    throw new MinerdRetrievalError('El query no puede estar vacío', 'EMPTY_QUERY');
  }
  if (!supabase) {
    throw new MinerdRetrievalError(
      'Cliente Supabase no inicializado. Verifica SUPABASE_URL y SUPABASE_SERVICE_KEY.',
      'SUPABASE_UNAVAILABLE'
    );
  }

  const rawLimit = parseInt(options.limit, 10);
  const limit = Math.min(
    Math.max(Number.isFinite(rawLimit) && rawLimit > 0 ? rawLimit : DEFAULT_LIMIT, 1),
    MAX_LIMIT
  );

  const embedding = await embedQuery(q);
  const filter = buildFilter(options);

  const { data, error } = await supabase.rpc('match_chunks', {
    query_embedding: embedding,
    match_count: limit,
    filter,
  });

  if (error) {
    throw new MinerdRetrievalError(
      `Error en match_chunks: ${error.message}`,
      'RPC_ERROR',
      { cause: error.message, hint: error.hint || null }
    );
  }

  const chunks = (Array.isArray(data) ? data : [])
    .map(formatChunk)
    .sort((a, b) => (b.similarity ?? 0) - (a.similarity ?? 0));

  return {
    query: q,
    count: chunks.length,
    chunks,
  };
}

module.exports = {
  searchMinerdChunks,
  embedQuery,
  buildFilter,
  formatChunk,
  MinerdRetrievalError,
  EMBEDDING_MODEL,
  DEFAULT_LIMIT,
  MAX_LIMIT,
};

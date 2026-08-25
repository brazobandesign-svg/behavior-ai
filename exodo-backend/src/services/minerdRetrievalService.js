'use strict';

/**
 * ============================================================================
 * minerdRetrievalService.js — RAG Semántico + Reranking MINERD (DashScope)
 * ============================================================================
 *
 * Vectorización con `text-embedding-v4` (1536 dim, L2 normalized) y reranking
 * neuronal con `qwen3-rerank` de Alibaba Cloud DashScope.
 *
 * Incluye fallback determinista en memoria ante contingencias de red.
 */

const OpenAI = require('openai');
const supabase = require('../config/supabase');
const { ALIBABA_CONFIG } = require('../config/models');

const EMBEDDING_MODEL = ALIBABA_CONFIG.models.embeddingModel || 'text-embedding-v4';
const RERANK_MODEL = ALIBABA_CONFIG.models.rerankModel || 'qwen3-rerank';
const RERANK_API_URL = 'https://dashscope-intl.aliyuncs.com/api/v1/services/rerank/text-rerank/text-rerank';
const DEFAULT_LIMIT = 5;
const MAX_LIMIT = 20;
const TARGET_EMBEDDING_DIM = 1536;

class MinerdRetrievalError extends Error {
  constructor(message, code, details) {
    super(message);
    this.name = 'MinerdRetrievalError';
    this.code = code;
    this.details = details || null;
    if (Error.captureStackTrace) Error.captureStackTrace(this, this.constructor);
  }
}

let _alibabaClient = null;

function getApiKey() {
  return process.env.DASHSCOPE_API_KEY ||
         process.env.ALIBABA_API_KEY ||
         process.env.ALIBABA_FREE_KEY ||
         ALIBABA_CONFIG.apiKey;
}

function getAlibabaClient() {
  const apiKey = getApiKey();
  if (!apiKey) return null;

  if (!_alibabaClient) {
    const baseURL = process.env.ALIBABA_BASE_URL ||
                    ALIBABA_CONFIG.baseURL ||
                    'https://dashscope-intl.aliyuncs.com/compatible-mode/v1';
    _alibabaClient = new OpenAI({
      apiKey,
      baseURL,
      timeout: 30000,
    });
  }
  return _alibabaClient;
}

/**
 * Normaliza un vector a norma unitaria euclidiana (L2).
 */
function normalizeL2(vec) {
  let sumSq = 0;
  for (let i = 0; i < vec.length; i++) {
    sumSq += vec[i] * vec[i];
  }
  const norm = Math.sqrt(sumSq);
  if (norm === 0) {
    vec[0] = 1.0;
    return vec;
  }
  for (let i = 0; i < vec.length; i++) {
    vec[i] /= norm;
  }
  return vec;
}

/**
 * Fallback determinista en memoria (1536 dim) por hashing de n-gramas.
 */
function generateDeterministicVector(text, targetDim = TARGET_EMBEDDING_DIM) {
  const vec = new Array(targetDim).fill(0);
  const str = String(text || '').toLowerCase().trim();
  if (!str) {
    vec[0] = 1.0;
    return vec;
  }

  const tokens = str.split(/[\s,.;:!?()"-]+/).filter((t) => t.length > 1);
  if (tokens.length === 0) {
    vec[0] = 1.0;
    return vec;
  }

  for (let i = 0; i < tokens.length; i++) {
    const word = tokens[i];
    let hash = 0;
    for (let j = 0; j < word.length; j++) {
      hash = ((hash << 5) - hash) + word.charCodeAt(j);
      hash |= 0;
    }
    const idx = Math.abs(hash) % targetDim;
    vec[idx] += 1.0;

    if (i < tokens.length - 1) {
      const bigram = word + '_' + tokens[i + 1];
      let bHash = 0;
      for (let j = 0; j < bigram.length; j++) {
        bHash = ((bHash << 5) - bHash) + bigram.charCodeAt(j);
        bHash |= 0;
      }
      const bIdx = Math.abs(bHash) % targetDim;
      vec[bIdx] += 1.5;
    }
  }

  return normalizeL2(vec);
}

function fitDimension(vec, targetDim = TARGET_EMBEDDING_DIM) {
  if (!Array.isArray(vec) || vec.length === 0) {
    return generateDeterministicVector('', targetDim);
  }
  if (vec.length === targetDim) {
    return normalizeL2(vec);
  }
  const result = new Array(targetDim).fill(0);
  const copyLen = Math.min(vec.length, targetDim);
  for (let i = 0; i < copyLen; i++) {
    result[i] = vec[i];
  }
  return normalizeL2(result);
}

/**
 * Genera embedding usando DashScope `text-embedding-v4` (o fallback determinista).
 */
async function embedQuery(query) {
  const cleanQuery = String(query || '').replace(/\n+/g, ' ').trim();
  if (!cleanQuery) {
    return generateDeterministicVector('', TARGET_EMBEDDING_DIM);
  }

  const client = getAlibabaClient();
  if (client) {
    try {
      const response = await client.embeddings.create({
        model: EMBEDDING_MODEL,
        input: cleanQuery,
      });
      const embedding = response?.data?.[0]?.embedding;
      if (Array.isArray(embedding) && embedding.length > 0) {
        return fitDimension(embedding, TARGET_EMBEDDING_DIM);
      }
    } catch (err) {
      // Si text-embedding-v4 falla o no está en la región, intentar text-embedding-v3
      try {
        const response = await client.embeddings.create({
          model: 'text-embedding-v3',
          input: cleanQuery,
        });
        const embedding = response?.data?.[0]?.embedding;
        if (Array.isArray(embedding) && embedding.length > 0) {
          return fitDimension(embedding, TARGET_EMBEDDING_DIM);
        }
      } catch (fallbackErr) {
        console.warn(`[minerdRetrieval] Fallback a vector determinista: ${fallbackErr.message}`);
      }
    }
  }

  return generateDeterministicVector(cleanQuery, TARGET_EMBEDDING_DIM);
}

/**
 * Reranker Neuronal con DashScope `qwen3-rerank`.
 * Reordena candidatos recuperados antes de pasarlos al LLM.
 */
async function rerankChunks(query, chunks, topN = 5) {
  if (!Array.isArray(chunks) || chunks.length <= 1) {
    return chunks || [];
  }

  const apiKey = getApiKey();
  if (!apiKey) return chunks.slice(0, topN);

  try {
    const documents = chunks.map((c) => c.content || '');
    const res = await fetch(RERANK_API_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: RERANK_MODEL,
        input: {
          query,
          documents,
        },
        parameters: {
          top_n: topN,
          return_documents: false,
        },
      }),
    });

    if (!res.ok) {
      return chunks.slice(0, topN);
    }

    const data = await res.json();
    const results = data?.output?.results;
    if (Array.isArray(results) && results.length > 0) {
      const reranked = [];
      for (const item of results) {
        const originalIndex = item.index;
        if (chunks[originalIndex]) {
          const chunkCopy = { ...chunks[originalIndex] };
          chunkCopy.rerank_score = item.relevance_score;
          reranked.push(chunkCopy);
        }
      }
      return reranked;
    }
  } catch (err) {
    console.warn(`[minerdRetrieval] Rerank omitido (fallback orden semántico): ${err.message}`);
  }

  return chunks.slice(0, topN);
}

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
 * Recuperación semántica de chunks con reranker Qwen3.
 */
async function searchMinerdChunks(query, options = {}) {
  const q = String(query || '').trim();
  if (!q) {
    return { query: '', count: 0, chunks: [] };
  }
  if (!supabase) {
    return { query: q, count: 0, chunks: [] };
  }

  const rawLimit = parseInt(options.limit, 10);
  const limit = Math.min(
    Math.max(Number.isFinite(rawLimit) && rawLimit > 0 ? rawLimit : DEFAULT_LIMIT, 1),
    MAX_LIMIT
  );

  try {
    const embedding = await embedQuery(q);
    const filter = buildFilter(options);

    // Recuperar candidatos iniciales (2x para luego filtrar por reranker)
    const candidateLimit = Math.min(limit * 2, 20);

    const { data, error } = await supabase.rpc('match_chunks', {
      query_embedding: embedding,
      match_count: candidateLimit,
      filter,
    });

    if (error) {
      console.warn(`[minerdRetrieval] RPC match_chunks omitido: ${error.message}`);
      return { query: q, count: 0, chunks: [] };
    }

    const candidateChunks = (Array.isArray(data) ? data : [])
      .map(formatChunk)
      .sort((a, b) => (b.similarity ?? 0) - (a.similarity ?? 0));

    // Aplicar Reranker Qwen3
    const finalChunks = await rerankChunks(q, candidateChunks, limit);

    return {
      query: q,
      count: finalChunks.length,
      chunks: finalChunks,
    };
  } catch (err) {
    console.warn(`[minerdRetrieval] Error en searchMinerdChunks: ${err.message}`);
    return { query: q, count: 0, chunks: [] };
  }
}

module.exports = {
  searchMinerdChunks,
  embedQuery,
  rerankChunks,
  buildFilter,
  formatChunk,
  generateDeterministicVector,
  MinerdRetrievalError,
  EMBEDDING_MODEL,
  RERANK_MODEL,
  DEFAULT_LIMIT,
  MAX_LIMIT,
  TARGET_EMBEDDING_DIM,
};

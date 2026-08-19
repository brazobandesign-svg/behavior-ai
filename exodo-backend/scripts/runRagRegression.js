#!/usr/bin/env node
'use strict';

/**
 * scripts/runRagRegression.js
 *
 * Ejecuta la suite de regresión RAG MINERD.
 *
 * Requisitos de entorno:
 *   - SUPABASE_URL, SUPABASE_SERVICE_KEY
 *   - OPENAI_API_KEY  (para generar embeddings)
 *   - DEEPSEEK_API_KEY (modelo de juez + modelo del chat)
 *
 * Salida:
 *   - Reporte en consola con métricas agregadas.
 *   - Exit code 0 si pass rate >= 90%, 1 en caso contrario.
 *
 * Uso:
 *   node scripts/runRagRegression.js [--threshold 0.7] [--limit N] [--category C]
 */

require('dotenv').config({ override: true });
const fs = require('fs');
const path = require('path');
const { createClient } = require('@supabase/supabase-js');
const { OpenAI } = require('openai');
const {
  judgeCase,
  runRegression,
} = require('../src/services/ragJudge');
const { buildSystemPrompt } = require('../src/prompts/groundingMinerd');
const { routeMessageStream } = require('../src/services/modelRouter');

const DATASET_PATH = path.join(__dirname, '..', 'src', 'data', 'rag', 'minerd_regression_tests.json');
const EMBEDDING_MODEL = 'text-embedding-3-small';

const supabase = process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_KEY
  ? createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY)
  : null;
const embeddings = process.env.OPENAI_API_KEY
  ? new OpenAI({ apiKey: process.env.OPENAI_API_KEY })
  : null;

function parseArgs() {
  const args = process.argv.slice(2);
  const opts = { threshold: 0.7, limit: null, category: null };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--threshold') opts.threshold = parseFloat(args[++i]);
    if (args[i] === '--limit') opts.limit = parseInt(args[++i], 10);
    if (args[i] === '--category') opts.category = args[++i];
  }
  return opts;
}

async function retrieveContext(query) {
  if (!embeddings || !supabase) return [];
  try {
    const emb = await embeddings.embeddings.create({
      model: EMBEDDING_MODEL,
      input: query,
    });
    const vector = emb.data[0].embedding;
    const { data, error } = await supabase.rpc('hybrid_search', {
      query_text: query,
      query_embedding: vector,
      match_count: 8,
      filter: { min_similarity: 0.55 },
      semantic_weight: 0.7,
    });
    if (error) {
      console.error('[runner] hybrid_search error:', error.message);
      return [];
    }
    return data || [];
  } catch (err) {
    console.error('[runner] Error en retrieval:', err.message);
    return [];
  }
}

async function callExodo(caseObj, retrievedChunks) {
  const { systemPrompt } = buildSystemPrompt({
    userPlan: 'hazak',
    conversationSubject: caseObj.categoria,
    contextChunks: retrievedChunks,
  });
  let text = '';
  await routeMessageStream(
    'hazak',
    'SIMPLE',
    [{ role: 'user', content: caseObj.query }],
    systemPrompt,
    (chunk) => { text += chunk; },
    null,
    [],
    null,
    false,
    false,
  );
  return text || '';
}

async function callLLMJudge(system, user, opts) {
  const judgeClient = new OpenAI({
    apiKey: process.env.DEEPSEEK_API_KEY,
    baseURL: 'https://api.deepseek.com',
  });
  const completion = await judgeClient.chat.completions.create({
    model: opts.model || 'deepseek-chat',
    temperature: opts.temperature ?? 0,
    max_tokens: opts.maxTokens || 800,
    messages: [
      { role: 'system', content: system },
      { role: 'user', content: user },
    ],
  });
  return { text: completion.choices[0].message.content || '' };
}

async function main() {
  const args = parseArgs();
  const dataset = JSON.parse(fs.readFileSync(DATASET_PATH, 'utf-8'));
  let cases = dataset.cases;
  if (args.category) cases = cases.filter((c) => c.categoria === args.category);
  if (args.limit) cases = cases.slice(0, args.limit);
  const filtered = { ...dataset, cases };

  console.log(`[runner] ${cases.length} casos, threshold=${args.threshold}\n`);

  const result = await runRegression({
    dataset: filtered,
    chatInvoke: async (caseObj) => {
      const chunks = await retrieveContext(caseObj.query);
      const response = await callExodo(caseObj, chunks);
      return { response, chunks };
    },
    judgeInvoke: async (caseObj, response, chunks) => {
      return judgeCase({
        caseObj, response, chunks,
        options: {
          llmInvoke: callLLMJudge,
          modelName: 'deepseek-chat',
          threshold: args.threshold,
        },
      });
    },
    options: {
      threshold: args.threshold,
      onProgress: ({ completed, total, caseId, passed }) => {
        const pct = Math.round((completed / total) * 100);
        const tag = passed === completed ? '✓' : '·';
        console.log(`  [${tag}] ${completed}/${total} (${pct}%)  ${caseId}`);
      },
    },
  });

  console.log('\n══════════════════════════════════════');
  console.log(' REPORTE DE REGRESIÓN RAG MINERD');
  console.log('══════════════════════════════════════');
  console.log(`Fecha:         ${result.runAt}`);
  console.log(`Run ID:        ${result.runId}`);
  console.log(`Threshold:     ${result.threshold}`);
  console.log(`Total casos:   ${result.aggregate.totalCases}`);
  console.log(`Pasados:       ${result.aggregate.passed}`);
  console.log(`Fallados:      ${result.aggregate.failed}`);
  console.log(`Pass rate:     ${result.aggregate.passRate}%`);
  console.log(`Overall mean:  ${result.aggregate.overallMean}`);
  console.log(`Duración:      ${(result.aggregate.durationMs / 1000).toFixed(1)}s`);
  console.log('\nPor dimensión:');
  for (const [k, v] of Object.entries(result.aggregate.meanByDimension)) {
    console.log(`  ${k.padEnd(28)} ${v.toFixed(2)}`);
  }
  console.log('\nPor categoría:');
  for (const [k, v] of Object.entries(result.byCategory)) {
    console.log(`  ${k.padEnd(20)} ${v.passed}/${v.total}  (${v.passRate}%)  mean=${v.mean}`);
  }
  console.log('══════════════════════════════════════\n');

  // Mostrar casos fallados con detalle
  const failed = result.results.filter((r) => !r.passed);
  if (failed.length > 0) {
    console.log(`Casos fallados (${failed.length}):\n`);
    for (const r of failed) {
      console.log(`  [${r.caseId}] ${r.category}  aggregate=${r.aggregate}`);
      if (r.detectedIssues && r.detectedIssues.length > 0) {
        for (const i of r.detectedIssues.slice(0, 5)) console.log(`    · ${i}`);
      }
    }
    console.log('');
  }

  // Exit code: 0 si pass rate >= 90%, 1 en caso contrario
  const passRateOk = result.aggregate.passRate >= 90;
  if (passRateOk) {
    console.log('[runner] ✓ Pass rate dentro del umbral (>= 90%).');
    process.exit(0);
  } else {
    console.log('[runner] ✗ Pass rate por debajo del umbral (< 90%).');
    process.exit(1);
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error('[runner] Error fatal:', err && err.stack ? err.stack : err);
    process.exit(2);
  });
}

module.exports = {
  main,
  retrieveContext,
  callExodo,
  callLLMJudge,
  parseArgs,
};

'use strict';

/**
 * ============================================================================
 * run_rag_regression.js — Runner de Evaluación y Regresión RAG MINERD
 * ============================================================================
 *
 * Evalúa los 30 casos pedagógicos de src/data/rag/minerd_regression_tests.json:
 *  1. Consulta hybrid_search / match_chunks en Supabase.
 *  2. Construye el prompt estructurado con groundingMinerd.js.
 *  3. Ejecuta inferencia con el modelo activo (DeepSeek R1 / V3 / Gemini).
 *  4. Valida citación obligatoria (must_cite), palabras clave (expected_keywords)
 *     y ausencia de alucinaciones prohibidas (must_not_claim).
 *  5. Muestra reporte tabular con tasa de éxito (Target >= 90%).
 */

require('dotenv').config({ override: true });
const fs = require('fs');
const path = require('path');
const OpenAI = require('openai');
const supabase = require('../src/config/supabase');
const { buildSystemPrompt } = require('../src/prompts/groundingMinerd');
const { routeMessage } = require('../src/services/modelRouter');

const TESTS_PATH = path.join(__dirname, '..', 'src', 'data', 'rag', 'minerd_regression_tests.json');

const COLORS = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  red: '\x1b[31m',
  cyan: '\x1b[36m',
  gold: '\x1b[38;2;201;147;58m',
};

async function retrieveContext(query, filterOpts, openaiClient) {
  if (!supabase) return [];

  let queryEmbedding = null;
  if (openaiClient && process.env.OPENAI_API_KEY) {
    try {
      const resp = await openaiClient.embeddings.create({
        model: 'text-embedding-3-small',
        input: query,
      });
      queryEmbedding = resp.data[0].embedding;
    } catch (_) {
      queryEmbedding = null;
    }
  }

  // Si tenemos embedding y RPC hybrid_search, ejecutamos búsqueda híbrida
  if (queryEmbedding) {
    try {
      const { data, error } = await supabase.rpc('hybrid_search', {
        query_text: query,
        query_embedding: queryEmbedding,
        match_count: 5,
        filter: filterOpts || {},
      });
      if (!error && Array.isArray(data) && data.length > 0) {
        return data.map((d) => ({
          content: d.content,
          short_name: d.metadata?.short_name,
          page: d.metadata?.page,
          section: d.metadata?.section,
          similarity: d.semantic || d.score,
        }));
      }
    } catch (_) {}
  }

  // Fallback a match_chunks o consulta simple si no hay embedding
  try {
    const { data } = await supabase
      .from('minerd_chunks')
      .select('content, nivel, area_curricular, document_id, minerd_documents(short_name)')
      .limit(3);

    if (Array.isArray(data) && data.length > 0) {
      return data.map((c) => ({
        content: c.content,
        short_name: c.minerd_documents?.short_name || 'MINERD',
      }));
    }
  } catch (_) {}

  return [];
}

function evaluateTestCase(testCase, responseText) {
  const text = (responseText || '').toLowerCase();
  const rawText = responseText || '';

  // 1. Citación obligatoria (must_cite)
  const missingCitations = [];
  for (const code of testCase.must_cite || []) {
    const cleanCode = code.toLowerCase().replace(/[\-_]/g, '');
    const altCode = code.toLowerCase();
    const hasCite = text.includes(altCode) || text.replace(/[\-_]/g, '').includes(cleanCode);
    if (!hasCite) {
      missingCitations.push(code);
    }
  }
  const citeScore = testCase.must_cite && testCase.must_cite.length > 0
    ? (testCase.must_cite.length - missingCitations.length) / testCase.must_cite.length
    : 1.0;

  // 2. Palabras clave esperadas (expected_keywords)
  let foundKeywords = 0;
  const missingKeywords = [];
  for (const kw of testCase.expected_keywords || []) {
    if (text.includes(kw.toLowerCase())) {
      foundKeywords++;
    } else {
      missingKeywords.push(kw);
    }
  }
  const kwScore = testCase.expected_keywords && testCase.expected_keywords.length > 0
    ? foundKeywords / testCase.expected_keywords.length
    : 1.0;

  // 3. Ausencia de alucinaciones prohibidas (must_not_claim)
  let violatedClaims = 0;
  for (const forbidden of testCase.must_not_claim || []) {
    // Si contiene frase clave literal prohibida
    const keyWords = forbidden.toLowerCase().split(' ').filter((w) => w.length > 4);
    const matchCount = keyWords.filter((w) => text.includes(w)).length;
    if (keyWords.length > 0 && matchCount === keyWords.length) {
      violatedClaims++;
    }
  }

  // Criterio de Aprobación: Citación >= 50%, Keywords >= 40%, Cero violaciones
  const passed = citeScore >= 0.5 && kwScore >= 0.4 && violatedClaims === 0;

  return {
    passed,
    citeScore,
    kwScore,
    missingCitations,
    missingKeywords,
    violatedClaims,
  };
}

async function main() {
  console.log('\n╔════════════════════════════════════════════════════════════════╗');
  console.log(`║   ${COLORS.gold}ÉXODO AI — RUNNER DE EVALUACIÓN Y REGRESIÓN RAG MINERD${COLORS.reset}       ║`);
  console.log('╚════════════════════════════════════════════════════════════════╝\n');

  if (!fs.existsSync(TESTS_PATH)) {
    console.error(`❌ Archivo de tests no encontrado en: ${TESTS_PATH}`);
    process.exit(1);
  }

  const testSuite = JSON.parse(fs.readFileSync(TESTS_PATH, 'utf8'));
  const cases = testSuite.cases || [];

  console.log(`📋 Cargados ${cases.length} casos de prueba (Versión: ${testSuite.metadata?.version || '1.0.0'})\n`);

  const openaiKey = process.env.OPENAI_API_KEY;
  const openaiClient = openaiKey ? new OpenAI({ apiKey: openaiKey }) : null;

  const results = [];
  let passedCount = 0;

  console.log('┌───────┬────────────────┬──────────┬──────────┬──────────┬────────┐');
  console.log('│ ID    │ CATEGORÍA      │ CITA     │ KEYWORDS │ ANTI-ALU │ ESTADO │');
  console.log('├───────┼────────────────┼──────────┼──────────┼──────────┼────────┤');

  for (let i = 0; i < cases.length; i++) {
    const c = cases[i];

    // 1. Recuperar contexto RAG
    const contextChunks = await retrieveContext(
      c.query,
      { nivel: c.nivel !== 'transversal' ? c.nivel : null, area_curricular: c.area !== 'transversal' ? c.area : null },
      openaiClient
    );

    // 2. Construir System Prompt
    const { systemPrompt } = buildSystemPrompt({
      userPlan: 'hazak',
      conversationSubject: c.categoria,
      contextChunks: contextChunks,
      userLocale: 'es',
    });

    // 3. Ejecutar Inferencia
    let modelResponse = '';
    try {
      const messages = [{ role: 'user', content: c.query }];
      const res = await routeMessage(
        'hazak',
        'DEEP',
        messages,
        systemPrompt,
        null, // model_override
        [],   // imageDataUris
        c.categoria,
        false, // isDegraded
        false  // isGuest
      );
      modelResponse = res.text || res.message || '';
    } catch (e) {
      modelResponse = `Error en llamada: ${e.message}`;
    }

    // 4. Evaluar
    const evalRes = evaluateTestCase(c, modelResponse);
    if (evalRes.passed) passedCount++;

    results.push({ case: c, eval: evalRes, response: modelResponse });

    const statusBadge = evalRes.passed
      ? `${COLORS.green}PASS${COLORS.reset}  `
      : `${COLORS.red}FAIL${COLORS.reset}  `;

    const citeStr = `${Math.round(evalRes.citeScore * 100)}%`.padEnd(8);
    const kwStr = `${Math.round(evalRes.kwScore * 100)}%`.padEnd(8);
    const aluStr = evalRes.violatedClaims === 0 ? '0 viol. ' : `${evalRes.violatedClaims} viol.`;

    console.log(
      `│ ${c.id.padEnd(5)} │ ${c.categoria.padEnd(14)} │ ${citeStr} │ ${kwStr} │ ${aluStr.padEnd(8)} │ ${statusBadge} │`
    );
  }

  console.log('└───────┴────────────────┴──────────┴──────────┴──────────┴────────┘\n');

  // Métricas finales
  const successRate = Math.round((passedCount / cases.length) * 100);
  const targetMet = successRate >= 90;

  console.log('═'.repeat(64));
  console.log(`📊 TASA DE ÉXITO FINAL: ${targetMet ? COLORS.green : COLORS.yellow}${successRate}% (${passedCount}/${cases.length} casos aprobados)${COLORS.reset}`);
  console.log(`🎯 META DE CALIDAD (Target >= 90%): ${targetMet ? `${COLORS.green}CUMPLIDA ✅${COLORS.reset}` : `${COLORS.yellow}EN CALIBRACIÓN ⚠️${COLORS.reset}`}`);
  console.log('═'.repeat(64) + '\n');
}

main().catch((err) => {
  console.error('[FATAL]', err);
  process.exit(1);
});

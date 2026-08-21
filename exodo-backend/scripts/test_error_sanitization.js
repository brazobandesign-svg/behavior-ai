'use strict';

/**
 * ============================================================================
 * test_error_sanitization.js — Verificación autónoma del fix de seguridad
 * ============================================================================
 * Fix 2026-08-19: Error Sanitization & Vendor Leak Protection.
 *
 * Fuerza errores mock 413/429 de vendor (con org IDs, URLs y payload sizes
 * falsos en el mensaje crudo) y verifica:
 *   A) SSE solo emite el mensaje genérico de marca (error + done) — 0 fugas.
 *   B) Cadena completa de fallback agotada (429 en 3 proveedores) — 0 fugas.
 *   C) TPM-Guard: contexto >4k tokens NUNCA golpea Groq; va a Alibaba/DeepSeek.
 *   D) El error crudo del vendor queda logueado SOLO en consola del servidor.
 *
 * Ejecutar:  node scripts/test_error_sanitization.js
 */

const http = require('http');
const path = require('path');

process.chdir(path.join(__dirname, '..'));

// ---------------------------------------------------------------------------
// 1. Stubs de módulos (se inyectan en require.cache ANTES de cargar chat.js)
// ---------------------------------------------------------------------------

const memUsageMap = new Map();

function stubModule(relPath, exports) {
  const abs = require.resolve(relPath);
  require.cache[abs] = { id: abs, filename: abs, loaded: true, exports };
}

// --- Middleware ---
stubModule('../src/middleware/auth', (req, res, next) => {
  const plan = req.headers['x-test-plan'] || 'guest';
  const isGuest = plan === 'guest';
  req.user = {
    userId: isGuest ? null : 'test-user-1',
    plan,
    anonymous: isGuest,
    isGuest,
    isDegraded: false,
  };
  next();
});

stubModule('../src/middleware/planGuard', {
  planGuard: (req, res, next) => {
    req.user.isDegraded = false;
    req.usage = {
      id: null,
      isGuest: !!req.user.isGuest,
      dailyTokensUsed: 0,
      dailyTokensLimit: 6000,
      monthlyVisionUsed: 0,
      monthlyVisionLimit: 3,
      isDegraded: false,
    };
    next();
  },
  getMemUsageMap: () => memUsageMap,
});

// --- Servicios de soporte ---
stubModule('../src/services/historyManager', {
  getHistory: async () => [],
  saveMessage: async () => {},
});

stubModule('../src/services/intentClassifier', {
  classifyIntent: async () => 'SIMPLE',
});

stubModule('../src/services/minerdRetrievalService', {
  searchMinerdChunks: async () => ({ chunks: [] }),
});

stubModule('../src/services/documentExtractor', {
  extractText: async () => ({ ok: false, text: '' }),
});

stubModule('../src/prompts/groundingMinerd', {
  buildSystemPrompt: () => ({ systemPrompt: 'Eres Éxodo, asistente de prueba.' }),
});

stubModule('../src/config/supabase', null);

// --- Providers mock con errores de vendor realistas (datos falsos) ---
const VENDOR_LEAK_413 =
  'Error: 413 {"error":{"message":"Please reduce the length of the messages or completion. ' +
  'The maximum context length is 8192 tokens. Organization: org_LeAkZx7QpXvT2mNwR4bQ. ' +
  'Visit https://console.groq.com/docs/rate-limits for details. ' +
  'Request payload size: 131072 bytes exceeded the limit."}, ' +
  '"request_id":"req_groq_9f8e7d6c5b4a"}';

const VENDOR_LEAK_429 =
  'Error: 429 {"error":{"message":"Rate limit reached for model in organization ' +
  'org_LeAkZx7QpXvT2mNwR4bQ on tokens per minute (TPM): Limit 8000, Used 7950, Requested 2500. ' +
  'Please try again in 14.1s. Visit https://console.groq.com/docs/rate-limits."}}';

const providerState = {
  groq: { calls: 0, error: null },
  deepseek: { calls: 0, error: null, succeed: false },
  gemini: { calls: 0, error: null },
};

function resetProviders() {
  providerState.groq.calls = 0;
  providerState.groq.error = null;
  providerState.deepseek.calls = 0;
  providerState.deepseek.error = null;
  providerState.deepseek.succeed = false;
  providerState.gemini.calls = 0;
  providerState.gemini.error = null;
}

function makeVendorError(state) {
  const e = new Error(state.error.message);
  e.status = state.error.status;
  return e;
}

stubModule('../src/services/providers/groqProvider', {
  call: async () => {
    providerState.groq.calls++;
    if (providerState.groq.error) throw makeVendorError(providerState.groq);
    return { text: 'groq-ok', tokensInput: 1, tokensOutput: 1, model: 'groq', provider: 'groq', isEco: true };
  },
  callStream: async (modelId, messages, systemPrompt, onChunk) => {
    providerState.groq.calls++;
    if (providerState.groq.error) throw makeVendorError(providerState.groq);
    onChunk('groq-ok');
    return { text: 'groq-ok', tokensInput: 0, tokensOutput: 0, model: modelId, provider: 'groq', isEco: true };
  },
});

stubModule('../src/services/providers/deepseekProvider', {
  call: async () => {
    providerState.deepseek.calls++;
    if (providerState.deepseek.error) throw makeVendorError(providerState.deepseek);
    return { text: 'alibaba-ok', tokensInput: 1, tokensOutput: 1, model: 'qwen', provider: 'alibaba' };
  },
  callStream: async (modelId, messages, systemPrompt, onChunk) => {
    providerState.deepseek.calls++;
    if (providerState.deepseek.error) throw makeVendorError(providerState.deepseek);
    onChunk('OK ');
    onChunk('desde Alibaba.');
    return { text: 'OK desde Alibaba.', tokensInput: 0, tokensOutput: 0, model: modelId, provider: 'alibaba' };
  },
});

stubModule('../src/services/providers/geminiProvider', {
  call: async () => {
    providerState.gemini.calls++;
    if (providerState.gemini.error) throw makeVendorError(providerState.gemini);
    return { text: 'gemini-ok', tokensInput: 1, tokensOutput: 1, model: 'gemini', provider: 'gemini' };
  },
  callStream: async (modelId, messages, systemPrompt, onChunk) => {
    providerState.gemini.calls++;
    if (providerState.gemini.error) throw makeVendorError(providerState.gemini);
    onChunk('gemini-ok');
    return { text: 'gemini-ok', tokensInput: 0, tokensOutput: 0, model: modelId, provider: 'gemini' };
  },
});

// ---------------------------------------------------------------------------
// 2. Cargar módulos REALES bajo prueba
// ---------------------------------------------------------------------------

const express = require('express');
const chatRouter = require('../src/routes/chat');
const { USER_FACING_ERROR_MESSAGE, containsVendorLeak } = require('../src/services/errorSanitizer');

// ---------------------------------------------------------------------------
// 3. Captura de consola del servidor (verificar log interno)
// ---------------------------------------------------------------------------

const capturedConsole = [];
const origConsoleError = console.error;
const origConsoleWarn = console.warn;
console.error = (...args) => {
  capturedConsole.push(args.map((a) => (typeof a === 'string' ? a : JSON.stringify(a))).join(' '));
  origConsoleError(...args);
};
console.warn = (...args) => {
  capturedConsole.push(args.map((a) => (typeof a === 'string' ? a : JSON.stringify(a))).join(' '));
  origConsoleWarn(...args);
};

// ---------------------------------------------------------------------------
// 4. Harness HTTP
// ---------------------------------------------------------------------------

function parseSse(body) {
  return body
    .split('\n\n')
    .map((b) => b.trim())
    .filter((b) => b.startsWith('data: '))
    .map((b) => {
      try {
        return JSON.parse(b.slice(6));
      } catch (_) {
        return { __raw: b };
      }
    });
}

function postChat(port, body, plan) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const req = http.request(
      {
        host: '127.0.0.1',
        port,
        path: '/api/chat',
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(data),
          Authorization: 'Bearer test-jwt',
          'x-test-plan': plan,
        },
      },
      (res) => {
        let buf = '';
        res.on('data', (c) => (buf += c));
        res.on('end', () => resolve({ status: res.statusCode, body: buf }));
      }
    );
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

let failures = 0;
function assert(cond, label) {
  if (cond) {
    origConsoleError; // noop ref
    console.log(`  ✅ ${label}`);
  } else {
    failures++;
    console.log(`  ❌ FALLO: ${label}`);
  }
}

const LEAK_MARKERS = ['org_LeAkZx7QpXvT2mNwR4bQ', 'console.groq.com', '131072', 'Rate limit reached', 'Please reduce the length'];

function assertNoLeaks(sseBody, label) {
  const clean = LEAK_MARKERS.every((m) => !sseBody.includes(m)) && !containsVendorLeak(sseBody);
  assert(clean, `${label}: SSE no filtra datos del vendor (org ID / URL / payload)`);
}

// ---------------------------------------------------------------------------
// 5. Escenarios de prueba
// ---------------------------------------------------------------------------

async function run() {
  const app = express();
  app.use(express.json({ limit: '20mb' }));
  app.use('/api/chat', chatRouter);

  const server = await new Promise((resolve) => {
    const s = app.listen(0, '127.0.0.1', () => resolve(s));
  });
  const port = server.address().port;

  // ─────────────────────────────────────────────────────────────────────────
  // TEST A — Groq 413 (réplica exacta del incidente): guest → Groq primario
  // ─────────────────────────────────────────────────────────────────────────
  console.log('\n[TEST A] Groq HTTP 413 / TPM excedido — guest, Groq primario');
  resetProviders();
  providerState.groq.error = { status: 413, message: VENDOR_LEAK_413 };
  capturedConsole.length = 0;

  const resA = await postChat(port, { message: 'Hola, cuéntame una historia corta sobre el espacio', history: [] }, 'guest');
  const eventsA = parseSse(resA.body);
  const errA = eventsA.find((e) => e.type === 'error');
  const doneA = eventsA.find((e) => e.type === 'done');

  assert(resA.status === 200, 'A: respuesta HTTP 200 (SSE abierto)');
  assert(!!errA, 'A: evento "error" presente');
  assert(errA && errA.content === USER_FACING_ERROR_MESSAGE, 'A: contenido del error es el mensaje genérico de marca');
  assert(!!doneA, 'A: evento "done" presente (cierre limpio para el cliente móvil)');
  assertNoLeaks(resA.body, 'A');
  assert(
    capturedConsole.some((l) => l.includes('[INTERNAL_GATEWAY_ERROR]') && l.includes('org_LeAkZx7QpXvT2mNwR4bQ')),
    'A: error crudo del vendor logueado SOLO en consola interna ([INTERNAL_GATEWAY_ERROR])'
  );

  // ─────────────────────────────────────────────────────────────────────────
  // TEST B — 429 en cascada: primario + todos los fallbacks agotados
  // ─────────────────────────────────────────────────────────────────────────
  console.log('\n[TEST B] HTTP 429 en cascada — free, cadena completa de fallbacks');
  resetProviders();
  providerState.deepseek.error = { status: 429, message: VENDOR_LEAK_429 };
  providerState.gemini.error = { status: 429, message: VENDOR_LEAK_429 };
  providerState.groq.error = { status: 429, message: VENDOR_LEAK_429 };
  capturedConsole.length = 0;

  const resB = await postChat(port, { message: 'Explícame brevemente la fotosíntesis', history: [] }, 'free');
  const eventsB = parseSse(resB.body);
  const errB = eventsB.find((e) => e.type === 'error');
  const doneB = eventsB.find((e) => e.type === 'done');

  assert(providerState.deepseek.calls >= 1 && providerState.gemini.calls >= 1 && providerState.groq.calls >= 1,
    'B: se intentó primario + fallbacks (deepseek→gemini→groq)');
  assert(!!errB && errB.content === USER_FACING_ERROR_MESSAGE, 'B: error sanitizado de marca tras agotar fallbacks');
  assert(!!doneB, 'B: evento "done" presente');
  assertNoLeaks(resB.body, 'B');
  assert(
    capturedConsole.filter((l) => l.includes('[INTERNAL_GATEWAY_ERROR]')).length >= 3,
    'B: cada fallo de proveedor quedó logueado internamente (≥3 entradas)'
  );

  // ─────────────────────────────────────────────────────────────────────────
  // TEST C — TPM-Guard: contexto >4k tokens desviado de Groq hacia Alibaba
  // ─────────────────────────────────────────────────────────────────────────
  console.log('\n[TEST C] TPM-Guard — contexto largo (~5k tokens) nunca golpea Groq');
  resetProviders();
  providerState.deepseek.succeed = true;
  capturedConsole.length = 0;

  const longSentence = 'La física cuántica estudia las partículas subatómicas y sus interacciones fundamentales. ';
  const longMessage = longSentence.repeat(230); // ~21k chars ≈ 5.3k tokens
  const resC = await postChat(port, { message: longMessage, history: [] }, 'guest');
  const eventsC = parseSse(resC.body);
  const doneC = eventsC.find((e) => e.type === 'done');
  const chunksC = eventsC.filter((e) => e.type === 'chunk').map((e) => e.content).join('');

  assert(providerState.groq.calls === 0, 'C: Groq NO fue llamado (protección TPM activa)');
  assert(providerState.deepseek.calls === 1, 'C: Alibaba/DeepSeek usado como motor primario desviado');
  assert(chunksC.includes('OK desde Alibaba.'), 'C: stream completado con respuesta del motor desviado');
  assert(!!doneC && !doneC.error, 'C: evento "done" limpio');
  assert(
    capturedConsole.some((l) => l.includes('[ModelRouter TPM-Guard]')),
    'C: desvío TPM registrado en consola interna'
  );

  // ─────────────────────────────────────────────────────────────────────────
  // TEST D — Unitario: routeMessageStream devuelve shape sanitizado
  // ─────────────────────────────────────────────────────────────────────────
  console.log('\n[TEST D] Unitario — routeMessageStream ante 413 directo');
  resetProviders();
  providerState.groq.error = { status: 413, message: VENDOR_LEAK_413 };

  const { routeMessageStream } = require('../src/services/modelRouter');
  const resultD = await routeMessageStream(
    'guest', 'SIMPLE',
    [{ role: 'user', content: 'prueba unitaria directa' }],
    'system',
    () => {},
    null, [], undefined, false, true, null
  );

  assert(resultD.error === true, 'D: resultado marca error: true');
  assert(resultD.message === USER_FACING_ERROR_MESSAGE, 'D: mensaje del resultado es el genérico de marca');
  assert(!LEAK_MARKERS.some((m) => JSON.stringify(resultD).includes(m)), 'D: resultado libre de datos del vendor');

  server.close();
  console.log('\n══════════════════════════════════════════════════');
  if (failures === 0) {
    console.log('✅ TODAS LAS PRUEBAS PASARON — 0 fugas de vendor en SSE, sanitización verificada.');
  } else {
    console.log(`❌ ${failures} prueba(s) fallaron.`);
  }
  console.log('══════════════════════════════════════════════════');
  process.exit(failures === 0 ? 0 : 1);
}

// Guardarraíl global: el test no puede colgar indefinidamente.
setTimeout(() => {
  console.error('❌ TIMEOUT: el harness excedió 30s.');
  process.exit(1);
}, 30000).unref();

run().catch((err) => {
  origConsoleError('❌ Error fatal del harness:', err);
  process.exit(1);
});

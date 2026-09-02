'use strict';

/**
 * test/backend.test.js — Suite de tests del backend Éxodo (H5).
 * Runner nativo de Node.js (node:test + node:assert), sin dependencias extra.
 *
 * Uso: npm test   (=> node --test test/*.test.js)
 */

require('dotenv').config({ override: true });

const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const { spawn } = require('node:child_process');
const path = require('node:path');

// ---------------------------------------------------------------------------
// 1. GET /health — servidor real en puerto efímero
// ---------------------------------------------------------------------------

function fetchHealth(port, timeoutMs = 30000, child = null) {
  const deadline = Date.now() + timeoutMs;
  return new Promise((resolve, reject) => {
    const attempt = () => {
      const req = http.get({ host: '127.0.0.1', port, path: '/health', timeout: 2000 }, (res) => {
        let body = '';
        res.on('data', (c) => { body += c; });
        res.on('end', () => resolve({ statusCode: res.statusCode, body }));
      });
      req.on('error', () => {
        if (Date.now() > deadline) {
          return reject(new Error(`El servidor no respondió a tiempo. Boot: ${(child && child.bootLog) || '(sin salida)'}`));
        }
        setTimeout(attempt, 400);
      });
      req.on('timeout', () => {
        req.destroy();
        if (Date.now() > deadline) {
          return reject(new Error(`Timeout esperando /health. Boot: ${(child && child.bootLog) || '(sin salida)'}`));
        }
        setTimeout(attempt, 400);
      });
    };
    attempt();
  });
}

test('GET /health responde 200 con status "ok" (servidor real)', async (t) => {
  const child = spawn(process.execPath, ['src/index.js'], {
    cwd: path.join(__dirname, '..'),
    // src/index.js carga dotenv con override:true sobre .env (PORT=3000);
    // DOTENV_CONFIG_PATH redirige esa carga a este archivo mínimo para que
    // el servidor escuche en un puerto fijo de pruebas.
    env: {
      ...process.env,
      DOTENV_CONFIG_PATH: path.join(__dirname, '.env.health'),
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  child.bootLog = '';
  child.stdout.on('data', (d) => { child.bootLog += d; });
  child.stderr.on('data', (d) => { child.bootLog += d; });
  t.after(() => {
    try { child.kill(); } catch (_) { /* ya terminó */ }
  });

  const res = await fetchHealth(4317, 30000, child);
  assert.strictEqual(res.statusCode, 200, 'El health check debe responder 200');
  const parsed = JSON.parse(res.body);
  assert.strictEqual(parsed.status, 'ok');
  // Nota (auditoría A4): /health es superficie mínima por decisión — el
  // uptime NO se expone deliberadamente; el 200 + ok es el contrato vivo.
});

// ---------------------------------------------------------------------------
// 2. planGuard — guests y degradación por cuota (ruta de memoria, sin DB)
// ---------------------------------------------------------------------------

const { planGuard, getMemUsageMap } = require('../src/middleware/planGuard');
const { PLAN_CONFIG } = require('../src/config/models');

function fakeRes() {
  return {
    statusCode: null,
    body: null,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; },
  };
}

function astTodayKey() {
  // Misma fórmula de fecha AST que planGuard.getAstDates().
  return new Date(Date.now() - 4 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

test('planGuard: guest pasa sin DB, marcado como invitado y sin saldo', async () => {
  const req = { user: { userId: null, plan: 'guest', isGuest: true } };
  const res = fakeRes();
  let nextCalled = false;
  await planGuard(req, res, () => { nextCalled = true; });
  assert.ok(nextCalled, 'guest debe continuar la cadena');
  assert.strictEqual(res.statusCode, null, 'guest no debe recibir 429/403');
  assert.strictEqual(req.usage.isGuest, true);
  assert.strictEqual(req.usage.dailyTokensLimit, 0);
});

test('planGuard: free con cuota agotada queda degradado (modo eco)', async () => {
  const userId = 'test-user-free-agotado';
  const today = astTodayKey();
  getMemUsageMap().set(userId, {
    ts: Date.now(),
    id: null,
    dailyTokensUsed: PLAN_CONFIG.free.dailyTokensLimit, // >= límite (6000)
    monthlyVisionUsed: 0,
    lastTokenReset: today,
    lastVisionReset: today.slice(0, 7),
    lastImageReset: today,
  });
  try {
    const req = { user: { userId, plan: 'genesis', isGuest: false } };
    const res = fakeRes();
    let nextCalled = false;
    await planGuard(req, res, () => { nextCalled = true; });
    assert.ok(nextCalled, 'soft cap: la cadena continúa sin 429');
    assert.strictEqual(req.user.isDegraded, true, 'cuota agotada => degradado/eco');
    assert.strictEqual(req.usage.dailyTokensLimit, PLAN_CONFIG.free.dailyTokensLimit);
  } finally {
    getMemUsageMap().delete(userId);
  }
});

test('planGuard: pro (hazak) con consumo bajo no se degrada y recibe su límite', async () => {
  const userId = 'test-user-pro-fresco';
  const today = astTodayKey();
  getMemUsageMap().set(userId, {
    ts: Date.now(),
    id: null,
    dailyTokensUsed: 100,
    monthlyVisionUsed: 0,
    lastTokenReset: today,
    lastVisionReset: today.slice(0, 7),
    lastImageReset: today,
  });
  try {
    const req = { user: { userId, plan: 'hazak', isGuest: false } };
    const res = fakeRes();
    let nextCalled = false;
    await planGuard(req, res, () => { nextCalled = true; });
    assert.ok(nextCalled);
    assert.strictEqual(req.user.isDegraded, false, 'pro nunca se degrada por cuota');
    assert.strictEqual(req.usage.dailyTokensLimit, PLAN_CONFIG.pro.dailyTokensLimit);
    assert.strictEqual(req.usage.dailyTokensLimit, 50000);
  } finally {
    getMemUsageMap().delete(userId);
  }
});

// ---------------------------------------------------------------------------
// 3. stripCodeBlocksForSources / extractSourcesFromText — privacidad de Sources
// ---------------------------------------------------------------------------

const chatRoutes = require('../src/routes/chat');
const stripCodeBlocksForSources = chatRoutes.stripCodeBlocksForSources;
const extractSourcesFromText = chatRoutes.extractSourcesFromText;

test('stripCodeBlocksForSources: elimina el contenido de fences ``` y ~~~', () => {
  const text = [
    'Explicación con [NASA](https://www.nasa.gov) de contexto.',
    '',
    '```html',
    '<svg xmlns="http://www.w3.org/2000/svg"></svg>',
    '<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>',
    '```',
  ].join('\n');
  const prose = stripCodeBlocksForSources(text);
  assert.ok(!prose.includes('w3.org'), 'el xmlns del código no debe sobrevivir');
  assert.ok(!prose.includes('jsdelivr'), 'el CDN del código no debe sobrevivir');
  assert.ok(prose.includes('nasa.gov'), 'la prosa se conserva');
});

test('extractSourcesFromText: ignora URLs del código y conserva fuentes legítimas', () => {
  const response = [
    'Aquí tienes el gráfico solicitado.',
    '',
    '```html',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 240"></svg>',
    '```',
    '',
    'La caída se acelera. Fuente: [NASA](https://www.nasa.gov)',
  ].join('\n');
  const sources = extractSourcesFromText(response, [], [], false);
  assert.ok(!sources.some((s) => /w3\.org/i.test(s.url)), 'el xmlns w3.org NO es una fuente');
  assert.ok(sources.some((s) => /nasa\.gov/i.test(s.url)), 'la fuente legítima se conserva');
});

test('extractSourcesFromText: lista vacía cuando la respuesta es solo código', () => {
  const sources = extractSourcesFromText(
    '```html\n<svg xmlns="http://www.w3.org/2000/svg"/>\n```',
    [], [], false,
  );
  assert.strictEqual(sources.length, 0, 'sin prosa => sin Sources (el chip no aparece)');
});

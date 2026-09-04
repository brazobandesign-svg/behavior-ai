'use strict';

const test = require('node:test');
const assert = require('node:assert');

const { getExecutionChain, getEffectiveModel } = require('../src/services/modelRouter');
const { ALIBABA_CONFIG, PLAN_CONFIG } = require('../src/config/models');
const { needsWebSearch, enrichWithReader } = require('../src/services/webSearch');
const { buildSystemPrompt } = require('../src/prompts/groundingMinerd');
const { getLocalDateKey } = require('../src/utils/timezone');
const { planGuard } = require('../src/middleware/planGuard');

test('modelRouter: guest siempre se enruta al modo eco ($0.00)', () => {
  const chain = getExecutionChain('guest', 'SIMPLE', null, [], 'simple', true, false);
  assert.strictEqual(chain[0], ALIBABA_CONFIG.models.fastPrimary);

  const effective = getEffectiveModel('guest', 'SIMPLE', null, [], 'simple', true, false);
  assert.strictEqual(effective.isEco, true);
});

test('modelRouter: usuario degradado (cuota agotada) se enruta al modo eco', () => {
  // Free degradado
  const chainFreeDegraded = getExecutionChain('genesis', 'RAZONAMIENTO', null, [], 'reasoning', false, true);
  assert.strictEqual(chainFreeDegraded[0], ALIBABA_CONFIG.models.fastPrimary);

  // Pro degradado
  const chainProDegraded = getExecutionChain('hazak', 'CODE', null, [], 'code', false, true);
  assert.strictEqual(chainProDegraded[0], ALIBABA_CONFIG.models.fastPrimary);

  const effective = getEffectiveModel('genesis', 'SIMPLE', null, [], 'simple', false, true);
  assert.strictEqual(effective.isEco, true);
});

test('modelRouter: visión ilimitada para todos los tiers', () => {
  const fakeImageUri = ['data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='];

  // Guest visión
  const guestVision = getExecutionChain('guest', 'VISION', null, fakeImageUri, 'simple', true, false);
  assert.strictEqual(guestVision[0], ALIBABA_CONFIG.models.visionEco || 'qwen3-vl-plus');

  // Pro visión
  const proVision = getExecutionChain('hazak', 'VISION', null, fakeImageUri, 'simple', false, false);
  assert.strictEqual(proVision[0], ALIBABA_CONFIG.models.visionPrimary);
});

test('planGuard: visión ilimitada en el guardia de planes', async () => {
  const reqGuest = { user: { userId: null, plan: 'guest', isGuest: true } };
  await planGuard(reqGuest, {}, () => {});
  assert.strictEqual(reqGuest.usage.monthlyVisionLimit, Infinity);

  assert.strictEqual(PLAN_CONFIG.free.monthlyVisionLimit, Infinity);
  assert.strictEqual(PLAN_CONFIG.pro.monthlyVisionLimit, Infinity);
});

test('webSearch: tope estricto de 3 búsquedas diarias para Guest e Incógnito', () => {
  const testIp = `192.168.10.${Math.floor(Math.random() * 899 + 100)}`;
  const tz = 'America/Santo_Domingo';

  // Tres primeras búsquedas permitidas
  for (let i = 0; i < 3; i++) {
    const gate = needsWebSearch({
      message: 'busca en la web las últimas noticias de hoy',
      intent: 'INFORMACION',
      hasImages: false,
      isGuest: true,
      clientIp: testIp,
      timezone: tz,
    });
    assert.strictEqual(gate.search, true);
    assert.strictEqual(gate.quotaExceeded, undefined);
  }

  // La 4ta búsqueda debe ser bloqueada por cuota diaria excedida
  const { _guestSearchUsage } = require('../src/services/webSearch');
  const todayKey = getLocalDateKey(tz);
  _guestSearchUsage.set(testIp, { date: todayKey, count: 3 });

  const blockedGate = needsWebSearch({
    message: 'busca en la web las últimas noticias de hoy',
    intent: 'INFORMACION',
    hasImages: false,
    isGuest: true,
    clientIp: testIp,
    timezone: tz,
  });
  assert.strictEqual(blockedGate.search, false);
  assert.strictEqual(blockedGate.quotaExceeded, true);
});

test('webSearch: enrichWithReader omite Jina reader para Guest e Incógnito', async () => {
  const sampleResults = [
    { title: 'T1', url: 'https://example.com/1', snippet: 'Corto' },
    { title: 'T2', url: 'https://example.com/2', snippet: 'Corto' },
  ];

  const guestEnriched = await enrichWithReader(sampleResults, { isGuest: true });
  assert.strictEqual(guestEnriched[0].snippet, 'Corto');

  const incognitoEnriched = await enrichWithReader(sampleResults, { isIncognito: true });
  assert.strictEqual(incognitoEnriched[0].snippet, 'Corto');
});

test('groundingMinerd: artefactos interactivos limitados para sesiones anónimas', () => {
  const promptAnonymous = buildSystemPrompt({
    userPlan: 'genesis',
    isAnonymous: true,
    lite: false,
  });
  assert.ok(
    promptAnonymous.systemPrompt.includes('Para previsualizar artefactos y ejecutar aplicaciones interactivas, inicia sesión en tu cuenta.'),
    'Debe advertir amigablemente iniciar sesión para interactividad'
  );

  const promptLiteAnonymous = buildSystemPrompt({
    userPlan: 'genesis',
    isAnonymous: true,
    lite: true,
  });
  assert.ok(
    promptLiteAnonymous.systemPrompt.includes('Para previsualizar artefactos y ejecutar aplicaciones interactivas, inicia sesión en tu cuenta.'),
    'En modo lite también debe incluir la advertencia para anónimos'
  );

  const promptRegistered = buildSystemPrompt({
    userPlan: 'hazak',
    isAnonymous: false,
    lite: false,
  });
  assert.ok(
    !promptRegistered.systemPrompt.includes('LIMITACIÓN DE ARTEFACTOS INTERACTIVOS'),
    'Usuarios registrados no deben tener la limitación de artefactos'
  );
});

test('timezone: getLocalDateKey genera fechas inviolables por huso horario', () => {
  const now = Date.now();
  const dateDO = getLocalDateKey('America/Santo_Domingo', now);
  assert.match(dateDO, /^\d{4}-\d{2}-\d{2}$/);

  const dateFallback = getLocalDateKey('ZONA_INVALIDA', now);
  assert.match(dateFallback, /^\d{4}-\d{2}-\d{2}$/);
});

test('errorHandler: captura LIMIT_FILE_SIZE y responde con mensaje exacto', () => {
  const errorHandler = require('../src/middleware/errorHandler');
  const err = new Error('File too large');
  err.code = 'LIMIT_FILE_SIZE';

  let statusSent = null;
  let jsonSent = null;
  const res = {
    status(s) { statusSent = s; return this; },
    json(j) { jsonSent = j; return this; },
  };

  errorHandler(err, { method: 'POST', path: '/api/chat' }, res, () => {});
  assert.strictEqual(statusSent, 400);
  assert.strictEqual(jsonSent.error, 'El adjunto supera el límite permitido (15MB).');
});

test('cascadeRouter: arquitectura modular de cascada lista para el futuro', () => {
  const { getCascadeChain } = require('../src/services/cascadeRouter');

  // Guest -> Groq Eco directo
  const guestChain = getCascadeChain('guest', 'SIMPLE', null, [], 'simple', true, false);
  assert.strictEqual(guestChain[0].provider, 'groq');
  assert.strictEqual(guestChain[0].isEco, true);

  // Free degradado -> Groq Eco directo
  const freeDegraded = getCascadeChain('genesis', 'SIMPLE', null, [], 'simple', false, true);
  assert.strictEqual(freeDegraded[0].provider, 'groq');
  assert.strictEqual(freeDegraded[0].isEco, true);

  // Pro -> OpenAI -> Google -> DeepSeek -> Groq
  const proChain = getCascadeChain('hazak', 'SIMPLE', null, [], 'simple', false, false);
  assert.strictEqual(proChain[0].provider, 'openai');
  assert.strictEqual(proChain[1].provider, 'gemini');
  assert.strictEqual(proChain[2].provider, 'deepseek');
  assert.strictEqual(proChain[3].provider, 'groq');

  // Free -> Google -> DeepSeek -> Groq
  const freeChain = getCascadeChain('genesis', 'SIMPLE', null, [], 'simple', false, false);
  assert.strictEqual(freeChain[0].provider, 'gemini');
  assert.strictEqual(freeChain[1].provider, 'deepseek');
  assert.strictEqual(freeChain[2].provider, 'groq');
});


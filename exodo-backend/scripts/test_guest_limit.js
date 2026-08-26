'use strict';
/**
 * ============================================================================
 * scripts/test_guest_limit.js — Verificación re-ejecutable del middleware C9
 * ============================================================================
 * Prueba la lógica pura del limitador diario de invitados sin servidor:
 *   1. Bloquea exactamente en el tope configurado (GUEST_DAILY_MESSAGES)
 *   2. Usuarios registrados pasan siempre
 *   3. IPs distintas llevan contadores independientes
 *   4. El reset por cambio de día funciona
 *
 * Uso: node scripts/test_guest_limit.js
 */

const assert = (cond, msg) => {
  if (!cond) { failures++; console.error(`  ❌ ${msg}`); }
  else console.log(`  ✅ ${msg}`);
};

// Requiere el módulo ANTES de tocar env (DAILY_LIMIT se lee al cargar).
const { guestLimit } = require('../src/middleware/guestLimit');
const REAL_LIMIT = require.cache[require.resolve('../src/middleware/guestLimit')].exports.DAILY_LIMIT;

let failures = 0;

function makeRes() {
  return {
    statusCode: null,
    body: null,
    status(c) { this.statusCode = c; return this; },
    json(b) { this.body = b; },
  };
}

console.log(`\n[TEST 1] Tope real del middleware: GUEST_DAILY_MESSAGES=${REAL_LIMIT}`);
{
  const ip = '10.0.0.1';
  let blockedAt = -1;
  for (let i = 1; i <= REAL_LIMIT + 2; i++) {
    const req = { user: { isGuest: true }, ip };
    const res = makeRes();
    let nextCalled = false;
    guestLimit(req, res, () => { nextCalled = true; });
    if (!nextCalled && blockedAt === -1) blockedAt = i;
    if (!nextCalled && res.statusCode !== 429) failures++;
  }
  assert(blockedAt === REAL_LIMIT + 1, `bloquea en la petición #${blockedAt} (esperado #${REAL_LIMIT + 1})`);
}

console.log('\n[TEST 2] Usuario registrado jamás bloqueado tras agotar guest');
{
  let allNext = true;
  for (let i = 0; i < REAL_LIMIT + 5; i++) {
    const res = makeRes();
    let nextCalled = false;
    guestLimit({ user: { isGuest: false, userId: 'u1' }, ip: '10.0.0.2' }, res, () => { nextCalled = true; });
    if (!nextCalled) allNext = false;
  }
  assert(allNext, 'registrado pasa en todas las iteraciones');
}

console.log('\n[TEST 3] Contadores independientes por IP');
{
  const resA = makeRes(), resB = makeRes();
  let aNext = false, bNext = false;
  guestLimit({ user: { isGuest: true }, ip: '10.0.0.3' }, resA, () => { aNext = true; });
  guestLimit({ user: { isGuest: true }, ip: '10.0.0.4' }, resB, () => { bNext = true; });
  assert(aNext && bNext, 'dos IPs nuevas pasan ambas (contadores separados)');
}

console.log('\n[TEST 4] Reset por día (simulación manipulando Date.now)');
{
  const realNow = Date.now;
  const ip = '10.0.0.5';
  for (let i = 0; i < REAL_LIMIT; i++) {
    guestLimit({ user: { isGuest: true }, ip }, makeRes(), () => {});
  }
  // Congelar "mañana"
  const tomorrow = new Date(realNow() + 24 * 60 * 60 * 1000);
  Date.now = () => tomorrow.getTime();
  const res = makeRes();
  let nextAfterReset = false;
  guestLimit({ user: { isGuest: true }, ip }, res, () => { nextAfterReset = true; });
  Date.now = realNow;
  assert(nextAfterReset, 'IP agotada hoy vuelve a pasar mañana');
}

console.log('\n══════════════════════════════════════════════════');
if (failures === 0) console.log('✅ TODAS LAS PRUEBAS PASARON — guestLimit blindado.');
else console.log(`❌ ${failures} prueba(s) fallaron.`);
console.log('══════════════════════════════════════════════════');
process.exit(failures === 0 ? 0 : 1);

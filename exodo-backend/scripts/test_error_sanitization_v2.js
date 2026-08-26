'use strict';

/**
 * ============================================================================
 * test_error_sanitization_v2.js — Sanitización contra la arquitectura ACTUAL
 * ============================================================================
 * El harness original (test_error_sanitization.js) quedó obsoleto cuando se
 * eliminó deepseekProvider y el router pasó a Alibaba-only. Este test v2:
 *
 *   A) routeMessageStream devuelve shape sanitizado ({error:true, message})
 *      cuando TODA la cadena falla con mensajes crudos del vendor (413/429),
 *      sin filtrar org IDs / URLs / tamaños de payload.
 *   B) containsVendorLeak detecta fugas típicas de Groq/DashScope/OpenAI.
 *   C) La cadena de fallback se agota completa antes de rendirse.
 *
 * Stub: se inyecta un providers/alibaba falso en require.cache ANTES de
 * cargar modelRouter, así no hay llamadas de red reales.
 */

const assert = (cond, msg) => {
  if (!cond) { failures++; console.error(`  ❌ ${msg}`); }
  else { console.log(`  ✅ ${msg}`); }
};

let failures = 0;

// ── Fugas sintéticas del estilo real de los vendors ─────────────────────────
const VENDOR_LEAK_413 =
  '413 Request Entity Too Large: org-org1234567890 maximum context length is 4096 tokens, got 51234 tokens';
const VENDOR_LEAK_429 =
  'Error: 429 You exceeded your current quota at https://dashscope-intl.aliyuncs.com/compatible-mode/v1 (org: rs-abc123), payload: 18342 bytes';
const LEAK_MARKERS = ['org-org1234567890', 'rs-abc123', 'dashscope-intl', '18342'];

// ── Stub del proveedor Alibaba ───────────────────────────────────────────────
const providerState = { calls: 0, failWith: null };

const alibabaPath = require.resolve('../src/services/providers/alibaba');
require.cache[alibabaPath] = {
  id: alibabaPath,
  filename: alibabaPath,
  loaded: true,
  exports: {
    resolveModelName: (m) => m || 'stub',
    getClient: () => ({}),
    call: async () => { providerState.calls++; throw makeErr(); },
    callStream: async () => { providerState.calls++; throw makeErr(); },
  },
};

function makeErr() {
  const e = new Error(providerState.failWith?.message || 'stub error');
  if (providerState.failWith?.status) e.status = providerState.failWith.status;
  return e;
}

async function run() {
  const { USER_FACING_ERROR_MESSAGE, containsVendorLeak } = require('../src/services/errorSanitizer');
  const { routeMessageStream } = require('../src/services/modelRouter');

  console.log('\n[TEST A] Unitario — containsVendorLeak');
  assert(containsVendorLeak(VENDOR_LEAK_413) === true, 'detecta fuga 413 (org ID)');
  assert(containsVendorLeak(VENDOR_LEAK_429) === true, 'detecta fuga 429 (URL vendor)');
  assert(containsVendorLeak('Respuesta normal del asistente') === false, 'no marca texto limpio como fuga');

  console.log('\n[TEST B] Cadena agotada con 413 en todos los eslabones');
  providerState.calls = 0;
  providerState.failWith = { status: 413, message: VENDOR_LEAK_413 };
  const rB = await routeMessageStream(
    'genesis', 'SIMPLE',
    [{ role: 'user', content: 'prueba' }],
    'system',
    () => {},
    null, [], undefined, false, false, null
  );
  assert(rB && rB.error === true, 'B: resultado marca error:true');
  assert(rB.message === USER_FACING_ERROR_MESSAGE, 'B: mensaje = genérico de marca');
  assert(!LEAK_MARKERS.some((m) => JSON.stringify(rB).includes(m)), 'B: resultado libre de datos del vendor');
  assert(providerState.calls >= 2, `B: cadena intentó varios eslabones (${providerState.calls} llamadas)`);

  console.log('\n[TEST C] Cadena agotada con 429 (quota)');
  providerState.calls = 0;
  providerState.failWith = { status: 429, message: VENDOR_LEAK_429 };
  const rC = await routeMessageStream(
    'guest', 'SIMPLE',
    [{ role: 'user', content: 'prueba' }],
    'system',
    () => {},
    null, [], undefined, false, true, null
  );
  assert(rC && rC.error === true, 'C: guest degradado también recibe shape sanitizado');
  assert(!LEAK_MARKERS.some((m) => JSON.stringify(rC).includes(m)), 'C: 0 marcadores de fuga');

  console.log('\n══════════════════════════════════════════════════');
  if (failures === 0) {
    console.log('✅ TODAS LAS PRUEBAS PASARON — sanitización verificada en arquitectura actual.');
  } else {
    console.log(`❌ ${failures} prueba(s) fallaron.`);
  }
  console.log('══════════════════════════════════════════════════');
  process.exit(failures === 0 ? 0 : 1);
}

setTimeout(() => {
  console.error('❌ TIMEOUT: el harness excedió 20s.');
  process.exit(1);
}, 20000).unref();

run().catch((err) => {
  console.error('❌ Error fatal del harness:', err);
  process.exit(1);
});

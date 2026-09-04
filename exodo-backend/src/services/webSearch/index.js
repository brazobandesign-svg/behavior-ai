'use strict';

/**
 * src/services/webSearch/index.js
 *
 * Orquestador de búsqueda web viva ($0, failover silencioso).
 *
 * Cadena: serper -> brave -> tavily -> exa -> jina -> deepseek(apagado).
 * Delante de todo: caché Supabase 7 días. Alrededor: topes diarios por
 * usuario (Free 5 / Pro 30), tope mensual global (breaker 80%) y topes
 * mensuales por proveedor (90% de su free tier).
 *
 * Todo desactivable con WEB_SEARCH_ENABLED=false. Sin keys o sin Supabase:
 * devuelve unavailable sin romper el chat (fallback a conocimiento).
 */

const crypto = require('crypto');
const supabase = require('../../config/supabase');
const {
  serperSearch,
  braveSearch,
  tavilySearch,
  exaSearch,
  jinaSearch,
  jinaExtract,
  deepseekSearch,
} = require('./providers');

// --- Señales del gate -----------------------------------------------------------
// Explícito manda (override estilo Claude). Recencia dispara (auto estilo
// Gemini/GPT). REDACCIÓN solo con explícito (cuida la cuota).
const EXPLICIT_SEARCH =
  /(busca(r)?\s+(en\s+)?(la\s+web|en\s+internet|en\s+l[ií]nea)|verif[ií]ca(lo|r)?(\s+en)?(\s+la\s+web|\s+en\s+internet|\s+en\s+l[ií]nea)?|b[uú]scalo\s+en|conf[ií]rmalo\s+en|investiga\s+en\s+(la\s+web|internet))/i;
const EXPLICIT_NOBROWSE =
  /(sin\s+buscar|no\s+busques|usa\s+solo\s+tu\s+conocimiento|sin\s+internet|no\s+uses\s+(la\s+web|internet))/i;
const RECENCY =
  /(actual(izado)?s?|hoy|ayer|esta\s+semana|este\s+mes|este\s+a[ñn]o|20 ?2[4-9]|últim[oa]s?|reciente?s?|precio?s?|qui[ée]n\s+gan[óo]|qu[ée]\s+pas[óo]\s+con|noticia?s?|ocurri[óo]|anunci[óo]|resultados?\s+de|lanzamiento|estreno|cu[aá]ndo\s+(sali[óo]|se\s+lanz[óo]|fue|anunciaron|ocurri[óo]|publicaron)|fecha\s+de\s+(lanzamiento|salida|publicaci[óo]n)|se\s+lanz[óo]|fue\s+anunciado)/i;

const { getLocalDateKey } = require('../../utils/timezone');

// Tracker de búsquedas para Guest e Incógnito en memoria por IP y medianoche local
const _guestSearchUsage = new Map(); // ip -> { date: 'YYYY-MM-DD', count }

function getGuestSearchCount(ip, timezone, nowMs = Date.now()) {
  if (!ip) return 0;
  const today = getLocalDateKey(timezone, nowMs);
  const entry = _guestSearchUsage.get(ip);
  if (!entry || entry.date !== today) return 0;
  return entry.count;
}

function bumpGuestSearch(ip, timezone, nowMs = Date.now()) {
  if (!ip) return;
  const today = getLocalDateKey(timezone, nowMs);
  if (_guestSearchUsage.size > 5000) {
    for (const [k, v] of _guestSearchUsage) {
      if (v.date !== today) _guestSearchUsage.delete(k);
    }
  }
  let entry = _guestSearchUsage.get(ip);
  if (!entry || entry.date !== today) {
    entry = { date: today, count: 0 };
    _guestSearchUsage.set(ip, entry);
  }
  entry.count += 1;
}

const SKIP_INTENTS = new Set(['IMAGEN', 'DOCUMENTO', 'VISION']);

/**
 * ¿Este turno amerita búsqueda viva? Puro y barato (sin LLM).
 * Devuelve { search, forced, quotaExceeded } — forced=true solo con pedido explícito.
 */
function needsWebSearch({ message, intent, hasImages, isGuest, isIncognito, clientIp, timezone }) {
  if (process.env.WEB_SEARCH_ENABLED === 'false') return { search: false, forced: false };
  if (hasImages) return { search: false, forced: false };

  // Control estricto de búsquedas web para Guest e Incógnito (máx 3/día)
  if (isGuest || isIncognito) {
    const used = getGuestSearchCount(clientIp, timezone);
    if (used >= 3) {
      return { search: false, forced: false, quotaExceeded: true };
    }
  }

  const text = String(message || '');
  if (EXPLICIT_NOBROWSE.test(text)) return { search: false, forced: false };
  const forced = EXPLICIT_SEARCH.test(text);
  if (forced) return { search: true, forced: true };
  if (SKIP_INTENTS.has(intent)) return { search: false, forced: false };
  if (intent === 'REDACCION') return { search: false, forced: false };
  if (RECENCY.test(text)) return { search: true, forced: false };
  return { search: false, forced: false };
}

// --- Config ----------------------------------------------------------------------
function cfg() {
  return {
    enabled: process.env.WEB_SEARCH_ENABLED !== 'false',
    monthlyCap: parseInt(process.env.WEB_SEARCH_MONTHLY_CAP || '4400', 10),
    freeDaily: parseInt(process.env.WEB_SEARCH_FREE_DAILY || '5', 10),
    proDaily: parseInt(process.env.WEB_SEARCH_PRO_DAILY || '30', 10),
    cacheDays: parseInt(process.env.WEB_SEARCH_CACHE_DAYS || '7', 10),
  };
}

// Topes mensuales por proveedor (90% de su free tier).
const PROVIDER_CHAIN = [
  { name: 'serper', fn: serperSearch, monthlyCap: 2250 },
  { name: 'brave', fn: braveSearch, monthlyCap: 900 },
  { name: 'tavily', fn: tavilySearch, monthlyCap: 900 },
  { name: 'exa', fn: exaSearch, monthlyCap: 1200 },
  { name: 'jina', fn: jinaSearch, monthlyCap: 2500 },
  { name: 'deepseek', fn: deepseekSearch, monthlyCap: 0 }, // apagado
];

function monthStart() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`;
}

function todayStr() {
  return new Date().toISOString().slice(0, 10);
}

function hashQuery(q) {
  const norm = String(q || '').toLowerCase().replace(/\s+/g, ' ').trim();
  return crypto.createHash('sha256').update(norm).digest('hex');
}

// --- Caché y cuotas (Supabase; si no hay cliente, se opera sin red) ---------------
async function cacheGet(hash, cacheDays) {
  if (!supabase) return null;
  try {
    const since = new Date(Date.now() - cacheDays * 86400000).toISOString();
    const { data } = await supabase
      .from('web_search_cache')
      .select('results, provider')
      .eq('query_hash', hash)
      .gte('created_at', since)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    if (data && Array.isArray(data.results) && data.results.length > 0) {
      return { results: data.results, provider: data.provider || 'cache' };
    }
  } catch (_) {}
  return null;
}

async function cachePut(hash, query, results, provider) {
  if (!supabase) return;
  try {
    await supabase.from('web_search_cache').upsert(
      {
        query_hash: hash,
        query: String(query || '').slice(0, 500),
        results: results.slice(0, 5),
        provider,
        created_at: new Date().toISOString(),
      },
      { onConflict: 'query_hash' }
    );
  } catch (_) {}
}

async function userDayCount(userId) {
  if (!supabase || !userId) return 0;
  try {
    const { data } = await supabase
      .from('web_search_usage')
      .select('count')
      .eq('user_id', userId)
      .eq('day', todayStr())
      .maybeSingle();
    return data?.count || 0;
  } catch (_) {
    return 0;
  }
}

async function bumpUserDay(userId) {
  if (!supabase || !userId) return;
  try {
    const day = todayStr();
    const { data } = await supabase
      .from('web_search_usage')
      .select('count')
      .eq('user_id', userId)
      .eq('day', day)
      .maybeSingle();
    const next = (data?.count || 0) + 1;
    await supabase.from('web_search_usage').upsert(
      { user_id: userId, day, count: next },
      { onConflict: 'user_id,day' }
    );
  } catch (_) {}
}

async function monthTotals() {
  // { global, perProvider } — si no hay Supabase, ceros (sin red de control).
  const totals = { global: 0, perProvider: {} };
  if (!supabase) return totals;
  try {
    const { data } = await supabase
      .from('web_search_provider_usage')
      .select('provider, count')
      .eq('month', monthStart());
    for (const row of data || []) {
      totals.perProvider[row.provider] = row.count || 0;
      totals.global += row.count || 0;
    }
  } catch (_) {}
  return totals;
}

async function bumpProvider(provider) {
  if (!supabase || !provider || provider === 'cache') return;
  try {
    const month = monthStart();
    const { data } = await supabase
      .from('web_search_provider_usage')
      .select('count')
      .eq('provider', provider)
      .eq('month', month)
      .maybeSingle();
    const next = (data?.count || 0) + 1;
    await supabase.from('web_search_provider_usage').upsert(
      { provider, month, count: next },
      { onConflict: 'provider,month' }
    );
  } catch (_) {}
}

// --- Orquestador -------------------------------------------------------------------
/**
 * Ejecuta la cadena con caché, cuotas y failover.
 * Devuelve { results, provider, cached, unavailable }.
 * unavailable: null | 'disabled' | 'no_keys' | 'user_cap' | 'global_cap' | 'error'
 */
async function runWebSearch(query, { userId = null, isPro = false, isGuest = false, isIncognito = false, clientIp = null, timezone = null, signal = null, onProvider = null } = {}) {
  const c = cfg();
  const q = String(query || '').trim().slice(0, 300);
  if (!c.enabled || !q) return { results: [], provider: null, cached: false, unavailable: 'disabled' };

  // Control estricto de búsquedas para Guest / Incognito (máx 3/día)
  if (isGuest || isIncognito) {
    const used = getGuestSearchCount(clientIp, timezone);
    if (used >= 3) {
      return { results: [], provider: null, cached: false, unavailable: 'guest_search_limit' };
    }
  }

  const hasAnyKey =
    process.env.SERPER_API_KEY || process.env.BRAVE_API_KEY ||
    process.env.TAVILY_API_KEY || process.env.EXA_API_KEY ||
    process.env.JINA_API_KEY;
  if (!hasAnyKey && process.env.WEB_SEARCH_DEEPSEEK_ENABLED !== 'true') {
    return { results: [], provider: null, cached: false, unavailable: 'no_keys' };
  }

  // Tope diario por usuario registrado (Free / Pro).
  if (userId) {
    const limit = isPro ? c.proDaily : c.freeDaily;
    const used = await userDayCount(userId);
    if (used >= limit) {
      return { results: [], provider: null, cached: false, unavailable: 'user_cap' };
    }
  }

  // Breaker global mensual.
  const totals = await monthTotals();
  if (totals.global >= c.monthlyCap) {
    return { results: [], provider: null, cached: false, unavailable: 'global_cap' };
  }

  // Presupuesto de snippets diferenciado: 3 para Guest/Incógnito, 5 para Free, 10 para Pro
  const maxSlice = (isGuest || isIncognito) ? 3 : (isPro ? 10 : 5);

  // Caché primero (no gasta cuota de nadie).
  const hash = hashQuery(q);
  const hit = await cacheGet(hash, c.cacheDays);
  if (hit) {
    return { results: (hit.results || []).slice(0, maxSlice), provider: hit.provider, cached: true, unavailable: null };
  }

  // Cadena con failover silencioso.
  for (const p of PROVIDER_CHAIN) {
    try {
      const used = totals.perProvider[p.name] || 0;
      if (used >= p.monthlyCap) continue;
      if (p.name === 'deepseek' && process.env.WEB_SEARCH_DEEPSEEK_ENABLED !== 'true') continue;
      const started = Date.now();
      const results = await p.fn(q, { signal });
      if (results && results.length > 0) {
        await bumpProvider(p.name);
        if (userId) await bumpUserDay(userId);
        if (isGuest || isIncognito) bumpGuestSearch(clientIp, timezone);
        await cachePut(hash, q, results, p.name);
        try { onProvider?.(p.name, Date.now() - started, false); } catch (_) {}
        return { results: results.slice(0, maxSlice), provider: p.name, cached: false, unavailable: null };
      }
      // null o vacío: el siguiente lo intenta (sin registrar gasto si ni
      // siquiera respondió; si respondió vacío igual consumió llamada, pero
      // no lo contamos para no castigar rarezas de un índice).
    } catch (_) {
      continue;
    }
  }
  return { results: [], provider: null, cached: false, unavailable: 'error' };
}

/**
 * Enriquece con Jina Reader las 2 primeras URLs cuando los snippets son
 * pobres (<120 chars). Protege el saldo: máximo 2 extracciones por turno.
 */
async function enrichWithReader(results, { isGuest = false, isIncognito = false, signal = null } = {}) {
  const out = (results || []).slice(0, 5);
  if (isGuest || isIncognito) return out; // Saldo protegido: invitados no disparan Jina Reader
  let used = 0;
  for (const r of out) {
    if (used >= 2) break;
    if (r.snippet && r.snippet.length >= 120) continue;
    if (!r.url || !/^https?:\/\//i.test(r.url)) continue;
    // eslint-disable-next-line no-await-in-loop
    const text = await jinaExtract(r.url, { signal }).catch(() => '');
    if (text) {
      r.snippet = text;
      used += 1;
    }
  }
  return out;
}

module.exports = {
  needsWebSearch,
  runWebSearch,
  enrichWithReader,
  hashQuery,
  PROVIDER_CHAIN,
  _guestSearchUsage,
  getGuestSearchCount,
  bumpGuestSearch,
};

try {
  module.exports.hostOf = require('./providers').hostOf;
} catch (_) {
  module.exports.hostOf = (u) => {
    try { return new URL(u).hostname.replace(/^www\./, ''); } catch (_) { return ''; }
  };
}

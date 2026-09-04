'use strict';

/**
 * src/services/webSearch/providers.js
 *
 * Adaptadores de búsqueda web viva — una sola forma:
 *   adapter(query, { signal }) -> [{ title, url, snippet }] | null
 *
 * null = proveedor no disponible (sin key, timeout, HTTP != 200): la cadena
 * continúa con el siguiente. [] = disponible pero sin resultados: también
 * continúa (otro índice puede tenerlos).
 *
 * Orden de cadena (orquestador): serper -> brave -> tavily -> exa -> jina.
 * DeepSeek web_search existe SOLO como stub apagado: se activará cuando el
 * backend real incorpore DeepSeek y se retire Alibaba. NUNCA se llama hoy.
 */

const FETCH_TIMEOUT_MS = 8000;

function withTimeout(signal) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS);
  const onAbort = () => {
    clearTimeout(t);
    try { signal?.removeEventListener?.('abort', onAbort); } catch (_) {}
  };
  try { signal?.addEventListener?.('abort', onAbort, { once: true }); } catch (_) {}
  return { signal: ctrl.signal, done: () => clearTimeout(t) };
}

function hostOf(url) {
  try { return new URL(url).hostname.replace(/^www\./, ''); } catch (_) { return ''; }
}

function clean(s, max = 500) {
  const t = String(s || '').replace(/\s+/g, ' ').trim();
  return t.length > max ? t.slice(0, max) + '…' : t;
}

// --- Serper (Google SERP, titular) -------------------------------------------
async function serperSearch(query, opts = {}) {
  const key = process.env.SERPER_API_KEY;
  if (!key) return null;
  const { signal, done } = withTimeout(opts.signal);
  try {
    const res = await fetch('https://google.serper.dev/search', {
      method: 'POST',
      signal,
      headers: { 'X-API-KEY': key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ q: query, num: 5, hl: 'es', gl: 'do' }),
    });
    if (!res.ok) return null;
    const data = await res.json().catch(() => ({}));
    const items = Array.isArray(data.organic) ? data.organic : [];
    return items.slice(0, 5).map((r) => ({
      title: clean(r.title, 140),
      url: r.link || '',
      snippet: clean(r.snippet, 500),
    })).filter((r) => r.url);
  } catch (_) {
    return null;
  } finally {
    done();
  }
}

// --- Brave (índice propio, relevo 1) ------------------------------------------
async function braveSearch(query, opts = {}) {
  const key = process.env.BRAVE_API_KEY;
  if (!key) return null;
  const { signal, done } = withTimeout(opts.signal);
  try {
    const url = `https://api.search.brave.com/res/v1/web/search?q=${encodeURIComponent(query)}&count=5&search_lang=es&country=DO`;
    const res = await fetch(url, {
      signal,
      headers: { Accept: 'application/json', 'X-Subscription-Token': key },
    });
    if (!res.ok) return null;
    const data = await res.json().catch(() => ({}));
    const items = (data.web && Array.isArray(data.web.results)) ? data.web.results : [];
    return items.slice(0, 5).map((r) => ({
      title: clean(r.title, 140),
      url: r.url || '',
      snippet: clean(r.description, 500),
    })).filter((r) => r.url);
  } catch (_) {
    return null;
  } finally {
    done();
  }
}

// --- Tavily (agent-native, relevo 2) -------------------------------------------
async function tavilySearch(query, opts = {}) {
  const key = process.env.TAVILY_API_KEY;
  if (!key) return null;
  const { signal, done } = withTimeout(opts.signal);
  try {
    const res = await fetch('https://api.tavily.com/search', {
      method: 'POST',
      signal,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        api_key: key,
        query,
        max_results: 5,
        search_depth: 'basic',
        include_answer: false,
      }),
    });
    if (!res.ok) return null;
    const data = await res.json().catch(() => ({}));
    const items = Array.isArray(data.results) ? data.results : [];
    return items.slice(0, 5).map((r) => ({
      title: clean(r.title, 140),
      url: r.url || '',
      snippet: clean(r.content, 500),
    })).filter((r) => r.url);
  } catch (_) {
    return null;
  } finally {
    done();
  }
}

// --- Exa (neural, relevo 3) ----------------------------------------------------
async function exaSearch(query, opts = {}) {
  const key = process.env.EXA_API_KEY;
  if (!key) return null;
  const { signal, done } = withTimeout(opts.signal);
  try {
    const res = await fetch('https://api.exa.ai/search', {
      method: 'POST',
      signal,
      headers: { 'x-api-key': key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query, numResults: 5, type: 'auto' }),
    });
    if (!res.ok) return null;
    const data = await res.json().catch(() => ({}));
    const items = Array.isArray(data.results) ? data.results : [];
    return items.slice(0, 5).map((r) => ({
      title: clean(r.title, 140),
      url: r.url || '',
      snippet: clean(r.text || r.snippet, 500),
    })).filter((r) => r.url);
  } catch (_) {
    return null;
  } finally {
    done();
  }
}

// --- Jina Search (relevo 4, gratis generoso) -------------------------------------
// s.jina.ai devuelve 5 entradas JSON {title, url, content}. Sin key también
// responde con rate bajo; con key usa el saldo del usuario.
async function jinaSearch(query, opts = {}) {
  const key = process.env.JINA_API_KEY;
  const { signal, done } = withTimeout(opts.signal);
  try {
    const res = await fetch(`https://s.jina.ai/?q=${encodeURIComponent(query)}`, {
      signal,
      headers: {
        Accept: 'application/json',
        ...(key ? { Authorization: `Bearer ${key}` } : {}),
      },
    });
    if (!res.ok) return null;
    const data = await res.json().catch(() => null);
    const items = Array.isArray(data) ? data : (data && Array.isArray(data.data) ? data.data : []);
    return items.slice(0, 5).map((r) => ({
      title: clean(r.title, 140),
      url: r.url || '',
      snippet: clean(r.content || r.description, 500),
    })).filter((r) => r.url);
  } catch (_) {
    return null;
  } finally {
    done();
  }
}

// --- Jina Reader (extracción de 1-2 URLs top, presupuesto bajo) ------------------
// Solo se usa cuando los snippets son pobres. Token budget corto a propósito:
// el default de 200K fundiría el saldo.
async function jinaExtract(url, opts = {}) {
  const key = process.env.JINA_API_KEY;
  if (!url) return '';
  const { signal, done } = withTimeout(opts.signal);
  try {
    const res = await fetch(`https://r.jina.ai/${url}`, {
      signal,
      headers: {
        Accept: 'text/markdown',
        ...(key ? { Authorization: `Bearer ${key}` } : {}),
        'X-Token-Budget': String(opts.tokenBudget || 6000),
        'X-Retain-Images': 'none',
        'X-Remove-Selector': 'nav, footer, .sidebar, #ads',
      },
    });
    if (!res.ok) return '';
    const text = await res.text().catch(() => '');
    return clean(text, opts.maxChars || 2500);
  } catch (_) {
    return '';
  } finally {
    done();
  }
}

// --- DeepSeek web_search: STUB APAGADO -------------------------------------------
// NO LLAMAR hasta el backend real (sin Alibaba). Se activa con
// WEB_SEARCH_DEEPSEEK_ENABLED=true y aquí irá la llamada a su Responses API
// con herramienta web_search. Hoy siempre devuelve null sin gastar nada.
async function deepseekSearch(/* query, opts */) {
  if (process.env.WEB_SEARCH_DEEPSEEK_ENABLED !== 'true') return null;
  // TODO(backend-real): implementar contra DeepSeek Responses API.
  return null;
}

module.exports = {
  serperSearch,
  braveSearch,
  tavilySearch,
  exaSearch,
  jinaSearch,
  jinaExtract,
  deepseekSearch,
  hostOf,
};

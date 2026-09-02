'use strict';

/**
 * src/routes/artifacts.js
 *
 * Endpoints Cloud Artifacts:
 *   - POST /api/artifacts/publish   (autenticado)   -> crea y devuelve { slug, url }
 *   - GET  /api/artifacts/:slug     (público)       -> HTML con OG meta tags + iframe sandbox
 *   - GET  /api/artifacts/:slug/raw (público)       -> JSON con source_code y metadatos
 *   - GET  /api/artifacts/me        (autenticado)   -> lista mis artefactos
 *   - DELETE /api/artifacts/:slug   (autenticado)   -> elimina mi artefacto
 *
 * Dependencias:
 *   nanoid@^3.3.7 zod@^3.23.8 sanitize-html@^2.13.0
 */

const express = require('express');
const { z } = require('zod');
const { customAlphabet } = require('nanoid');
const sanitizeHtml = require('sanitize-html');

const auth = require('../middleware/auth');
const { chatRateLimiter } = require('../middleware/rateLimiter');
const { planGuard } = require('../middleware/planGuard');
const supabase = require('../config/supabase');

const router = express.Router();

const PUBLIC_BASE_URL = (process.env.PUBLIC_BASE_URL || 'https://exodo.app').replace(/\/+$/, '');
const SLUG_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
const newSlug = customAlphabet(SLUG_ALPHABET, 12);

// TTL por plan (en días). null = permanente (Doctrina Éxodo).
const TTL_DAYS_BY_PLAN = {
  guest: 30,
  genesis: null,
  hazak: null,
};

// ---------------------------------------------------------------------------
// Validadores
// ---------------------------------------------------------------------------

const PublishSchema = z.object({
  title: z.string().trim().min(1).max(200),
  description: z.string().trim().max(500).optional().nullable(),
  kind: z.enum(['html', 'markdown', 'mermaid', 'svg', 'code', 'react']),
  language: z.string().trim().max(40).optional().nullable(),
  source_code: z.string().min(1).max(200_000),
  metadata: z.record(z.any()).optional().default({}),
  is_public: z.boolean().optional().default(true),
});

// ---------------------------------------------------------------------------
// Sanitización
// ---------------------------------------------------------------------------

const SANITIZE_OPTS = {
  allowedTags: [
    'h1','h2','h3','h4','h5','h6',
    'p','br','hr','span','div','section','article','aside','header','footer','main','nav',
    'ul','ol','li','dl','dt','dd',
    'strong','em','b','i','u','s','sub','sup','small','mark','code','pre','kbd','samp','var',
    'a','img','figure','figcaption','picture','source',
    'table','thead','tbody','tfoot','tr','th','td','caption','colgroup','col',
    'blockquote','q','cite','abbr','time','address',
    'svg','g','path','rect','circle','ellipse','line','polyline','polygon','text','tspan','defs','use','marker',
  ],
  allowedAttributes: {
    '*': ['class', 'id', 'title', 'aria-label', 'role', 'data-*', 'style'],
    a: ['href', 'target', 'rel'],
    img: ['src', 'alt', 'width', 'height', 'loading'],
    source: ['src', 'srcset', 'type', 'media', 'sizes'],
    svg: ['xmlns', 'viewbox', 'width', 'height', 'fill', 'stroke', 'stroke-width'],
    path: ['d', 'fill', 'stroke', 'stroke-width', 'transform'],
    rect: ['x', 'y', 'width', 'height', 'rx', 'ry', 'fill', 'stroke'],
    circle: ['cx', 'cy', 'r', 'fill', 'stroke'],
    line: ['x1', 'y1', 'x2', 'y2', 'stroke'],
    text: ['x', 'y', 'fill', 'font-size', 'text-anchor'],
  },
  allowedSchemes: ['http', 'https', 'mailto', 'data'],
  allowedSchemesByTag: {
    img: ['http', 'https', 'data'],
  },
  allowProtocolRelative: false,
  allowedStyles: {
    '*': {
      'color': [/^#(0x)?[0-9a-f]+$/i, /^rgb\(/, /^rgba\(/, /^hsl\(/, /^hsla\(/],
      'background': [/^#(0x)?[0-9a-f]+$/i, /^rgb\(/, /^rgba\(/, /^(none|transparent|inherit)$/],
      'background-color': [/^#(0x)?[0-9a-f]+$/i, /^rgb\(/, /^rgba\(/, /^(none|transparent|inherit)$/],
      'font-size': [/^\d+(?:\.\d+)?(?:px|em|rem|%)$/],
      'text-align': [/^(left|right|center|justify)$/],
      'margin': [/^[\d\.\-px\s%auto]+$/],
      'padding': [/^[\d\.\-px\s%]+$/],
    },
  },
  transformTags: {
    a: (tagName, attribs) => ({
      tagName: 'a',
      attribs: {
        ...attribs,
        rel: 'noopener noreferrer nofollow',
        target: '_blank',
      },
    }),
  },
};

function sanitizeSource(kind, source) {
  if (kind === 'html' || kind === 'svg' || kind === 'react') {
    return sanitizeHtml(source, SANITIZE_OPTS);
  }
  return source;
}

// ---------------------------------------------------------------------------
// Generador de la página HTML con OpenGraph + iframe sandbox
// ---------------------------------------------------------------------------

function buildViewerHtml({ artifact, og }) {
  const sanitized = sanitizeSource(artifact.kind, artifact.source_code);
  const publicUrl = `${PUBLIC_BASE_URL}/api/artifacts/${artifact.slug}`;

  const csp = [
    "default-src 'self'",
    "script-src 'self' 'unsafe-inline'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: https:",
    "font-src 'self' data:",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'none'",
  ].join('; ');

  const srcdoc = `<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeAttr(artifact.title)}</title>
  <style>
    :root { color-scheme: light dark; }
    body { margin: 0; padding: 16px; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; line-height: 1.55; }
    pre, code { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
    pre { padding: 12px; background: rgba(127,127,127,.08); border-radius: 8px; overflow-x: auto; }
    img, svg { max-width: 100%; height: auto; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid rgba(127,127,127,.3); padding: 6px 10px; text-align: left; }
  </style>
</head>
<body>${sanitized}</body>
</html>`;

  return `<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <title>${escapeAttr(artifact.title)} · Éxodo</title>
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <meta name="description" content="${escapeAttr(artifact.description || artifact.title)}">
  <meta http-equiv="Content-Security-Policy" content="${escapeAttr(csp)}">

  <!-- OpenGraph -->
  <meta property="og:type" content="article">
  <meta property="og:title" content="${escapeAttr(og.title)}">
  <meta property="og:description" content="${escapeAttr(og.description)}">
  <meta property="og:url" content="${escapeAttr(publicUrl)}">
  <meta property="og:site_name" content="Éxodo">
  <meta property="og:locale" content="es_DO">
  <meta property="article:published_time" content="${escapeAttr(artifact.created_at)}">
  <meta property="article:author" content="${escapeAttr(og.authorName)}">
  ${og.ogImage ? `<meta property="og:image" content="${escapeAttr(og.ogImage)}">` : ''}
  ${og.ogImage ? `<meta property="og:image:width" content="1200">` : ''}
  ${og.ogImage ? `<meta property="og:image:height" content="630">` : ''}

  <!-- Twitter Card -->
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${escapeAttr(og.title)}">
  <meta name="twitter:description" content="${escapeAttr(og.description)}">
  ${og.ogImage ? `<meta name="twitter:image" content="${escapeAttr(og.ogImage)}">` : ''}

  <!-- XSS hardening extra -->
  <meta name="referrer" content="strict-origin-when-cross-origin">
  <meta http-equiv="X-Content-Type-Options" content="nosniff">

  <style>
    :root {
      --ink-deep: #0E0C0A;
      --gold: #C9933A;
      --bg: #fbfaf6;
      --fg: #1a1a1a;
      --muted: #6b6b6b;
    }
    @media (prefers-color-scheme: dark) {
      :root { --bg: #0E0C0A; --fg: #f4f1ea; --muted: #a8a8a8; }
    }
    * { box-sizing: border-box; }
    html, body { margin: 0; padding: 0; background: var(--bg); color: var(--fg); font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
    .exo-header {
      padding: 12px 18px; border-bottom: 1px solid rgba(127,127,127,.2);
      display: flex; align-items: center; gap: 12px; font-size: 14px;
    }
    .exo-header .exo-brand {
      font-weight: 700; letter-spacing: .5px; color: var(--gold);
    }
    .exo-header .exo-meta { color: var(--muted); margin-left: auto; }
    .exo-frame-wrap {
      width: 100%;
    }
    iframe.exo-artifact {
      display: block; width: 100%; min-height: 70vh; border: 0;
      background: var(--bg);
    }
    .exo-footer {
      padding: 14px 18px; font-size: 12px; color: var(--muted);
      text-align: center; border-top: 1px solid rgba(127,127,127,.2);
    }
    .exo-footer a { color: var(--gold); text-decoration: none; }
  </style>
</head>
<body>
  <header class="exo-header">
    <span class="exo-brand">Éxodo</span>
    <span>${escapeAttr(artifact.title)}</span>
    <span class="exo-meta">${artifact.views_count} ${artifact.views_count === 1 ? 'vista' : 'vistas'}</span>
  </header>

  <div class="exo-frame-wrap">
    <iframe
      class="exo-artifact"
      sandbox="allow-scripts"
      referrerpolicy="no-referrer"
      title="${escapeAttr(artifact.title)}"
      srcdoc="${escapeAttr(srcdoc)}"
    ></iframe>
  </div>

  <footer class="exo-footer">
    Publicado con <a href="${escapeAttr(PUBLIC_BASE_URL)}">Éxodo</a> ·
    <a href="${escapeAttr(publicUrl)}.raw">ver fuente</a>
  </footer>
</body>
</html>`;
}

function escapeAttr(s) {
  if (s == null) return '';
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

// ---------------------------------------------------------------------------
// Generador de la imagen OpenGraph (SVG inline -> data URI)
// ---------------------------------------------------------------------------

function buildOgSvg({ title, description, authorName }) {
  const safeTitle = truncate(title, 90);
  const safeDesc = truncate(description || '', 160);
  const gold = '#C9933A';
  const ink = '#0E0C0A';
  const bg = '#fbfaf6';
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 630" width="1200" height="630">
  <defs>
    <linearGradient id="bgGrad" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="${bg}"/>
      <stop offset="100%" stop-color="#f0eadd"/>
    </linearGradient>
  </defs>
  <rect width="1200" height="630" fill="url(#bgGrad)"/>
  <rect x="0" y="0" width="1200" height="6" fill="${gold}"/>
  <text x="60" y="90" font-family="Georgia, serif" font-size="28" font-weight="700" fill="${gold}" letter-spacing="2">ÉXODO</text>
  <text x="60" y="180" font-family="Georgia, serif" font-size="58" font-weight="700" fill="${ink}">${escapeXml(safeTitle)}</text>
  <text x="60" y="240" font-family="-apple-system, sans-serif" font-size="24" fill="${ink}" opacity="0.7">${escapeXml(safeDesc)}</text>
  <line x1="60" y1="540" x2="1140" y2="540" stroke="${gold}" stroke-width="2"/>
  <text x="60" y="580" font-family="-apple-system, sans-serif" font-size="20" fill="${ink}" opacity="0.6">${escapeXml(authorName || 'Anónimo')}</text>
  <text x="1140" y="580" font-family="-apple-system, sans-serif" font-size="20" fill="${ink}" opacity="0.6" text-anchor="end">exodo.app</text>
</svg>`;
}

function escapeXml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function truncate(s, n) {
  if (!s) return '';
  return s.length > n ? s.slice(0, n - 1) + '…' : s;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function calculateExpiresAt(plan) {
  const days = TTL_DAYS_BY_PLAN[plan];
  if (days == null) return null;
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString();
}

async function fetchAuthorName(userId) {
  if (!supabase || !userId) return 'Anónimo';
  try {
    const { data } = await supabase
      .from('profiles')
      .select('full_name')
      .eq('id', userId)
      .single();
    return data && data.full_name ? data.full_name : 'Anónimo';
  } catch (_) {
    return 'Anónimo';
  }
}

// ---------------------------------------------------------------------------
// POST /api/artifacts/publish
// ---------------------------------------------------------------------------

router.post('/publish', auth, chatRateLimiter, planGuard, async (req, res, next) => {
  try {
    if (!supabase) {
      return res.status(503).json({ error: 'database_unavailable' });
    }
    if (req.user.isGuest) {
      return res.status(401).json({ error: 'authentication_required' });
    }
    if (!req.user.userId) {
      return res.status(401).json({ error: 'authentication_required' });
    }

    const parsed = PublishSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({
        error: 'invalid_payload',
        details: parsed.error.flatten(),
      });
    }
    const body = parsed.data;
    const plan = req.user.plan || 'genesis';
    const expiresAt = calculateExpiresAt(plan);

    let slug = newSlug();
    let inserted = null;
    let lastError = null;
    for (let attempt = 0; attempt < 3; attempt++) {
      const { data, error } = await supabase
        .from('published_artifacts')
        .insert({
          slug,
          user_id: req.user.userId,
          title: body.title,
          description: body.description || null,
          kind: body.kind,
          language: body.language || null,
          source_code: body.source_code,
          metadata: body.metadata || {},
          is_public: body.is_public !== false,
          expires_at: expiresAt,
        })
        .select('id, slug, created_at, expires_at, is_public')
        .single();
      if (!error) {
        inserted = data;
        break;
      }
      lastError = error;
      if (error && error.code === '23505') {
        slug = newSlug();
        continue;
      }
      break;
    }

    if (!inserted) {
      console.error('[artifacts] insert failed:', lastError && lastError.message);
      return res.status(500).json({ error: 'insert_failed' });
    }

    return res.status(201).json({
      id: inserted.id,
      slug: inserted.slug,
      url: `${PUBLIC_BASE_URL}/api/artifacts/${inserted.slug}`,
      raw_url: `${PUBLIC_BASE_URL}/api/artifacts/${inserted.slug}/raw`,
      expires_at: inserted.expires_at,
      created_at: inserted.created_at,
    });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// GET /api/artifacts/:slug   (HTML viewer + OG meta tags)
// ---------------------------------------------------------------------------

router.get('/:slug', chatRateLimiter, async (req, res, next) => {
  try {
    if (!supabase) {
      return res.status(503).json({ error: 'database_unavailable' });
    }
    const { slug } = req.params;
    if (!/^[A-Za-z0-9_-]{8,16}$/.test(slug)) {
      return res.status(404).json({ error: 'not_found' });
    }

    const { data: artifact, error } = await supabase
      .from('published_artifacts')
      .select('id, slug, user_id, title, description, kind, language, source_code, is_public, views_count, expires_at, created_at, updated_at')
      .eq('slug', slug)
      .eq('is_public', true)
      .or('expires_at.is.null,expires_at.gt.now()')
      .maybeSingle();

    if (error) {
      console.error('[artifacts] select error:', error.message);
      return res.status(500).json({ error: 'lookup_failed' });
    }
    if (!artifact) {
      return res.status(404).send(`<!DOCTYPE html><html lang="es"><head><meta charset="utf-8"><title>No encontrado · Éxodo</title></head><body style="font-family:sans-serif;text-align:center;padding:60px"><h1>Artefacto no encontrado</h1><p>El enlace puede haber expirado o sido eliminado.</p></body></html>`);
    }

    supabase.rpc('increment_views', { p_slug: slug }).then(({ error: e }) => {
      if (e) console.warn('[artifacts] increment_views:', e.message);
    }).catch(() => {});

    const authorName = await fetchAuthorName(artifact.user_id);
    const ogSvg = buildOgSvg({
      title: artifact.title,
      description: artifact.description || '',
      authorName,
    });
    const ogImage = `data:image/svg+xml;utf8,${encodeURIComponent(ogSvg)}`;

    const html = buildViewerHtml({
      artifact: { ...artifact, views_count: artifact.views_count + 1 },
      og: {
        title: artifact.title,
        description: artifact.description || artifact.title,
        authorName,
        ogImage,
      },
    });

    res.set('Content-Type', 'text/html; charset=utf-8');
    res.set('Cache-Control', 'public, max-age=30, s-maxage=60');
    res.set('X-Content-Type-Options', 'nosniff');
    res.set('Referrer-Policy', 'strict-origin-when-cross-origin');
    res.set('Content-Security-Policy', "frame-ancestors 'none'");
    return res.status(200).send(html);
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// GET /api/artifacts/:slug/raw   (JSON con source_code)
// ---------------------------------------------------------------------------

router.get('/:slug/raw', async (req, res, next) => {
  try {
    if (!supabase) {
      return res.status(503).json({ error: 'database_unavailable' });
    }
    const { slug } = req.params;
    if (!/^[A-Za-z0-9_-]{8,16}$/.test(slug)) {
      return res.status(404).json({ error: 'not_found' });
    }
    const { data: artifact, error } = await supabase
      .from('published_artifacts')
      .select('id, slug, user_id, title, description, kind, language, source_code, metadata, views_count, created_at')
      .eq('slug', slug)
      .eq('is_public', true)
      .or('expires_at.is.null,expires_at.gt.now()')
      .maybeSingle();
    if (error) {
      return res.status(500).json({ error: 'lookup_failed' });
    }
    if (!artifact) {
      return res.status(404).json({ error: 'not_found' });
    }
    return res.json({
      id: artifact.id,
      slug: artifact.slug,
      title: artifact.title,
      description: artifact.description,
      kind: artifact.kind,
      language: artifact.language,
      source_code: artifact.source_code,
      metadata: artifact.metadata,
      views_count: artifact.views_count,
      created_at: artifact.created_at,
    });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// GET /api/artifacts/me   (lista mis artefactos, autenticado)
// ---------------------------------------------------------------------------

router.get('/me', auth, async (req, res, next) => {
  try {
    if (!supabase) {
      return res.status(503).json({ error: 'database_unavailable' });
    }
    if (!req.user.userId) {
      return res.status(401).json({ error: 'authentication_required' });
    }
    const limit = Math.min(parseInt(req.query.limit, 10) || 50, 200);
    const offset = Math.max(parseInt(req.query.offset, 10) || 0, 0);
    const { data, error } = await supabase
      .from('published_artifacts')
      .select('id, slug, title, kind, language, is_public, views_count, created_at, expires_at')
      .eq('user_id', req.user.userId)
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);
    if (error) {
      console.warn('[artifacts] /me query notice:', error.message);
      return res.json({ items: [], limit, offset });
    }
    return res.json({ items: data || [], limit, offset });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// DELETE /api/artifacts/:slug   (autenticado, sólo dueño)
// ---------------------------------------------------------------------------

router.delete('/:slug', auth, async (req, res, next) => {
  try {
    if (!supabase) {
      return res.status(503).json({ error: 'database_unavailable' });
    }
    if (!req.user.userId) {
      return res.status(401).json({ error: 'authentication_required' });
    }
    const { slug } = req.params;
    if (!/^[A-Za-z0-9_-]{8,16}$/.test(slug)) {
      return res.status(404).json({ error: 'not_found' });
    }
    const { error } = await supabase
      .from('published_artifacts')
      .delete()
      .eq('slug', slug)
      .eq('user_id', req.user.userId);
    if (error) {
      return res.status(500).json({ error: 'delete_failed' });
    }
    return res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

module.exports = router;

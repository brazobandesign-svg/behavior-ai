'use strict';

/**
 * src/routes/expedientes.js
 *
 * Endpoints del módulo "Expedientes" (almacén privado por usuario):
 *   - GET    /api/expedientes       (autenticado) -> lista mis registros (filtro ?category, paginación)
 *   - POST   /api/expedientes       (autenticado) -> crea/guarda un registro
 *   - GET    /api/expedientes/:id   (autenticado) -> detalle + content_payload
 *   - DELETE /api/expedientes/:id   (autenticado) -> elimina un registro propio
 */

const express = require('express');
const { z } = require('zod');

const auth = require('../middleware/auth');
const supabase = require('../config/supabase');

const router = express.Router();

const CATEGORIES = ['documento', 'tabla', 'interactivo'];
const FILE_FORMATS = ['docx', 'xlsx', 'pdf', 'html', 'svg', 'md'];

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Listado: columnas ligeras (sin content_payload).
const LIST_COLUMNS = 'id, user_id, chat_id, title, category, file_format, metadata, created_at, updated_at';
// Detalle: incluye el payload completo.
const DETAIL_COLUMNS = `${LIST_COLUMNS}, content_payload`;

const CreateSchema = z.object({
  title: z.string().trim().min(1).max(500),
  category: z.enum(CATEGORIES),
  file_format: z.enum(FILE_FORMATS),
  content_payload: z.string().min(1).max(2_000_000),
  chat_id: z.string().trim().max(200).optional().nullable(),
  metadata: z.record(z.any()).optional().default({}),
});

/**
 * Resuelve el usuario autenticado o responde 401/503 y devuelve null.
 */
function requireUser(req, res) {
  if (!supabase) {
    res.status(503).json({ error: 'database_unavailable' });
    return null;
  }
  if (!req.user || !req.user.userId) {
    res.status(401).json({ error: 'authentication_required' });
    return null;
  }
  return req.user;
}

function parsePagination(req) {
  const rawLimit = parseInt(req.query.limit, 10);
  const rawOffset = parseInt(req.query.offset, 10);
  const limit = Math.min(Number.isFinite(rawLimit) && rawLimit > 0 ? rawLimit : 50, 200);
  const offset = Math.max(Number.isFinite(rawOffset) && rawOffset >= 0 ? rawOffset : 0, 0);
  return { limit, offset };
}

// ---------------------------------------------------------------------------
// GET /api/expedientes  — listado con filtro opcional por categoría
// ---------------------------------------------------------------------------

router.get('/', auth, async (req, res, next) => {
  try {
    const user = requireUser(req, res);
    if (!user) return;

    const { category } = req.query;
    if (category !== undefined && !CATEGORIES.includes(category)) {
      return res.status(400).json({ error: 'invalid_category', allowed: CATEGORIES });
    }

    const { limit, offset } = parsePagination(req);

    let query = supabase
      .from('expedientes')
      .select(LIST_COLUMNS)
      .eq('user_id', user.userId);

    if (category) {
      query = query.eq('category', category);
    }

    query = query.order('updated_at', { ascending: false }).range(offset, offset + limit - 1);

    const { data, error } = await query;
    if (error) {
      console.error('[expedientes] list error:', error.message);
      return res.status(500).json({ error: 'list_failed' });
    }

    return res.json({ items: data || [], limit, offset });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// POST /api/expedientes  — crea/guarda un registro
// ---------------------------------------------------------------------------

router.post('/', auth, async (req, res, next) => {
  try {
    const user = requireUser(req, res);
    if (!user) return;

    const parsed = CreateSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: 'invalid_payload', details: parsed.error.flatten() });
    }
    const body = parsed.data;

    const { data, error } = await supabase
      .from('expedientes')
      .insert({
        user_id: user.userId,
        chat_id: body.chat_id || null,
        title: body.title,
        category: body.category,
        file_format: body.file_format,
        content_payload: body.content_payload,
        metadata: body.metadata || {},
      })
      .select(DETAIL_COLUMNS)
      .single();

    if (error) {
      console.error('[expedientes] insert error:', error.message);
      return res.status(500).json({ error: 'insert_failed' });
    }

    return res.status(201).json(data);
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// GET /api/expedientes/:id  — detalle + content_payload
// ---------------------------------------------------------------------------

router.get('/:id', auth, async (req, res, next) => {
  try {
    const user = requireUser(req, res);
    if (!user) return;

    const { id } = req.params;
    if (!UUID_RE.test(id)) {
      return res.status(404).json({ error: 'not_found' });
    }

    const { data, error } = await supabase
      .from('expedientes')
      .select(DETAIL_COLUMNS)
      .eq('id', id)
      .eq('user_id', user.userId)
      .maybeSingle();

    if (error) {
      console.error('[expedientes] get error:', error.message);
      return res.status(500).json({ error: 'lookup_failed' });
    }
    if (!data) {
      return res.status(404).json({ error: 'not_found' });
    }

    return res.json(data);
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// DELETE /api/expedientes/:id  — elimina un registro propio
// ---------------------------------------------------------------------------

router.delete('/:id', auth, async (req, res, next) => {
  try {
    const user = requireUser(req, res);
    if (!user) return;

    const { id } = req.params;
    if (!UUID_RE.test(id)) {
      return res.status(404).json({ error: 'not_found' });
    }

    const { error } = await supabase
      .from('expedientes')
      .delete()
      .eq('id', id)
      .eq('user_id', user.userId);

    if (error) {
      console.error('[expedientes] delete error:', error.message);
      return res.status(500).json({ error: 'delete_failed' });
    }

    return res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

module.exports = router;

const supabase = require('../config/supabase');

/**
 * History Manager — Bible: últimos 10 mensajes como contexto.
 * Reduce tokens de entrada ~50% sin que el usuario note diferencia.
 */

/**
 * Recupera los últimos N mensajes de una conversación con Pruning Adaptativo.
 * Garantiza que el historial anterior no exceda el presupuesto de tokens (maxTokens, default: 9000),
 * evitando saturar el contexto del modelo o agotar la cuota del plan Genesis.
 * 25 mensajes ≈ 12 turnos completos (alineado con el estándar de apps de IA;
 * el poda-por-tokens sigue siendo el límite duro real).
 * @param {string} conversationId - UUID de la conversación
 * @param {number} limit - Cantidad de mensajes a recuperar (default: 25)
 * @param {number} maxTokens - Presupuesto máximo de tokens para el historial anterior (default: 9000)
 * @returns {Promise<Array>} - Array de { role, content }
 */
async function getHistory(conversationId, limit = 25, maxTokens = 9000) {
  if (!conversationId || !supabase) return [];

  try {
    // P1-4: Descargar únicamente los 30 turnos más recientes en SQL
    const { data, error } = await supabase
      .from('messages')
      .select('role, content, created_at')
      .eq('conversation_id', conversationId)
      .order('created_at', { ascending: false })
      .limit(30);

    if (error || !data) return [];

    // Defensive sort: restaurar orden cronológico ascendente estable
    const sorted = [...data].sort((a, b) => {
      const ta = new Date(a.created_at).getTime();
      const tb = new Date(b.created_at).getTime();
      if (ta !== tb) return ta - tb;
      if (a.role !== b.role) return a.role === 'user' ? -1 : 1;
      return 0;
    });

    // Limpiar marcadores intermedios de UI (como <!-- ATTACHMENTS con base64 y SOURCES)
    // y deduplicar turnos consecutivos de 'user' causados por guardados en paralelo/móvil
    const cleanedMessages = [];
    for (const msg of sorted) {
      const cleanContent = (msg.content || '')
        .replace(/<!--\s*ATTACHMENTS:.*?-->/gs, '')
        .replace(/<!--\s*SOURCES:.*?-->/gs, '')
        .trim();

      // Si después de limpiar el contenido queda vacío pero es 'user', omitir si es un placeholder de inserción
      if (!cleanContent && msg.role === 'user') continue;

      if (cleanedMessages.length > 0 && cleanedMessages[cleanedMessages.length - 1].role === msg.role && msg.role === 'user') {
        const prev = cleanedMessages[cleanedMessages.length - 1];
        if (cleanContent.length > prev.content.length || cleanContent.includes('[Imagen:')) {
          prev.content = cleanContent || msg.content;
          prev.created_at = msg.created_at;
        }
        continue;
      }

      cleanedMessages.push({
        role: msg.role,
        content: cleanContent || msg.content,
        created_at: msg.created_at,
      });
    }

    // Tomar los últimos N mensajes como ventana cronológica inicial
    const windowMessages = cleanedMessages.slice(-limit);

    // Capa 3: Pruning Adaptativo por Presupuesto de Tokens
    // Recorremos desde el mensaje MÁS RECIENTE del historial hacia el más antiguo
    let accumulatedChars = 0;
    const maxChars = maxTokens * 3.5; // Heurística veloz (~3.5 chars/token)
    const prunedHistory = [];

    for (let i = windowMessages.length - 1; i >= 0; i--) {
      const msg = windowMessages[i];
      const msgChars = (msg.content || '').length;

      // Si añadir este mensaje superaría el presupuesto máximo de tokens
      if (accumulatedChars + msgChars > maxChars) {
        if (prunedHistory.length > 0) {
          // Ya tenemos turnos recientes en el historial; omitimos turnos más antiguos que desbordarían la cuota
          break;
        } else {
          // El turno inmediatamente anterior por sí solo supera el presupuesto de historial (ej. un pegado gigante previo).
          // Truncamos inteligentemente ese mensaje conservando su final (lo más relevante y reciente).
          const allowedChars = Math.max(1000, Math.floor(maxChars - accumulatedChars));
          prunedHistory.unshift({
            role: msg.role,
            content: '...[Contexto anterior resumido por límite de memoria]...\n' + (msg.content || '').slice(-allowedChars),
          });
          break;
        }
      }

      prunedHistory.unshift({
        role: msg.role,
        content: msg.content,
      });
      accumulatedChars += msgChars;
    }

    // Aseguramos que el historial empiece con role:'user' para mantener un contrato de conversación limpio.
    // Si el pruning por tokens dejó el historial arrancando en 'assistant', descartamos turnos iniciales.
    let startIdx = 0;
    while (startIdx < prunedHistory.length && prunedHistory[startIdx].role !== 'user') {
      startIdx++;
    }
    const safeHistory = prunedHistory.slice(startIdx);

    return safeHistory;
  } catch (err) {
    console.error('[historyManager] Error recuperando historial:', err.message);
    return [];
  }
}

/**
 * Guarda un mensaje en la base de datos.
 * No guarda si la conversación es incógnita.
 */
async function saveMessage(conversationId, role, content, metadata = {}) {
  if (!conversationId || !supabase) return null;

  try {
    const insertPayload = {
      conversation_id: conversationId,
      role,
      content,
      intent_detected: metadata.intent || null,
      model_called: metadata.model || null,
      tokens_input: metadata.tokensInput || null,
      tokens_output: metadata.tokensOutput || null,
    };

    if (metadata.sources && metadata.sources.length > 0) {
      insertPayload.sources = metadata.sources;
    }

    let { data, error } = await supabase
      .from('messages')
      .insert(insertPayload)
      .select()
      .single();

    if (error && error.message && error.message.includes('sources')) {
      delete insertPayload.sources;
      const retry = await supabase.from('messages').insert(insertPayload).select().single();
      data = retry.data;
      error = retry.error;
    }

    if (error) {
      console.error('[historyManager] Error guardando mensaje:', error.message);
      return null;
    }

    return data;
  } catch (err) {
    console.error('[historyManager] Error:', err.message);
    return null;
  }
}

/**
 * C1 (TTFT): caché positiva de propiedad de conversación.
 * Antes CADA mensaje pagaba un SELECT a Supabase ANTES de abrir el stream SSE.
 * TTL 60s deslizante (misma política que la caché de sesión en middleware/auth):
 * una revocación de acceso se propaga como mucho en 60s. Solo se cachean
 * resultados exitosos (fail-closed intacto ante errores de BD).
 */
const _ownershipCache = new Map();
const OWNERSHIP_TTL_MS = 60_000;
const OWNERSHIP_CACHE_MAX = 1000;

/**
 * C1 (IDOR): Valida que la conversación pertenezca al usuario autenticado.
 * - Si conversationId no está especificado o el usuario es anónimo/invitado, omite la validación.
 * - Si la conversación no existe aún en la base de datos (creación optimista en cliente), permite continuar.
 * - Si la conversación existe en Supabase pero pertenece a otro user_id, lanza error 403 Forbidden.
 * - P0-5: Fail-Closed. En caso de error de BD o excepción, rechaza con 503/500 en lugar de permitir acceso.
 * @param {string} userId - UUID del usuario autenticado (req.user.userId)
 * @param {string} conversationId - UUID de la conversación
 * @returns {Promise<boolean>}
 */
async function assertConversationOwner(userId, conversationId) {
  if (!conversationId || !userId || !supabase) return true;

  // C1 (TTFT): mensajes consecutivos en la misma conversación no repiten el round-trip.
  const cacheKey = `${userId}:${conversationId}`;
  const now = Date.now();
  const cached = _ownershipCache.get(cacheKey);
  if (cached && now - cached.ts < OWNERSHIP_TTL_MS) {
    cached.ts = now;
    return true;
  }

  try {
    const { data, error } = await supabase
      .from('conversations')
      .select('user_id')
      .eq('id', conversationId)
      .maybeSingle();

    if (error) {
      console.error('[historyManager] Error verificando propiedad de conversación:', error.message);
      const err = new Error('Error al validar propiedad de la conversación');
      err.status = 503;
      err.code = 'DATABASE_UNAVAILABLE';
      throw err;
    }

    // Si la conversación existe y su user_id no coincide con el usuario autenticado -> 403 Forbidden
    if (data && data.user_id && data.user_id !== userId) {
      const err = new Error('No tienes permiso para acceder a esta conversación');
      err.status = 403;
      err.code = 'FORBIDDEN_CONVERSATION';
      throw err;
    }

    // Cachear solo el resultado exitoso (la conversación es del usuario o aún no existe en BD).
    if (_ownershipCache.size >= OWNERSHIP_CACHE_MAX) {
      const oldest = _ownershipCache.keys().next().value;
      if (oldest !== undefined) _ownershipCache.delete(oldest);
    }
    _ownershipCache.set(cacheKey, { ts: Date.now() });

    return true;
  } catch (err) {
    if (err.status) throw err;
    console.error('[historyManager] assertConversationOwner error:', err.message);
    const fallbackErr = new Error('Error de validación de seguridad');
    fallbackErr.status = 500;
    throw fallbackErr;
  }
}

module.exports = { getHistory, saveMessage, assertConversationOwner };

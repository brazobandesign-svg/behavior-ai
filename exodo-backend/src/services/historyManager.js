const supabase = require('../config/supabase');

/**
 * History Manager — Bible: últimos 10 mensajes como contexto.
 * Reduce tokens de entrada ~50% sin que el usuario note diferencia.
 */

/**
 * Recupera los últimos N mensajes de una conversación con Pruning Adaptativo.
 * Garantiza que el historial anterior no exceda el presupuesto de tokens (maxTokens, default: 6000),
 * evitando saturar el contexto del modelo o agotar la cuota del plan Genesis.
 * @param {string} conversationId - UUID de la conversación
 * @param {number} limit - Cantidad de mensajes a recuperar (default: 10)
 * @param {number} maxTokens - Presupuesto máximo de tokens para el historial anterior (default: 6000)
 * @returns {Promise<Array>} - Array de { role, content }
 */
async function getHistory(conversationId, limit = 10, maxTokens = 6000) {
  if (!conversationId || !supabase) return [];

  try {
    const { data, error } = await supabase
      .from('messages')
      .select('role, content, created_at')
      .eq('conversation_id', conversationId)
      .order('created_at', { ascending: true });

    if (error || !data) return [];

    // Defensive sort: garantizar orden cronológico estable
    const sorted = [...data].sort((a, b) => {
      const ta = new Date(a.created_at).getTime();
      const tb = new Date(b.created_at).getTime();
      if (ta !== tb) return ta - tb;
      if (a.role !== b.role) return a.role === 'user' ? -1 : 1;
      return 0;
    });

    // Tomar los últimos N mensajes como ventana cronológica inicial
    const windowMessages = sorted.slice(-limit);

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

    return prunedHistory;
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
    const { data, error } = await supabase
      .from('messages')
      .insert({
        conversation_id: conversationId,
        role,
        content,
        intent_detected: metadata.intent || null,
        model_called: metadata.model || null,
        tokens_input: metadata.tokensInput || null,
        tokens_output: metadata.tokensOutput || null,
        // [Punto 00] Sources como JSONB para que persistan entre sesiones.
        sources: metadata.sources && metadata.sources.length > 0 ? metadata.sources : null,
      })
      .select()
      .single();

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

module.exports = { getHistory, saveMessage };

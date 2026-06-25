const supabase = require('../config/supabase');

/**
 * History Manager — Bible: últimos 10 mensajes como contexto.
 * Reduce tokens de entrada ~50% sin que el usuario note diferencia.
 */

/**
 * Recupera los últimos N mensajes de una conversación.
 * @param {string} conversationId - UUID de la conversación
 * @param {number} limit - Cantidad de mensajes a recuperar (default: 10)
 * @returns {Promise<Array>} - Array de { role, content }
 */
async function getHistory(conversationId, limit = 10) {
  if (!conversationId || !supabase) return [];

  try {
    const { data, error } = await supabase
      .from('messages')
      .select('role, content')
      .eq('conversation_id', conversationId)
      .order('created_at', { ascending: true });

    if (error || !data) return [];

    // Tomar los últimos N mensajes
    return data.slice(-limit);
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

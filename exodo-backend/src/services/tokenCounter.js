const supabase = require('../config/supabase');

/**
 * Token Counter — Bible sección 07.
 * Cuenta tokens input/output y actualiza user_usage en Supabase.
 * Los tokens se cuentan por día (período diario, reseteo automático).
 */

/**
 * Estima tokens de un texto (aproximación: 1 token ≈ 4 caracteres en español).
 * Para producción se reemplazaría con tiktoken o la respuesta de uso del provider.
 */
function estimateTokens(text) {
  if (!text) return 0;
  return Math.ceil(text.length / 4);
}

/**
 * Actualiza el contador de tokens del usuario para hoy.
 * @param {string} usageId - ID del registro user_usage de hoy
 * @param {number} tokensUsed - Tokens actuales ya usados
 * @param {number} newTokens - Tokens adicionales de esta llamada (input + output)
 */
async function updateTokenUsage(usageId, tokensUsed, newTokens) {
  if (!usageId || !supabase) return;

  try {
    await supabase
      .from('user_usage')
      .update({
        tokens_used: tokensUsed + newTokens,
        updated_at: new Date().toISOString(),
      })
      .eq('id', usageId);
  } catch (err) {
    console.error('[tokenCounter] Error actualizando uso:', err.message);
  }
}

module.exports = { estimateTokens, updateTokenUsage };

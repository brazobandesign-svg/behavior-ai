const supabase = require('../config/supabase');
const { getMemUsageMap } = require('../middleware/planGuard');

/**
 * Token Counter
 * Cuenta tokens input/output y actualiza user_usage en Supabase y memoria.
 */

function estimateTokens(text) {
  if (!text) return 0;
  return Math.ceil(text.length / 4);
}

function getAstDates() {
  const now = new Date();
  const astOffset = 4 * 60 * 60 * 1000;
  const astDate = new Date(now.getTime() - astOffset);
  const currentDate = astDate.toISOString().split('T')[0];
  const currentMonth = currentDate.substring(0, 7);
  return { currentDate, currentMonth };
}

/**
 * Actualiza el contador de tokens y visión del usuario.
 */
async function updateTokenUsage(userId, newTokens, hasImage = false, currentUsage = {}) {
  if (!userId) return;

  const { currentDate, currentMonth } = getAstDates();
  const memMap = getMemUsageMap();
  let mem = memMap.get(userId);

  const tokensToAdd = Math.max(1, newTokens);
  const imagesToAdd = hasImage ? 1 : 0;

  if (mem) {
    if (mem.lastTokenReset !== currentDate) {
      mem.dailyTokensUsed = tokensToAdd;
      mem.lastTokenReset = currentDate;
    } else {
      mem.dailyTokensUsed += tokensToAdd;
    }

    if (mem.lastVisionReset !== currentMonth) {
      mem.monthlyVisionUsed = imagesToAdd;
      mem.lastVisionReset = currentMonth;
    } else {
      mem.monthlyVisionUsed += imagesToAdd;
    }
  } else {
    mem = {
      dailyTokensUsed: (currentUsage.dailyTokensUsed || 0) + tokensToAdd,
      dailyTokensLimit: currentUsage.dailyTokensLimit || 6000,
      monthlyVisionUsed: (currentUsage.monthlyVisionUsed || 0) + imagesToAdd,
      monthlyVisionLimit: currentUsage.monthlyVisionLimit || 3,
      lastTokenReset: currentDate,
      lastVisionReset: currentMonth,
    };
    memMap.set(userId, mem);
  }

  // 2. Actualizar en Supabase
  if (!supabase) return;

  // C7: incremento ATÓMICO en SQL (RPC increment_user_usage). Antes se
  // sobrescribía el total con el valor en memoria → lost-updates entre
  // requests concurrentes y entre réplicas, y pérdida del delta en restarts.
  try {
    const { error } = await supabase.rpc('increment_user_usage', {
      p_user_id: userId,
      p_tokens: Math.max(1, Math.round(newTokens)),
      p_images: imagesToAdd,
    });
    if (error) throw new Error(error.message);
  } catch (err) {
    console.error('[tokenCounter] RPC atómica falló, usando fallback legado:', err.message);
    try {
      const updatePayload = {
        tokens_used: mem.dailyTokensUsed,
        images_used: mem.monthlyVisionUsed,
        period: currentDate,
        updated_at: new Date().toISOString(),
      };
      await supabase.from('user_usage').update(updatePayload).eq('user_id', userId);
    } catch (err2) {
      console.error('[tokenCounter] Error actualizando uso en DB:', err2.message);
    }
  }
}

module.exports = { estimateTokens, updateTokenUsage };

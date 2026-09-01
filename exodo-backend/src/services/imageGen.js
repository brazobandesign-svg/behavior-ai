'use strict';

/**
 * src/services/imageGen.js
 *
 * Generación de imágenes con Alibaba Cloud DashScope (Free Tier activo):
 *   - Primario: wan2.2-t2i-flash (Ultra Rápido, ~8s)
 *   - Fallback 1: wan2.1-t2i-turbo (Alta Velocidad, ~8s)
 *   - Fallback 2: wan2.2-t2i-plus (Máxima Calidad, ~12s)
 *   - Fallback 3: wan2.1-t2i-plus (Alta Calidad, ~12s)
 *   - Fallback 4: qwen-image (Equilibrado, ~5s)
 *   - Fallback 5: qwen-image-plus (Detalle Fino, ~5.6s)
 */

const { ALIBABA_CONFIG } = require('../config/models');

const IMAGE_GEN_URL = 'https://dashscope-intl.aliyuncs.com/api/v1/services/aigc/text2image/image-synthesis';
const TASKS_URL = 'https://dashscope-intl.aliyuncs.com/api/v1/tasks/';

// 30-ago: verificado contra el Free Tier REAL del dueño. El único modelo
// de generación de imagen con cuota es wan2.2-kf2v-flash (50 llamadas
// TOTALES, expira 2026-10-24). Los qwen-image* NO están habilitados y
// devolvían 400/404 silenciosos.
const ACTIVE_IMAGE_MODELS = [
  ALIBABA_CONFIG.models.imageModel || 'wan2.2-kf2v-flash',
];

function getApiKey() {
  return process.env.DASHSCOPE_API_KEY ||
         process.env.ALIBABA_API_KEY ||
         process.env.ALIBABA_FREE_KEY ||
         ALIBABA_CONFIG.apiKey;
}

/**
 * Espera a que una tarea asíncrona de DashScope se complete.
 */
async function pollTask(taskId, apiKey, maxAttempts = 30, intervalMs = 2000) {
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    await new Promise((resolve) => setTimeout(resolve, intervalMs));

    const res = await fetch(`${TASKS_URL}${taskId}`, {
      headers: {
        Authorization: `Bearer ${apiKey}`,
      },
    });

    if (!res.ok) continue;

    const data = await res.json();
    const status = data?.output?.task_status;

    if (status === 'SUCCEEDED') {
      const results = data?.output?.results;
      if (Array.isArray(results) && results.length > 0) {
        return results[0].url;
      }
      return data?.output?.url || null;
    }

    if (status === 'FAILED' || status === 'CANCELED') {
      throw new Error(`Generación de imagen falló con estado: ${status} (${data?.output?.message || ''})`);
    }
  }

  throw new Error('Tiempo de espera agotado generando imagen');
}

/**
 * Genera una imagen a partir de un prompt de texto.
 *
 * @param {string} prompt Prompt descriptivo de la imagen.
 * @param {object} [options]
 * @param {string} [options.size='1024*1024'] Tamaño de la imagen ('1024*1024', '720*1280', '1280*720')
 * @param {string} [options.model] Modelo específico opcional
 * @returns {Promise<{ url: string, model: string }>}
 */
async function generateImage(prompt, options = {}) {
  const cleanPrompt = String(prompt || '').trim();
  if (!cleanPrompt) {
    throw new Error('El prompt no puede estar vacío');
  }

  const apiKey = getApiKey();
  if (!apiKey) {
    throw new Error('DASHSCOPE_API_KEY no configurada');
  }

  const size = options.size || '1024*1024';
  const models = options.model ? [options.model, ...ACTIVE_IMAGE_MODELS.filter(m => m !== options.model)] : ACTIVE_IMAGE_MODELS;

  let lastError = null;

  for (let i = 0; i < models.length; i++) {
    const model = models[i];
    try {
      const res = await fetch(IMAGE_GEN_URL, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
          'X-DashScope-Async': 'enable',
        },
        body: JSON.stringify({
          model,
          input: {
            prompt: cleanPrompt,
          },
          parameters: {
            size,
            n: 1,
          },
        }),
      });

      if (!res.ok) {
        const errText = await res.text();
        throw new Error(`DashScope API error (${res.status}): ${errText}`);
      }

      const data = await res.json();
      const taskId = data?.output?.task_id;

      if (taskId) {
        const imageUrl = await pollTask(taskId, apiKey);
        if (imageUrl) {
          return { url: imageUrl, model };
        }
      }

      // Si la respuesta fue síncrona
      const directUrl = data?.output?.results?.[0]?.url || data?.output?.url;
      if (directUrl) {
        return { url: directUrl, model };
      }
    } catch (err) {
      console.warn(`[imageGen] Fallo con modelo ${model}: ${err.message}`);
      lastError = err;
    }
  }

  throw lastError || new Error('No se pudo generar la imagen con ningún modelo');
}

module.exports = {
  generateImage,
  ACTIVE_IMAGE_MODELS,
  PRIMARY_MODEL: ACTIVE_IMAGE_MODELS[0],
  FALLBACK_1: ACTIVE_IMAGE_MODELS[1],
  FALLBACK_2: ACTIVE_IMAGE_MODELS[2],
};

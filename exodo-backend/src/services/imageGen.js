'use strict';

/**
 * src/services/imageGen.js
 *
 * Generación de imágenes con Alibaba Cloud DashScope:
 *   - Primario: qwen-image-3.0-pro
 *   - Fallback 1: qwen-image-2.0-pro
 *   - Fallback 2: wan2.7-image-pro (o wan2.2-t2i-plus)
 */

const { ALIBABA_CONFIG } = require('../config/models');

const IMAGE_GEN_URL = 'https://dashscope-intl.aliyuncs.com/api/v1/services/aigc/text2image/image-synthesis';
const TASKS_URL = 'https://dashscope-intl.aliyuncs.com/api/v1/tasks/';

const PRIMARY_MODEL = ALIBABA_CONFIG.models.imageModel || 'qwen-image-3.0-pro';
const FALLBACK_1 = ALIBABA_CONFIG.models.imageFallback1 || 'qwen-image-2.0-pro';
const FALLBACK_2 = ALIBABA_CONFIG.models.imageFallback2 || 'wan2.7-image-pro';

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
  const models = [PRIMARY_MODEL, FALLBACK_1, FALLBACK_2];

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
  PRIMARY_MODEL,
  FALLBACK_1,
  FALLBACK_2,
};

'use strict';

/**
 * src/services/ttsService.js
 *
 * Servicio Text-to-Speech con Alibaba Cloud CosyVoice (`cosyvoice-v3-plus`).
 * Fallback: `cosyvoice-v3-flash`.
 *
 * Endpoint nativo DashScope International Model Studio:
 * https://dashscope-intl.aliyuncs.com/api/v1/services/aigc/text2speech/synthesis
 */

const { ALIBABA_CONFIG } = require('../config/models');

const TTS_MODEL = ALIBABA_CONFIG.models.ttsModel || 'cosyvoice-v3-plus';
const TTS_FALLBACK_MODEL = ALIBABA_CONFIG.models.ttsFallback || 'cosyvoice-v3-flash';
const DASHSCOPE_TTS_URL = 'https://dashscope-intl.aliyuncs.com/api/v1/services/aigc/text2speech/synthesis';

function getApiKey() {
  return process.env.DASHSCOPE_API_KEY ||
         process.env.ALIBABA_API_KEY ||
         process.env.ALIBABA_FREE_KEY ||
         ALIBABA_CONFIG.apiKey;
}

const DEFAULT_TTS_VOICE = 'longwan';
const MAX_TTS_CHARS = 500;

/**
 * Recorta el texto a un tamaño seguro para DashScope, evitando rechazos
 * o paradas por payloads demasiado largos.
 */
function truncateForTts(text) {
  if (!text) return '';
  if (text.length <= MAX_TTS_CHARS) return text;
  const cut = text.slice(0, MAX_TTS_CHARS);
  const lastSpace = cut.lastIndexOf(' ');
  const lastPunct = Math.max(
    cut.lastIndexOf('.'),
    cut.lastIndexOf('?'),
    cut.lastIndexOf('!'),
    cut.lastIndexOf('\n'),
  );
  const boundary = Math.max(lastSpace, lastPunct);
  return boundary > 40 ? cut.slice(0, boundary).trim() : cut.trim();
}

/**
 * Devuelve una voz válida de CosyVoice. Si el valor parece un nombre de
 * modelo (contiene 'cosyvoice') o está vacío, devuelve la voz por defecto.
 */
function sanitizeVoice(voice) {
  const v = String(voice || '').trim();
  if (!v || /cosyvoice/i.test(v)) return DEFAULT_TTS_VOICE;
  return v;
}

/**
 * Sintetiza texto a audio MP3 usando CosyVoice v3.
 *
 * @param {string} text Texto a sintetizar
 * @param {object} [options]
 * @param {string} [options.voice] Voz (default: 'longwan')
 * @param {string} [options.format] Formato ('mp3' | 'wav')
 * @returns {Promise<{ buffer: Buffer, format: string, contentType: string }>}
 */
async function synthesizeSpeech(text, options = {}) {
  const cleanText = truncateForTts(String(text || '').trim());
  if (!cleanText) {
    throw new Error('El texto para síntesis de voz no puede estar vacío');
  }

  const apiKey = getApiKey();
  if (!apiKey) {
    throw new Error('DASHSCOPE_API_KEY / ALIBABA_API_KEY no configurada');
  }

  const voice = sanitizeVoice(options.voice);
  const format = options.format === 'wav' ? 'wav' : 'mp3';

  // 1. Intentar con modelo primario cosyvoice-v3-plus y luego fallback cosyvoice-v3-flash
  const modelsToTry = [TTS_MODEL, TTS_FALLBACK_MODEL];
  let lastError = null;

  for (let i = 0; i < modelsToTry.length; i++) {
    const model = modelsToTry[i];
    try {
      const response = await fetch(DASHSCOPE_TTS_URL, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model,
          input: {
            text: cleanText,
          },
          parameters: {
            voice,
            format,
            sample_rate: 22050,
          },
        }),
      });

      if (response.ok) {
        // DashScope puede devolver audio binario directamente o payload JSON
        const contentType = (response.headers.get('content-type') || '').toLowerCase();
        if (contentType.includes('audio/') || contentType.includes('application/octet-stream')) {
          const arrayBuffer = await response.arrayBuffer();
          return {
            buffer: Buffer.from(arrayBuffer),
            format,
            contentType: format === 'wav' ? 'audio/wav' : 'audio/mpeg',
            model,
          };
        }

        // Si devuelve JSON con audio (URL o base64)
        const data = await response.json();
        const out = data?.output?.audio ?? data?.output?.audio_url ?? data?.output?.url;
        if (typeof out === 'string' && /^https?:\/\//i.test(out)) {
          const audioRes = await fetch(out);
          if (audioRes.ok) {
            const arrayBuffer = await audioRes.arrayBuffer();
            return {
              buffer: Buffer.from(arrayBuffer),
              format,
              contentType: format === 'wav' ? 'audio/wav' : 'audio/mpeg',
              model,
            };
          }
        } else if (typeof out === 'string' && out.length > 0) {
          return {
            buffer: Buffer.from(out, 'base64'),
            format,
            contentType: format === 'wav' ? 'audio/wav' : 'audio/mpeg',
            model,
          };
        } else if (out && typeof out === 'object') {
          const url = out.url || out.audio_url;
          const b64 = out.data || out.b64 || out.audio;
          if (typeof url === 'string' && url) {
            const audioRes = await fetch(url);
            if (audioRes.ok) {
              const arrayBuffer = await audioRes.arrayBuffer();
              return {
                buffer: Buffer.from(arrayBuffer),
                format,
                contentType: format === 'wav' ? 'audio/wav' : 'audio/mpeg',
                model,
              };
            }
          } else if (typeof b64 === 'string' && b64.length > 0) {
            return {
              buffer: Buffer.from(b64, 'base64'),
              format,
              contentType: format === 'wav' ? 'audio/wav' : 'audio/mpeg',
              model,
            };
          }
        }
      } else {
        const errBody = await response.text();
        console.warn(`[ttsService] Intento con ${model} falló (HTTP ${response.status}): ${errBody}`);
        lastError = new Error(`DashScope TTS HTTP ${response.status}: ${errBody}`);
      }
    } catch (err) {
      console.warn(`[ttsService] Intento con ${model} falló: ${err.message}`);
      lastError = err;
    }
  }

  throw lastError || new Error('Todos los motores TTS de CosyVoice fallaron');
}

module.exports = {
  synthesizeSpeech,
  TTS_MODEL,
  TTS_FALLBACK_MODEL,
};

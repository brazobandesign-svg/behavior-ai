'use strict';

/**
 * src/routes/voice.js
 *
 * Endpoints de audio y voz:
 *   - POST /api/voice/transcribe (STT: Groq Whisper Large V3 -> Fallback Alibaba fun-asr-flash)
 *   - POST /api/voice/tts        (TTS: Alibaba CosyVoice v3 Plus -> Fallback CosyVoice Flash)
 */

const express = require('express');
const multer = require('multer');
const { chatRateLimiter } = require('../middleware/rateLimiter');
const { synthesizeSpeech } = require('../services/ttsService');
const { ALIBABA_CONFIG } = require('../config/models');

const router = express.Router();

const GROQ_API_URL = 'https://api.groq.com/openai/v1/audio/transcriptions';
const GROQ_WHISPER_MODEL = 'whisper-large-v3-turbo';
const ALIBABA_ASR_URL = 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1/audio/transcriptions';
const ALIBABA_ASR_MODEL = ALIBABA_CONFIG.models.sttModel || 'fun-asr-flash-2026-06-15';
const ALIBABA_ASR_FALLBACK = ALIBABA_CONFIG.models.sttFallback || 'qwen-audio-3.0-asr-flash';

const MAX_AUDIO_BYTES = 25 * 1024 * 1024; // 25 MB

const DOMINICAN_PROMPT =
  'Transcripción en español dominicano y caribeño, términos técnicos y educativos.';

const ALLOWED_MIME = new Set([
  'audio/m4a',
  'audio/mp4',
  'audio/x-m4a',
  'audio/wav',
  'audio/wave',
  'audio/x-wav',
  'audio/mpeg',
  'audio/mp3',
  'audio/webm',
  'audio/ogg',
]);

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: MAX_AUDIO_BYTES,
    files: 1,
  },
  fileFilter: (req, file, cb) => {
    const mime = (file.mimetype || '').toLowerCase().split(';')[0].trim();
    if (ALLOWED_MIME.has(mime)) {
      cb(null, true);
    } else {
      cb(new MulterMimeError(mime));
    }
  },
});

class MulterMimeError extends Error {
  constructor(mime) {
    super(`unsupported_media_type: ${mime || 'unknown'}`);
    this.code = 'UNSUPPORTED_MEDIA_TYPE';
    this.receivedMime = mime;
  }
}

class AudioTooLargeError extends Error {
  constructor() {
    super('audio_too_large');
    this.code = 'AUDIO_TOO_LARGE';
  }
}

function extensionForMime(mime) {
  if (!mime) return 'm4a';
  const m = mime.toLowerCase().split(';')[0].trim();
  switch (m) {
    case 'audio/wav':
    case 'audio/wave':
    case 'audio/x-wav':
      return 'wav';
    case 'audio/mpeg':
    case 'audio/mp3':
      return 'mp3';
    case 'audio/webm':
      return 'webm';
    case 'audio/ogg':
      return 'ogg';
    case 'audio/m4a':
    case 'audio/mp4':
    case 'audio/x-m4a':
    default:
      return 'm4a';
  }
}

function buildMultipartBody({ buffer, mime, filename, model = GROQ_WHISPER_MODEL }) {
  const boundary = `----ExodoBoundary${Date.now().toString(16)}${Math.random().toString(16).slice(2, 10)}`;
  const ext = extensionForMime(mime);
  const safeName = filename && filename.length < 100 ? filename : `clip.${ext}`;

  const enc = new TextEncoder();
  const headParts = [
    `--${boundary}\r\n`,
    `Content-Disposition: form-data; name="file"; filename="${safeName}"\r\n`,
    `Content-Type: ${mime || 'audio/m4a'}\r\n`,
    `\r\n`,
  ];
  const head = enc.encode(headParts.join(''));

  const tail = enc.encode(
    [
      `\r\n`,
      `--${boundary}\r\n`,
      `Content-Disposition: form-data; name="model"\r\n`,
      `\r\n`,
      `${model}\r\n`,
      `--${boundary}\r\n`,
      `Content-Disposition: form-data; name="language"\r\n`,
      `\r\n`,
      `es\r\n`,
      `--${boundary}\r\n`,
      `Content-Disposition: form-data; name="prompt"\r\n`,
      `\r\n`,
      `${DOMINICAN_PROMPT}\r\n`,
      `--${boundary}\r\n`,
      `Content-Disposition: form-data; name="response_format"\r\n`,
      `\r\n`,
      `json\r\n`,
      `--${boundary}--\r\n`,
    ].join(''),
  );

  const totalLength = head.byteLength + buffer.byteLength + tail.byteLength;
  const body = Buffer.allocUnsafe(totalLength);
  let offset = 0;
  head.copy(body, offset);
  offset += head.byteLength;
  Buffer.from(buffer).copy(body, offset);
  offset += buffer.byteLength;
  tail.copy(body, offset);

  return {
    body,
    contentType: `multipart/form-data; boundary=${boundary}`,
  };
}

function runUploadMiddleware(req, res) {
  return new Promise((resolve, reject) => {
    upload.single('file')(req, res, (err) => {
      if (!err) return resolve();
      if (err instanceof multer.MulterError) {
        if (err.code === 'LIMIT_FILE_SIZE') return reject(new AudioTooLargeError());
        return reject(err);
      }
      if (err instanceof MulterMimeError) return reject(err);
      return reject(err);
    });
  });
}

/**
 * Transcribe con Alibaba Cloud DashScope ASR
 */
async function transcribeWithAlibaba(fileBuffer, mime, filename) {
  const apiKey = process.env.DASHSCOPE_API_KEY ||
                 process.env.ALIBABA_API_KEY ||
                 process.env.ALIBABA_FREE_KEY ||
                 ALIBABA_CONFIG.apiKey;

  if (!apiKey) throw new Error('DASHSCOPE_API_KEY no configurada para ASR fallback');

  const models = [ALIBABA_ASR_MODEL, ALIBABA_ASR_FALLBACK];
  for (const model of models) {
    try {
      const { body, contentType } = buildMultipartBody({
        buffer: fileBuffer,
        mime,
        filename,
        model,
      });

      const res = await fetch(ALIBABA_ASR_URL, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': contentType,
          'Content-Length': String(body.length),
        },
        body,
      });

      if (res.ok) {
        const parsed = await res.json();
        if (parsed && typeof parsed.text === 'string') {
          return parsed.text.trim();
        }
      }
    } catch (err) {
      console.warn(`[voice] Alibaba ASR intento con ${model} falló: ${err.message}`);
    }
  }

  throw new Error('Alibaba ASR falló en todos los modelos');
}

// ---------------------------------------------------------------------------
// POST /api/voice/transcribe
// ---------------------------------------------------------------------------

router.post('/transcribe', chatRateLimiter, async (req, res, next) => {
  const startedAt = Date.now();
  try {
    try {
      await runUploadMiddleware(req, res);
    } catch (err) {
      if (err && err.code === 'UNSUPPORTED_MEDIA_TYPE') {
        return res.status(415).json({
          error: 'unsupported_media_type',
          allowed: Array.from(ALLOWED_MIME),
          received: err.receivedMime || null,
        });
      }
      if (err && err.code === 'AUDIO_TOO_LARGE') {
        return res.status(413).json({
          error: 'audio_too_large',
          max_bytes: MAX_AUDIO_BYTES,
        });
      }
      return res.status(400).json({ error: 'invalid_multipart_payload' });
    }

    if (!req.file || !req.file.buffer || req.file.buffer.length === 0) {
      return res.status(400).json({ error: 'empty_audio' });
    }

    const mime = (req.file.mimetype || 'audio/m4a').toLowerCase().split(';')[0].trim();

    // 1) Intentar Groq Whisper Large V3 (Primario)
    const groqKey = process.env.GROQ_API_KEY;
    if (groqKey) {
      try {
        const { body, contentType: multipartType } = buildMultipartBody({
          buffer: req.file.buffer,
          mime,
          filename: req.file.originalname || null,
          model: GROQ_WHISPER_MODEL,
        });

        const groqRes = await fetch(GROQ_API_URL, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${groqKey}`,
            'Content-Type': multipartType,
            'Content-Length': String(body.length),
          },
          body,
          signal: AbortSignal.timeout(10000), // 10s timeout
        });

        if (groqRes.ok) {
          const parsed = await groqRes.json();
          const text = typeof parsed.text === 'string' ? parsed.text.trim() : '';
          const elapsedMs = Date.now() - startedAt;
          console.log(`[voice] Groq transcribe OK: ${text.length} chars en ${elapsedMs}ms`);
          return res.status(200).json({ text, provider: 'groq' });
        }
      } catch (groqErr) {
        console.warn(`[voice] Groq falló o timeout (${groqErr.message}), pasando a Alibaba ASR...`);
      }
    }

    // 2) Fallback a Alibaba Cloud DashScope ASR
    try {
      const text = await transcribeWithAlibaba(req.file.buffer, mime, req.file.originalname);
      const elapsedMs = Date.now() - startedAt;
      console.log(`[voice] Alibaba ASR transcribe OK: ${text.length} chars en ${elapsedMs}ms`);
      return res.status(200).json({ text, provider: 'alibaba' });
    } catch (aliErr) {
      console.error(`[voice] Todos los proveedores de transcripción fallaron: ${aliErr.message}`);
      return res.status(502).json({ error: 'voice_transcription_failed' });
    }
  } catch (err) {
    return next(err);
  }
});

// ---------------------------------------------------------------------------
// POST /api/voice/tts
// ---------------------------------------------------------------------------

router.post('/tts', chatRateLimiter, async (req, res, next) => {
  try {
    const { text, voice, format } = req.body || {};
    if (!text || typeof text !== 'string' || !text.trim()) {
      return res.status(400).json({ error: 'El campo "text" es requerido' });
    }

    const audio = await synthesizeSpeech(text, { voice, format });
    res.setHeader('Content-Type', audio.contentType);
    res.setHeader('Content-Length', String(audio.buffer.length));
    res.setHeader('Cache-Control', 'public, max-age=86400');
    return res.status(200).send(audio.buffer);
  } catch (err) {
    console.error('[voice] TTS error:', err.message);
    return res.status(500).json({ error: 'tts_generation_failed', message: err.message });
  }
});

module.exports = router;

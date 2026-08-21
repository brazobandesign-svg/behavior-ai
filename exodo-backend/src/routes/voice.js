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
const { OpenAI, toFile } = require('openai');

const router = express.Router();

const GROQ_WHISPER_MODEL = 'whisper-large-v3-turbo';
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
  'application/octet-stream',
]);

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: MAX_AUDIO_BYTES,
    files: 1,
  },
  fileFilter: (req, file, cb) => {
    const mime = (file.mimetype || '').toLowerCase().split(';')[0].trim();
    if (ALLOWED_MIME.has(mime) || mime.startsWith('audio/')) {
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
    const ext = extensionForMime(mime);
    const filename = req.file.originalname && req.file.originalname.includes('.')
      ? req.file.originalname
      : `clip.${ext}`;

    const groqKey = process.env.GROQ_API_KEY;
    if (!groqKey) {
      return res.status(500).json({ error: 'groq_api_key_missing' });
    }

    const client = new OpenAI({
      apiKey: groqKey,
      baseURL: 'https://api.groq.com/openai/v1',
      timeout: 10000,
    });

    const fileObj = await toFile(req.file.buffer, filename, {
      type: mime === 'application/octet-stream' ? 'audio/m4a' : mime,
    });

    const transcription = await client.audio.transcriptions.create({
      file: fileObj,
      model: GROQ_WHISPER_MODEL,
      language: 'es',
      prompt: DOMINICAN_PROMPT,
      response_format: 'json',
    });

    const text = (transcription && typeof transcription.text === 'string')
      ? transcription.text.trim()
      : '';

    const elapsedMs = Date.now() - startedAt;
    console.log(`[voice] Groq Whisper OK: ${text.length} chars en ${elapsedMs}ms`);

    return res.status(200).json({
      text: text,
      provider: 'groq',
      model: GROQ_WHISPER_MODEL,
      elapsedMs: elapsedMs,
    });
  } catch (err) {
    console.error(`[voice] Error en transcripción: ${err.message}`);
    return res.status(502).json({
      error: 'voice_transcription_failed',
      message: err.message,
    });
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

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
const auth = require('../middleware/auth');
const { synthesizeSpeech } = require('../services/ttsService');
const { OpenAI, toFile } = require('openai');

const router = express.Router();

const GROQ_WHISPER_MODEL = 'whisper-large-v3-turbo';
const MAX_AUDIO_BYTES = 25 * 1024 * 1024; // 25 MB

// ---------------------------------------------------------------------------
// Rate limit por sesión (VOZ-1): cuenta SUBIDAS LÓGICAS (seq_id único por
// usuario), no intentos HTTP — el cliente reintenta por candidato y cada
// reintento no debe consumir cuota (medido: 6 candidatos × N subidas agotaba
// 30/min en segundos).
// ---------------------------------------------------------------------------
const VOICE_RATE_LIMIT = 30;          // subidas lógicas
const VOICE_RATE_WINDOW_MS = 60_000;  // por minuto
const _voiceSeqHits = new Map(); // userId -> Map(seq -> timestamp)

function registerVoiceUpload(userId, seqId, isPartial = false) {
  if (isPartial) return true; // P1-1: Los parciales de pseudo-streaming no consumen el cupo de subidas canónicas
  const now = Date.now();
  let perUser = _voiceSeqHits.get(userId);
  if (!perUser) {
    perUser = new Map();
    _voiceSeqHits.set(userId, perUser);
  }
  for (const [seq, ts] of perUser) {
    if (now - ts >= VOICE_RATE_WINDOW_MS) perUser.delete(seq);
  }
  const key = String(seqId ?? `noseq-${now}`); // sin seq: cada petición cuenta
  if (!perUser.has(key)) perUser.set(key, now);
  if (perUser.size > VOICE_RATE_LIMIT) return false;
  // Saneo defensivo LRU (evictar entradas individuales, nunca clear total)
  if (_voiceSeqHits.size > 5000) {
    const oldestKey = _voiceSeqHits.keys().next().value;
    _voiceSeqHits.delete(oldestKey);
  }
  return true;
}

/** C9 (auditoría): los endpoints de voz requieren JWT válido — sin usuario
 *  real se rechaza con 401 (antes Whisper quedaba abierto al público). */
function requireVoiceUser(req, res, next) {
  if (!req.user || !req.user.userId) {
    return res.status(401).json({ error: 'authentication_required' });
  }
  next();
}

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

// Sin chatRateLimiter aquí: el pseudo-streaming de voz dispara ~30 subidas
// lógicas/min y agotaría el presupuesto GLOBAL del chat del usuario (medido:
// el mensaje de chat posterior fallaba con "sin conexión" tras una sesión
// de dictado larga). El abuso de voz lo frena el limitador por sesión propio.
router.post('/transcribe', auth, requireVoiceUser, async (req, res, next) => {
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

    // Rate limit por subida lógica (tras multer: seq_id ya está en req.body).
    const seqId = req.body && req.body.seq_id;
    const isPartial = req.body && req.body.mode === 'partial';
    if (!registerVoiceUpload(req.user.userId, seqId, isPartial)) {
      res.setHeader('Retry-After', Math.ceil(VOICE_RATE_WINDOW_MS / 1000));
      return res.status(429).json({ error: 'voice_rate_limited', limit: VOICE_RATE_LIMIT });
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

    const transcriptionParams = {
      file: fileObj,
      model: GROQ_WHISPER_MODEL,
      response_format: 'json',
      // VOZ-1: transcripción determinista. Nota de desviación del acta:
      // `condition_on_previous_text` NO existe en la API de Groq (400
      // "unknown param", verificado en vivo); su intención (no re-inyectar
      // contexto del modelo) queda cubierta de facto — la continuidad la
      // porta exclusivamente el `prompt` que envía el cliente.
      temperature: 0,
    };

    // Si el cliente envía un idioma explícito diferente de 'auto', respetarlo.
    // Si no se especifica o es 'auto', Whisper auto-detecta el idioma hablado (inglés, español, francés, etc.)
    // y transcribe fielmente en ese idioma sin traducir.
    if (req.body && req.body.language && req.body.language !== 'auto') {
      transcriptionParams.language = req.body.language;
    }

    // El prompt en Whisper sesga el vocabulario y el idioma esperado.
    // Solo inyectar prompt dominicano si se pide explícitamente español, o si el cliente envía un prompt propio.
    // VOZ-1: el prompt viaja desde el cliente (últimas palabras consolidadas)
    // para dar continuidad entre bloques de dictado; se acota por seguridad.
    if (req.body && typeof req.body.prompt === 'string' && req.body.prompt.trim()) {
      transcriptionParams.prompt = req.body.prompt.trim().slice(0, 200);
    } else if (req.body && (req.body.language === 'es' || req.body.language === 'es-DO')) {
      transcriptionParams.prompt = DOMINICAN_PROMPT;
    }

    const transcription = await client.audio.transcriptions.create(transcriptionParams);

    let text = (transcription && typeof transcription.text === 'string')
      ? transcription.text.trim()
      : '';

    // Filtrar alucinaciones comunes de Whisper generadas en clips con silencio o ruido de fondo leve
    const SILENCE_HALLUCINATIONS = [
      /^you$/i,
      /^thank\s*you\.?$/i,
      /^thanks\s*for\s*watching\.?$/i,
      /^subt[íi]tulos\s*por.*$/i,
      /^amara\.org.*$/i,
      /^[.\s,;!?-]+$/,
    ];
    if (SILENCE_HALLUCINATIONS.some((rx) => rx.test(text))) {
      text = '';
    }

    const elapsedMs = Date.now() - startedAt;
    // P2-1: Privacidad — No loguear PII/texto de estudiantes en stdout de Railway
    console.log(`[voice] Groq Whisper OK: len=${text.length} chars (${elapsedMs}ms)`);

    return res.status(200).json({
      text: text,
      provider: 'groq',
      model: GROQ_WHISPER_MODEL,
      elapsedMs: elapsedMs,
    });
  } catch (err) {
    console.error(`[voice] Error en transcripción: ${err.message}`);
    // P2-1: Sanitizar mensaje al cliente
    return res.status(502).json({
      error: 'voice_transcription_failed',
      message: 'No se pudo procesar el audio. Por favor intenta de nuevo.',
    });
  }
});

// ---------------------------------------------------------------------------
// POST /api/voice/tts
// ---------------------------------------------------------------------------

router.post('/tts', auth, requireVoiceUser, async (req, res, next) => {
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
    return res.status(502).json({
      error: 'tts_generation_failed',
      message: 'No se pudo generar el audio de voz. Por favor intenta de nuevo.',
    });
  }
});

module.exports = router;

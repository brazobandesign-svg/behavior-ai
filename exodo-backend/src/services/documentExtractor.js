'use strict';

/**
 * ============================================================================
 * documentExtractor.js — Módulo 1: Extractor de documentos multi-formato
 * ============================================================================
 *
 * Recibe un Buffer y una pista de formato (mimeType, extensión o nombre de
 * archivo) y devuelve texto plano limpio, de forma segura y EN MEMORIA
 * (nunca escribe a disco).
 *
 * Formatos soportados: PDF, DOCX, XLSX, TXT/Markdown, CSV y JSON.
 *
 * Decisiones de diseño:
 *  - Todo en memoria: no se usa `fs`; los buffers se procesan directamente.
 *  - Errores controlados: `extractText` NUNCA lanza por defecto; devuelve un
 *    resultado estructurado. (Opcional: `throwOnError: true` lanza errores tipados).
 *  - Límites de tamaño para mitigar "ZIP bombs" / "decompression bombs".
 *  - Timeout por extractor para evitar bloqueos con documentos corruptos.
 *  - Detección de formato por mimeType → extensión → sniffing de contenido.
 */

const pdfParse = require('pdf-parse'); // Extrae texto de PDF (Buffer -> Promise)
const mammoth = require('mammoth');     // Extrae texto de .docx (extractRawText)
const XLSX = require('xlsx');           // SheetJS: lee .xlsx/.xls en memoria

// ---------------------------------------------------------------------------
// Errores tipados
// ---------------------------------------------------------------------------

class DocumentExtractorError extends Error {
  constructor(message, code, details) {
    super(message);
    this.name = 'DocumentExtractorError';
    this.code = code;
    this.details = details || null;
    if (Error.captureStackTrace) Error.captureStackTrace(this, this.constructor);
  }
}

class EmptyBufferError extends DocumentExtractorError {
  constructor() {
    super('El buffer de entrada está vacío o es nulo', 'EMPTY_BUFFER');
    this.name = 'EmptyBufferError';
  }
}

class SizeLimitError extends DocumentExtractorError {
  constructor(message, details) {
    super(message, 'SIZE_LIMIT_EXCEEDED', details);
    this.name = 'SizeLimitError';
  }
}

class UnsupportedTypeError extends DocumentExtractorError {
  constructor(hint) {
    const h = hint || 'desconocido';
    super(`Tipo de documento no soportado o no detectable: ${h}`, 'UNSUPPORTED_TYPE', { hint: h });
    this.name = 'UnsupportedTypeError';
  }
}

class ExtractionError extends DocumentExtractorError {
  constructor(format, cause, code) {
    const causeMsg = cause && cause.message ? cause.message : String(cause || '');
    const suffix = causeMsg ? `: ${causeMsg}` : '';
    super(`Error al extraer texto de ${format}${suffix}`, code || 'EXTRACTION_FAILED', {
      format,
      cause: causeMsg,
    });
    this.name = 'ExtractionError';
    this.cause = cause;
  }
}

// ---------------------------------------------------------------------------
// Constantes / límites por defecto (configurables vía `options`)
// ---------------------------------------------------------------------------

const DEFAULT_MAX_BUFFER_BYTES = 10 * 1024 * 1024; // 10 MB (límite de entrada)
const DEFAULT_MAX_EXTRACTED_CHARS = 1_000_000;     // 1 M de caracteres (límite de salida)
const DEFAULT_TIMEOUT_MS = 30_000;                 // 30 s por extractor
const DEFAULT_MAX_XLSX_CELLS = 2_000_000;          // celdas máximas por libro

const MIME_TO_FORMAT = {
  'application/pdf': 'pdf',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
  'application/vnd.ms-excel': 'xlsx',
  'text/plain': 'txt',
  'text/markdown': 'txt',
  'text/x-markdown': 'txt',
  'text/csv': 'csv',
  'application/csv': 'csv',
  'text/json': 'json',
  'application/json': 'json',
};

const EXT_TO_FORMAT = {
  '.pdf': 'pdf',
  '.docx': 'docx',
  '.xlsx': 'xlsx',
  '.xls': 'xlsx',
  '.txt': 'txt',
  '.md': 'txt',
  '.markdown': 'txt',
  '.csv': 'csv',
  '.json': 'json',
};

const DEFAULT_OPTIONS = {
  maxBufferBytes: DEFAULT_MAX_BUFFER_BYTES,
  maxExtractedChars: DEFAULT_MAX_EXTRACTED_CHARS,
  timeoutMs: DEFAULT_TIMEOUT_MS,
  maxXlsxCells: DEFAULT_MAX_XLSX_CELLS,
  throwOnError: false,
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function positiveInt(value, fallback) {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : fallback;
}

function resolveConfig(options) {
  const cfg = Object.assign({}, DEFAULT_OPTIONS, options || {});
  cfg.maxBufferBytes = positiveInt(cfg.maxBufferBytes, DEFAULT_MAX_BUFFER_BYTES);
  cfg.maxExtractedChars = positiveInt(cfg.maxExtractedChars, DEFAULT_MAX_EXTRACTED_CHARS);
  cfg.timeoutMs = positiveInt(cfg.timeoutMs, DEFAULT_TIMEOUT_MS);
  cfg.maxXlsxCells = positiveInt(cfg.maxXlsxCells, DEFAULT_MAX_XLSX_CELLS);
  return cfg;
}

function normalizeMime(mimeType) {
  if (!mimeType) return null;
  return String(mimeType).toLowerCase().split(';')[0].trim();
}

function stripBom(text) {
  if (text && text.charCodeAt(0) === 0xFEFF) return text.slice(1);
  return text;
}

function cleanText(text) {
  if (typeof text !== 'string') return '';
  return text
    .replace(/\u0000/g, '')
    .replace(/\r\n?/g, '\n')
    .replace(/[ \t]+\n/g, '\n')
    .trim();
}

function buildFailure(error) {
  return {
    ok: false,
    error: {
      name: error.name,
      code: error.code,
      message: error.message,
      details: error.details,
    },
  };
}

function buildSuccess(text, format, bytes, durationMs, truncated) {
  return {
    ok: true,
    text,
    format,
    stats: { bytes, chars: text.length, durationMs, truncated: !!truncated },
  };
}

async function withTimeout(fn, timeoutMs, format) {
  let timer;
  const timeoutPromise = new Promise((_, reject) => {
    timer = setTimeout(() => {
      reject(new ExtractionError(format, new Error(`Timeout al procesar el documento (${timeoutMs} ms)`), 'EXTRACTION_TIMEOUT'));
    }, timeoutMs);
  });

  try {
    return await Promise.race([Promise.resolve().then(fn), timeoutPromise]);
  } finally {
    clearTimeout(timer);
  }
}

// ---------------------------------------------------------------------------
// Detección de formato
// ---------------------------------------------------------------------------

function sniffFormat(buffer) {
  if (!buffer || buffer.length < 4) return null;

  // PDF: "%PDF"
  if (buffer[0] === 0x25 && buffer[1] === 0x50 && buffer[2] === 0x44 && buffer[3] === 0x46) {
    return 'pdf';
  }

  // ZIP: "PK\x03\x04" (DOCX y XLSX son archivos ZIP)
  if (buffer[0] === 0x50 && buffer[1] === 0x4b) {
    const head = buffer.toString('latin1', 0, Math.min(buffer.length, 8192));
    if (head.indexOf('word/') !== -1 || head.indexOf('word/document.xml') !== -1) return 'docx';
    if (head.indexOf('xl/') !== -1 || head.indexOf('xl/workbook.xml') !== -1) return 'xlsx';
    return null;
  }

  const s = buffer.toString('utf8', 0, Math.min(buffer.length, 64)).trim();
  if (s.startsWith('{') || s.startsWith('[')) return 'json';

  return null;
}

function detectFormat(buffer, options) {
  const opts = options || {};

  if (opts.mimeType) {
    const mime = normalizeMime(opts.mimeType);
    if (mime && MIME_TO_FORMAT[mime]) return MIME_TO_FORMAT[mime];
  }

  let ext = opts.extension;
  if (!ext && opts.filename) {
    const m = /(\.[a-zA-Z0-9]+)$/.exec(String(opts.filename));
    if (m) ext = m[1];
  }
  if (ext) {
    let key = String(ext).toLowerCase();
    if (key.charAt(0) !== '.') key = '.' + key;
    if (EXT_TO_FORMAT[key]) return EXT_TO_FORMAT[key];
  }

  return sniffFormat(buffer);
}

// ---------------------------------------------------------------------------
// Extractores por formato
// ---------------------------------------------------------------------------

async function extractPdfText(buffer) {
  const result = await pdfParse(buffer);
  return (result && typeof result.text === 'string') ? result.text : '';
}

async function extractDocxText(buffer) {
  const result = await mammoth.extractRawText({ buffer });
  return (result && typeof result.value === 'string') ? result.value : '';
}

function extractXlsxText(buffer, cfg) {
  let workbook;
  try {
    workbook = XLSX.read(buffer, { type: 'buffer', cellDates: false });
  } catch (err) {
    throw new ExtractionError('xlsx', err, 'XLSX_PARSE_FAILED');
  }

  if (!workbook || !workbook.SheetNames || workbook.SheetNames.length === 0) {
    throw new ExtractionError('xlsx', new Error('El libro no contiene hojas'), 'XLSX_EMPTY');
  }

  const parts = [];
  let totalCells = 0;

  for (const name of workbook.SheetNames) {
    const sheet = workbook.Sheets[name];
    if (!sheet) continue;

    let rows = 0;
    let cols = 0;
    if (sheet['!ref']) {
      const range = XLSX.utils.decode_range(sheet['!ref']);
      rows = range.e.r - range.s.r + 1;
      cols = range.e.c - range.s.c + 1;
    }

    totalCells += rows * cols;
    if (totalCells > cfg.maxXlsxCells) {
      throw new SizeLimitError(
        `El libro excede el límite de celdas permitido (${cfg.maxXlsxCells})`,
        { format: 'xlsx', limitCells: cfg.maxXlsxCells, actualCells: totalCells }
      );
    }

    const csv = XLSX.utils.sheet_to_csv(sheet);
    parts.push(`--- Hoja: ${name} ---\n${csv}`);
  }

  return parts.join('\n\n');
}

function extractPlainText(buffer) {
  return stripBom(buffer.toString('utf8'));
}

function extractCsvText(buffer) {
  return parseCsvToText(stripBom(buffer.toString('utf8')));
}

function parseCsvToText(csvText) {
  const rows = [];
  let row = [];
  let field = '';
  let inQuotes = false;

  for (let i = 0; i < csvText.length; i++) {
    const ch = csvText[i];

    if (inQuotes) {
      if (ch === '"') {
        if (csvText[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field += ch;
      }
    } else {
      if (ch === '"') {
        inQuotes = true;
      } else if (ch === ',') {
        row.push(field);
        field = '';
      } else if (ch === '\n') {
        row.push(field);
        rows.push(row);
        row = [];
        field = '';
      } else if (ch === '\r') {
        // ignorar \r
      } else {
        field += ch;
      }
    }
  }

  if (field !== '' || row.length > 0) {
    row.push(field);
    rows.push(row);
  }

  return rows.map((r) => r.join(' | ')).join('\n');
}

function extractJsonText(buffer) {
  const raw = stripBom(buffer.toString('utf8'));
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    throw new ExtractionError('json', err, 'INVALID_JSON');
  }
  return JSON.stringify(parsed, null, 2);
}

async function extractByFormat(format, buffer, cfg) {
  switch (format) {
    case 'pdf':
      return withTimeout(() => extractPdfText(buffer), cfg.timeoutMs, 'pdf');
    case 'docx':
      return withTimeout(() => extractDocxText(buffer), cfg.timeoutMs, 'docx');
    case 'xlsx':
      return withTimeout(() => extractXlsxText(buffer, cfg), cfg.timeoutMs, 'xlsx');
    case 'txt':
      return extractPlainText(buffer);
    case 'csv':
      return extractCsvText(buffer);
    case 'json':
      return extractJsonText(buffer);
    default:
      throw new UnsupportedTypeError(format);
  }
}

// ---------------------------------------------------------------------------
// Función principal
// ---------------------------------------------------------------------------

/**
 * Extrae texto plano limpio de un documento.
 *
 * @param {Buffer|Uint8Array} buffer Contenido del documento (en memoria).
 * @param {object} [options] Opciones:
 *   - mimeType  (string)  p. ej. 'application/pdf'
 *   - extension (string)  p. ej. '.pdf' o 'pdf'
 *   - filename  (string)  p. ej. 'reporte.pdf'
 *   - maxBufferBytes / maxExtractedChars / timeoutMs / maxXlsxCells (number)
 *   - throwOnError (boolean)
 * @returns {Promise<object>} { ok, text|error, format, stats }.
 */
async function extractText(buffer, options) {
  const cfg = resolveConfig(options);
  const startedAt = Date.now();

  try {
    if (buffer === null || buffer === undefined) {
      return buildFailure(new EmptyBufferError());
    }
    if (!Buffer.isBuffer(buffer)) {
      if (buffer instanceof Uint8Array) {
        buffer = Buffer.from(buffer);
      } else {
        return buildFailure(new DocumentExtractorError(
          'El primer argumento debe ser un Buffer o Uint8Array',
          'INVALID_BUFFER'
        ));
      }
    }
    if (buffer.length === 0) {
      return buildFailure(new EmptyBufferError());
    }

    if (buffer.length > cfg.maxBufferBytes) {
      return buildFailure(new SizeLimitError(
        `El documento excede el tamaño máximo permitido (${cfg.maxBufferBytes} bytes)`,
        { limitBytes: cfg.maxBufferBytes, actualBytes: buffer.length }
      ));
    }

    const format = detectFormat(buffer, cfg);
    if (!format) {
      return buildFailure(new UnsupportedTypeError(
        cfg.mimeType || cfg.extension || cfg.filename || 'desconocido'
      ));
    }

    let text = await extractByFormat(format, buffer, cfg);
    text = cleanText(text);

    let truncated = false;
    if (text.length > cfg.maxExtractedChars) {
      text = text.slice(0, cfg.maxExtractedChars);
      truncated = true;
    }

    return buildSuccess(text, format, buffer.length, Date.now() - startedAt, truncated);
  } catch (err) {
    const error = err instanceof DocumentExtractorError
      ? err
      : new ExtractionError('desconocido', err);

    if (cfg.throwOnError) {
      throw error;
    }
    return buildFailure(error);
  }
}

module.exports = {
  extractText,
  detectFormat,
  DocumentExtractorError,
  EmptyBufferError,
  SizeLimitError,
  UnsupportedTypeError,
  ExtractionError,
  SUPPORTED_MIME_TYPES: Object.keys(MIME_TO_FORMAT),
  SUPPORTED_EXTENSIONS: Object.keys(EXT_TO_FORMAT),
  DEFAULT_OPTIONS,
};

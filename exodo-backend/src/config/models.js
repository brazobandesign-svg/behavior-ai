// Constantes de modelos, proveedores y límites — alineado a Bible sección 04 y 05

const PLANS = {
  genesis: {
    name: 'Genesis G1.1',
    tokensPerDay: 15000,
    historyDays: 7,
    imagesPerMonth: 0,
    filesEnabled: false,
  },
  hazak: {
    name: 'Hazak J1.9',
    tokensPerDay: 150000,
    historyDays: null, // ilimitado
    imagesPerMonth: 30,
    filesEnabled: true,
  },
};

// Modelo real por intención y plan
// Genesis G1.1 -> Groq directo (qwen/qwen3.6-27b)
// Hazak XPi -> DeepSeek directo del proveedor original (o Anthropic cuando se active)
const MODEL_MAP = {
  SIMPLE: {
    genesis: 'qwen/qwen3.6-27b',
    hazak:   'deepseek-chat',
  },
  REDACCION: {
    genesis: 'qwen/qwen3.6-27b',
    hazak:   'deepseek-chat',
  },
  RAZONAMIENTO: {
    genesis: 'qwen/qwen3.6-27b',
    hazak:   'deepseek-reasoner',
  },
  DOCUMENTO: {
    genesis: 'qwen/qwen3.6-27b',
    hazak:   'deepseek-chat',
  },
  IMAGEN: {
    genesis: null,
    hazak:   null,
  },
};

// Cadena de fallback para Genesis G1.1 Free
const GENESIS_FALLBACK_CHAIN = [
  'qwen/qwen3.6-27b',
  'meta-llama/llama-4-scout-17b-16e-instruct',
  'llama-3.3-70b-versatile',
];

// Cadena de fallback para XPi / Plan Hazak Pro
const XPI_FALLBACK_CHAIN = [
  'deepseek-chat',
  'deepseek-reasoner',
];

// Mapeo modelo → proveedor para saber qué archivo de provider usar
const MODEL_TO_PROVIDER = {
  'qwen/qwen3.6-27b':                          'groq',
  'meta-llama/llama-4-scout-17b-16e-instruct': 'groq',
  'llama-3.3-70b-versatile':                   'groq',
  'gemini-2.0-flash':                          'gemini',
  'gemini-1.5-flash':                          'gemini',
  'deepseek-chat':                             'deepseek',
  'deepseek-reasoner':                         'deepseek',
  'claude-3-5-sonnet':                         'anthropic',
  'claude-3-haiku':                            'anthropic',
};

module.exports = {
  PLANS,
  MODEL_MAP,
  GENESIS_FALLBACK_CHAIN,
  XPI_FALLBACK_CHAIN,
  MODEL_TO_PROVIDER,
};

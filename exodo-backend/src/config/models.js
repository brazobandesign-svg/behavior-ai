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
// Genesis G1.1 -> Google Gemini directo (gemini-2.0-flash)
// Hazak XPi -> DeepSeek directo del proveedor original (o Anthropic cuando se active)
const MODEL_MAP = {
  SIMPLE: {
    genesis: 'gemini-2.0-flash',
    hazak:   'deepseek-chat',
  },
  REDACCION: {
    genesis: 'gemini-2.0-flash',
    hazak:   'deepseek-chat',
  },
  RAZONAMIENTO: {
    genesis: 'gemini-2.0-flash',
    hazak:   'deepseek-reasoner',
  },
  DOCUMENTO: {
    genesis: 'gemini-2.0-flash',
    hazak:   'deepseek-chat',
  },
  IMAGEN: {
    genesis: null,
    hazak:   null,
  },
};

// Cadena de fallback para Genesis G1.1 Free
const GENESIS_FALLBACK_CHAIN = [
  'gemini-2.0-flash',
  'deepseek-chat',
];

// Cadena de fallback para XPi / Plan Hazak Pro
const XPI_FALLBACK_CHAIN = [
  'deepseek-chat',
  'deepseek-reasoner',
];

// Mapeo modelo → proveedor para saber qué archivo de provider usar
const MODEL_TO_PROVIDER = {
  'gemini-2.0-flash':  'gemini',
  'gemini-1.5-flash':  'gemini',
  'deepseek-chat':     'deepseek',
  'deepseek-reasoner': 'deepseek',
  'claude-3-5-sonnet': 'anthropic',
  'claude-3-haiku':    'anthropic',
};

module.exports = {
  PLANS,
  MODEL_MAP,
  GENESIS_FALLBACK_CHAIN,
  XPI_FALLBACK_CHAIN,
  MODEL_TO_PROVIDER,
};

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
// Regla #8: en caso de duda → SIMPLE → Gemini Flash (error hacia lo barato)
const MODEL_MAP = {
  SIMPLE: {
    genesis: 'nim-nemotron-3-ultra',
    hazak:   'nim-nemotron-3-ultra',
  },
  REDACCION: {
    genesis: 'nim-nemotron-3-ultra',
    hazak:   'nim-nemotron-3-ultra',
  },
  RAZONAMIENTO: {
    genesis: 'nim-deepseek-v4-pro',
    hazak:   'nim-deepseek-v4-pro',
  },
  DOCUMENTO: {
    genesis: 'nim-kimi-2-6',
    hazak:   'nim-kimi-2-6',
  },
  IMAGEN: {
    genesis: null,
    hazak:   'flux-local',
  },
};

// Cadena de fallback en cascada (NIM primero, Ollama local al final por si NIM cae)
const GENESIS_FALLBACK_CHAIN = [
  'nim-nemotron-3-ultra',
  'nim-deepseek-v4-flash',
  'nim-deepseek-v4-pro',
  'nim-minimax-m3',
  'nim-kimi-2-6',
  'nim-glm-5-1',
  'nim-minimax-m2-7',
  'qwen2.5:7b', // Ollama Local (al final)
];

// Mapeo modelo → proveedor para saber qué archivo de provider usar
const MODEL_TO_PROVIDER = {
  'nim-nemotron-3-ultra': 'nim',
  'nim-deepseek-v4-flash': 'nim',
  'nim-deepseek-v4-pro': 'nim',
  'nim-minimax-m3': 'nim',
  'nim-kimi-2-6': 'nim',
  'nim-glm-5-1': 'nim',
  'nim-minimax-m2-7': 'nim',
  'qwen2.5:7b':         'ollama',
  'gemini-2.5-flash':   'gemini',
  'gemini-3.1-pro':     'gemini',
  'claude-sonnet-4-6':  'anthropic',
  'deepseek-v4-pro':    'deepseek',
  'groq-llama-3.3-70b': 'groq',
  'nim-llama-4':        'nim',
  'cerebras-llama-3.1': 'cerebras',
  'flux-local':         'flux',
};

module.exports = {
  PLANS,
  MODEL_MAP,
  GENESIS_FALLBACK_CHAIN,
  MODEL_TO_PROVIDER,
};

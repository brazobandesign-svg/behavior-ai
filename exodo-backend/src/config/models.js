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
    genesis: 'gemini-2.5-flash',
    hazak:   'gemini-2.5-flash',
  },
  REDACCION: {
    genesis: 'gemini-2.5-flash',
    hazak:   'claude-sonnet-4-6',
  },
  RAZONAMIENTO: {
    genesis: 'gemini-2.5-flash',
    hazak:   'deepseek-v4-pro',
  },
  DOCUMENTO: {
    genesis: 'gemini-2.5-flash',
    hazak:   'gemini-3.1-pro',
  },
  IMAGEN: {
    genesis: null, // no disponible
    hazak:   'flux-local',
  },
};

// Cadena de fallback para Genesis (4 proveedores en cascada)
const GENESIS_FALLBACK_CHAIN = [
  'gemini-2.5-flash',   // Google AI Studio (primario)
  'groq-llama-3.3-70b', // Groq (fallback 1)
  'nim-llama-4',        // NVIDIA NIM (fallback 2)
  'cerebras-llama-3.1', // Cerebras (fallback 3)
];

// Mapeo modelo → proveedor para saber qué archivo de provider usar
const MODEL_TO_PROVIDER = {
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

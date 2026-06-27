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
    genesis: 'qwen2.5:7b',
    hazak:   'qwen2.5:7b',
  },
  REDACCION: {
    genesis: 'qwen2.5:7b',
    hazak:   'qwen2.5:7b',
  },
  RAZONAMIENTO: {
    genesis: 'qwen2.5:7b',
    hazak:   'qwen2.5:7b',
  },
  DOCUMENTO: {
    genesis: 'qwen2.5:7b',
    hazak:   'qwen2.5:7b',
  },
  IMAGEN: {
    genesis: null,
    hazak:   'flux-local',
  },
};

// Cadena de fallback para Genesis (Ollama local primario)
const GENESIS_FALLBACK_CHAIN = [
  'qwen2.5:7b',         // Ollama Local (primario)
  'gemini-2.5-flash',   // Google AI Studio
  'groq-llama-3.3-70b', // Groq
  'nim-llama-4',        // NVIDIA NIM
  'cerebras-llama-3.1', // Cerebras
];

// Mapeo modelo → proveedor para saber qué archivo de provider usar
const MODEL_TO_PROVIDER = {
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

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
// Genesis G1.1 -> Mistral directo (mistral-small-2506 + pixtral para visión) y Groq en fallback
// Hazak XPi -> DeepSeek directo del proveedor original (o Anthropic cuando se active)
const MODEL_MAP = {
  SIMPLE: {
    genesis: 'mistral-small-2506',
    hazak:   'deepseek-chat',
  },
  REDACCION: {
    genesis: 'codestral-2508',
    hazak:   'deepseek-chat',
  },
  RAZONAMIENTO: {
    genesis: 'mistral-large-2512',
    hazak:   'deepseek-reasoner',
  },
  DOCUMENTO: {
    genesis: 'mistral-large-2512',
    hazak:   'deepseek-chat',
  },
  // [Fix visión] Nueva categoría determinística: se activa solo cuando
  // hay imágenes adjuntas (chat.js la fuerza, nunca depende del LLM
  // clasificador). Ambos planes apuntan a Gemini porque es el único
  // proveedor de la cascada con soporte de visión ya confirmado.
  // DeepSeek no tiene visión pública; Mistral sí (pixtral-12b-2409)
  // pero se deja Gemini como primario por ser el ya verificado.
  VISION: {
    genesis: 'gemini-2.0-flash',
    hazak:   'gemini-2.0-flash',
  },
  IMAGEN: {
    genesis: null,
    hazak:   null,
  },
};

// Cadena de fallback para Genesis G1.1 Free (orden táctico: colchón Mistral primero, luego Scout/70B/Qwen en Groq)
const GENESIS_FALLBACK_CHAIN = [
  'codestral-2508',
  'mistral-small-2506',
  'meta-llama/llama-4-scout-17b-16e-instruct',
  'llama-3.3-70b-versatile',
  'qwen/qwen3.6-27b',
];

// Cadena de fallback para XPi / Plan Hazak Pro
const XPI_FALLBACK_CHAIN = [
  'deepseek-chat',
  'deepseek-reasoner',
];

// Mapeo modelo → proveedor para saber qué archivo de provider usar
const MODEL_TO_PROVIDER = {
  'mistral-small-2506':                        'mistral',
  'codestral-2508':                            'mistral',
  'mistral-large-2512':                        'mistral',
  'devstral-2512':                             'mistral',
  'pixtral-12b-2409':                          'mistral',
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

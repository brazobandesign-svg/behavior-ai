// Constantes de modelos, proveedores y límites — Matriz Éxodo v4.2 (Clean Groq & Calibrated Limits)

const PLAN_CONFIG = {
  free: {
    name: 'Genesis G1.1',
    dailyTokensLimit: 6000,          // 6k tokens diarios de alta velocidad (DeepSeek Flash)
    maxOutputTokensNormal: 1500,     // Salida estándar natural
    monthlyVisionLimit: 3,           // Análisis de imagen al mes (Gemini Flash-Lite)
    allowThinking: false,
    // Configuración Groq (Guests y Modo Eco sin restricciones artificiales)
    ecoModel: 'llama-3.3-70b-versatile',
    ecoMaxOutputTokens: 4096,        // Extensión y capacidad natural completa
  },
  pro: {
    name: 'Hazak J1.9',
    priceUsd: 4.99,
    dailyTokensLimit: 50000,         // 50k tokens diarios (DeepSeek Pro / Reasoner)
    maxOutputTokens: 4096,
    monthlyVisionLimit: 40,          // Fotos al mes (Gemini Flash-Lite)
    allowThinking: true,
    isDegradable: false              // El plan Pro NUNCA entra a Modo Eco
  }
};

// Aliases para soportar tanto 'free'/'pro' como 'genesis'/'hazak'
PLAN_CONFIG.genesis = PLAN_CONFIG.free;
PLAN_CONFIG.hazak = PLAN_CONFIG.pro;

const PLANS = {
  genesis: {
    name: PLAN_CONFIG.free.name,
    tokensPerDay: PLAN_CONFIG.free.dailyTokensLimit,
    historyDays: 7,
    imagesPerMonth: PLAN_CONFIG.free.monthlyVisionLimit,
    filesEnabled: false,
  },
  hazak: {
    name: PLAN_CONFIG.pro.name,
    tokensPerDay: PLAN_CONFIG.pro.dailyTokensLimit,
    historyDays: null,
    imagesPerMonth: PLAN_CONFIG.pro.monthlyVisionLimit,
    filesEnabled: true,
  },
};
PLANS.free = PLANS.genesis;
PLANS.pro = PLANS.hazak;

const ECO_MODELS = {
  text:   PLAN_CONFIG.free.ecoModel,
  vision: 'qwen/qwen3.6-27b',
};

const MODEL_MAP = {
  SIMPLE: {
    genesis: 'deepseek-chat',
    hazak:   'deepseek-reasoner',
    free:    'deepseek-chat',
    pro:     'deepseek-reasoner',
  },
  REDACCION: {
    genesis: 'deepseek-chat',
    hazak:   'deepseek-reasoner',
    free:    'deepseek-chat',
    pro:     'deepseek-reasoner',
  },
  RAZONAMIENTO: {
    genesis: 'deepseek-chat',
    hazak:   'deepseek-reasoner',
    free:    'deepseek-chat',
    pro:     'deepseek-reasoner',
  },
  DOCUMENTO: {
    genesis: 'deepseek-chat',
    hazak:   'deepseek-reasoner',
    free:    'deepseek-chat',
    pro:     'deepseek-reasoner',
  },
  VISION: {
    genesis: 'gemini-flash-lite-latest',
    hazak:   'gemini-flash-lite-latest',
    free:    'gemini-flash-lite-latest',
    pro:     'gemini-flash-lite-latest',
  },
  IMAGEN: {
    genesis: null,
    hazak:   null,
    free:    null,
    pro:     null,
  },
};

const MODEL_TO_PROVIDER = {
  'deepseek-chat':             'deepseek',
  'deepseek-reasoner':         'deepseek',
  'gemini-flash-lite-latest': 'gemini',
  'llama-3.3-70b-versatile':   'groq',
  'qwen/qwen3.6-27b':          'groq',
};

module.exports = {
  PLAN_CONFIG,
  PLANS,
  MODEL_MAP,
  ECO_MODELS,
  MODEL_TO_PROVIDER,
};

// Constantes de modelos, proveedores y límites — Matriz Éxodo DashScope Free Tier (1M tokens)

const ALIBABA_CONFIG = {
  baseURL: process.env.ALIBABA_BASE_URL || 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
  // FIX (2026-08-20): había una key hardcodeada de respaldo aquí. Estaba
  // INVALIDADA (DashScope respondía 401 "Invalid API-key") y enmascaraba los
  // arranques sin .env (dotenv inyecta 0 vars si el CWD no es la raíz del
  // backend): toda la cadena de modelos fallaba con 401s confusos en lugar de
  // un "apiKey is required" evidente. Sin key en env, el check de arranque de
  // index.js avisa y el SDK de OpenAI falla ruidosamente en el primer request.
  apiKey: process.env.DASHSCOPE_API_KEY || process.env.ALIBABA_API_KEY || process.env.ALIBABA_FREE_KEY,
  models: {
    // Hazak (Pro / Reasoner)
    hazakPrimary: 'qwen3.7-max-2026-06-08',
    hazakReasoner: 'qwen3-235b-a22b-thinking-2507',
    hazakVision: 'qwen-vl-max',
    hazakFallback: 'deepseek-v3.2',
    hazakReasonerFallback: 'qwq-plus',
    hazakVisionFallback: 'qwen3.5-omni-plus',

    // Genesis (Free / Fast)
    genesisSimple: 'qwen3.7-flash',
    genesisRedaccion: 'qwen3.6-plus',
    genesisReasoner: 'qwen3.7-flash',
    genesisVision: 'qwen3-vl-plus',
    genesisSimpleFallback: 'qwen3.6-plus',
    genesisRedaccionFallback: 'qwen3.5-plus',
    genesisReasonerFallback: 'qwen3.6-27b',
    genesisVisionFallback: 'qwen-vl-max',

    // Audio & Image models
    sttModel: 'fun-asr-flash-2026-06-15',
    sttFallback: 'qwen-audio-3.0-asr-flash',
    ttsModel: 'cosyvoice-v3-plus',
    ttsFallback: 'cosyvoice-v3-flash',
    imageModel: 'qwen-image-3.0-pro',
    imageFallback1: 'qwen-image-2.0-pro',
    imageFallback2: 'wan2.7-image-pro',
    embeddingModel: 'text-embedding-v4',
    rerankModel: 'qwen3-rerank',
  },
};

const PLAN_CONFIG = {
  free: {
    name: 'Genesis G1.1',
    dailyTokensLimit: 1000000,        // 1M tokens diarios activos
    maxOutputTokensNormal: 4096,
    monthlyVisionLimit: 1000,
    allowThinking: true,
    primaryModel: 'qwen3.7-flash',
    fallbackChain: [
      'qwen3.6-plus',
      'qwen3.5-plus',
      'qwen3.7-flash',
      'qwen3.6-27b',
      'qwen3.7-plus',
    ],
    visionModels: ['qwen3-vl-plus', 'qwen-vl-max', 'qwen3.7-plus'],
    isDegradable: false,
  },
  pro: {
    name: 'Hazak J1.9',
    priceUsd: 4.99,
    dailyTokensLimit: 1000000,        // 1M tokens diarios activos
    maxOutputTokens: 8192,
    monthlyVisionLimit: 2000,
    allowThinking: true,
    primaryModel: 'qwen3.7-max-2026-06-08',
    fallbackChain: [
      'qwen3-235b-a22b-thinking-2507',
      'deepseek-v3.2',
      'qwq-plus',
      'qwen3.7-plus',
      'deepseek-v4-pro',
    ],
    visionModels: ['qwen-vl-max', 'qwen3.5-omni-plus', 'qwen3.7-plus'],
    isDegradable: false,
  },
};

// Aliases
PLAN_CONFIG.genesis = PLAN_CONFIG.free;
PLAN_CONFIG.hazak = PLAN_CONFIG.pro;

const PLANS = {
  genesis: {
    name: PLAN_CONFIG.free.name,
    tokensPerDay: PLAN_CONFIG.free.dailyTokensLimit,
    historyDays: 30,
    imagesPerMonth: PLAN_CONFIG.free.monthlyVisionLimit,
    filesEnabled: true,
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
  text:   'qwen3.7-flash',
  vision: 'qwen3-vl-plus',
};

const MODEL_MAP = {
  SIMPLE: {
    genesis: 'qwen3.7-flash',
    hazak:   'qwen3.7-max-2026-06-08',
    free:    'qwen3.7-flash',
    pro:     'qwen3.7-max-2026-06-08',
  },
  REDACCION: {
    genesis: 'qwen3.6-plus',
    hazak:   'qwen3.7-max-2026-06-08',
    free:    'qwen3.6-plus',
    pro:     'qwen3.7-max-2026-06-08',
  },
  RAZONAMIENTO: {
    genesis: 'qwen3.7-flash',
    hazak:   'qwen3-235b-a22b-thinking-2507',
    free:    'qwen3.7-flash',
    pro:     'qwen3-235b-a22b-thinking-2507',
  },
  DOCUMENTO: {
    genesis: 'qwen3.6-plus',
    hazak:   'qwen3.7-max-2026-06-08',
    free:    'qwen3.6-plus',
    pro:     'qwen3.7-max-2026-06-08',
  },
  VISION: {
    genesis: 'qwen3-vl-plus',
    hazak:   'qwen-vl-max',
    free:    'qwen3-vl-plus',
    pro:     'qwen-vl-max',
  },
  IMAGEN: {
    genesis: null,
    hazak:   'qwen-image-3.0-pro',
    free:    null,
    pro:     'qwen-image-3.0-pro',
  },
};

const MODEL_TO_PROVIDER = {
  // DashScope Qwen / DeepSeek Models
  'qwen3.7-max-2026-06-08':         'alibaba',
  'qwen3-235b-a22b-thinking-2507':  'alibaba',
  'qwen-vl-max':                    'alibaba',
  'qwen3.5-omni-plus':              'alibaba',
  'deepseek-v3.2':                  'alibaba',
  'qwq-plus':                       'alibaba',
  'qwen3.7-flash':                  'alibaba',
  'qwen3.6-plus':                   'alibaba',
  'qwen3.5-plus':                   'alibaba',
  'qwen3.6-27b':                    'alibaba',
  'qwen3-vl-plus':                  'alibaba',
  'qwen3.7-plus':                   'alibaba',
  'qwen3-coder-480b-a35b-instruct': 'alibaba',
  'deepseek-v4-pro':                'alibaba',
  'deepseek-v4-flash':              'alibaba',
  'deepseek-chat':                  'alibaba',
  'deepseek-reasoner':              'alibaba',
};

module.exports = {
  ALIBABA_CONFIG,
  PLAN_CONFIG,
  PLANS,
  MODEL_MAP,
  ECO_MODELS,
  MODEL_TO_PROVIDER,
};

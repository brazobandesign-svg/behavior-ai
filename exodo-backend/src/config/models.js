// Constantes de modelos, proveedores y límites — Matriz Éxodo DashScope Free Tier (1M tokens)

const ALIBABA_CONFIG = {
  baseURL: process.env.ALIBABA_BASE_URL || 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
  apiKey: process.env.DASHSCOPE_API_KEY || process.env.ALIBABA_API_KEY || process.env.ALIBABA_FREE_KEY,
  models: {
    // DOCTRINA (humano, 25-08): Kimi K3 y Qwen 3.7 Max RESERVADOS para Copilot (chatLanguageModels.json).
    // Flagship = qwen3.6-max-preview.
    textPrimary: 'qwen3.6-max-preview',       // Texto, conversación, redacción y asistencia general
    fastPrimary: 'qwen3.7-flash-2026-07-15',     // Conversación instantánea (<200ms TTFT) para saludos y mensajes simples
    textFallback: 'qwen3.6-plus-2026-04-02',     // Respaldo de alta elocuencia
    reasonerPrimary: 'qwq-plus',                 // Razonamiento lógico profundo y matemáticas
    coderPrimary: 'qwen3-coder-plus-2025-07-22', // Generación de código y artefactos interactivos
    visionPrimary: 'qwen-vl-max',                // Análisis de imágenes, visión multimodal y OCR
    agenticLongContext: 'glm-5.1',               // Agéntico/review largo

    // RAG MINERD y Embeddings
    embeddingModel: 'text-embedding-v4',
    rerankModel: 'qwen3-rerank',

    // Modelos de Generación de Imágenes (DashScope Free Tier)
    imageModel: 'wan2.2-t2i-flash',              // Primario: Wanx 2.2 Flash (rápido, ~8s)
    imageFallback1: 'wan2.1-t2i-turbo',          // Respaldo 1: Wanx 2.1 Turbo (~8s)
    imageFallback2: 'wan2.2-t2i-plus',           // Respaldo 2: Wanx 2.2 Plus (máxima calidad, ~12s)
    imageFallback3: 'wan2.1-t2i-plus',           // Respaldo 3: Wanx 2.1 Plus (~12s)
    imageFallback4: 'qwen-image',                // Respaldo 4: Qwen Image (~5s)
    imageFallback5: 'qwen-image-plus',           // Respaldo 5: Qwen Image Plus (~5.6s)

    // Compatibilidad de nombres
    hazakPrimary: 'qwen3.6-max-preview',
    hazakReasoner: 'qwq-plus',
    hazakCoder: 'qwen3-coder-plus-2025-07-22',
    hazakVision: 'qwen-vl-max',
    genesisSimple: 'qwen3.7-flash-2026-07-15',
    genesisRedaccion: 'qwen3.6-max-preview',
    genesisReasoner: 'qwq-plus',
    genesisCoder: 'qwen3-coder-plus-2025-07-22',
    genesisVision: 'qwen-vl-max',
  },
};

const PLAN_CONFIG = {
  free: {
    name: 'G1.1',
    dailyTokensLimit: 6000,           // 6,000 tokens diarios (lo que promete la UI)
    maxOutputTokensNormal: 8192,
    monthlyVisionLimit: 1000,
    dailyImagesLimit: 3,              // G1.1: pocas imágenes al día
    allowThinking: true,
    primaryModel: 'qwen3.6-max-preview',
    fallbackChain: [
      'qwen3.6-max-preview',
    ],
    visionModels: ['qwen-vl-max'],
    isDegradable: false,
  },
  pro: {
    name: 'XPi',
    priceUsd: 4.99,
    dailyTokensLimit: 50000,          // 50,000 tokens diarios (lo que promete la UI)
    maxOutputTokens: 8192,
    monthlyVisionLimit: 2000,
    dailyImagesLimit: 25,             // XPi: 25 imágenes/día (antes 66/mes implícito)
    allowThinking: true,
    primaryModel: 'qwen3.6-max-preview',
    fallbackChain: [
      'qwen3.6-max-preview',
    ],
    visionModels: ['qwen-vl-max'],
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
    hazak:   'qwen3.6-max-preview',
    free:    'qwen3.7-flash',
    pro:     'qwen3.6-max-preview',
  },
  REDACCION: {
    genesis: 'qwen3.6-plus',
    hazak:   'qwen3.6-max-preview',
    free:    'qwen3.6-plus',
    pro:     'qwen3.6-max-preview',
  },
  RAZONAMIENTO: {
    genesis: 'qwen3.7-flash',
    hazak:   'qwq-plus',
    free:    'qwen3.7-flash',
    pro:     'qwq-plus',
  },
  DOCUMENTO: {
    genesis: 'qwen3.6-plus',
    hazak:   'qwen3.6-max-preview',
    free:    'qwen3.6-plus',
    pro:     'qwen3.6-max-preview',
  },
  VISION: {
    genesis: 'qwen3-vl-plus',
    hazak:   'qwen-vl-max',
    free:    'qwen3-vl-plus',
    pro:     'qwen-vl-max',
  },
  IMAGEN: {
    genesis: 'wan2.2-t2i-flash',
    hazak:   'wan2.2-t2i-plus',
    free:    'wan2.2-t2i-flash',
    pro:     'wan2.2-t2i-plus',
  },
};

const MODEL_TO_PROVIDER = {
  // DashScope Qwen / DeepSeek Models
  'qwen3.6-max-preview':         'alibaba',
  'qwq-plus':                       'alibaba',
  'qwen-vl-max':                    'alibaba',
  'qwen3.5-omni-plus':              'alibaba',
  'deepseek-v3.2':                  'alibaba',
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
  'kimi-k3':                        'alibaba',
  'kimi-k3-1m':                     'alibaba',
  'moonshot-v1-1m':                 'alibaba',
  'moonshot-v1-128k':               'alibaba',
  // DashScope Image Models
  'wan2.2-t2i-flash':               'alibaba',
  'wan2.2-t2i-plus':                'alibaba',
  'wan2.1-t2i-turbo':               'alibaba',
  'wan2.1-t2i-plus':                'alibaba',
  'qwen-image':                     'alibaba',
  'qwen-image-plus':                'alibaba',
};

module.exports = {
  ALIBABA_CONFIG,
  PLAN_CONFIG,
  PLANS,
  MODEL_MAP,
  ECO_MODELS,
  MODEL_TO_PROVIDER,
};

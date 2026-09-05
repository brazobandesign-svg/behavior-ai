// Constantes de modelos, proveedores y límites — Matriz Éxodo DashScope Free Tier (1M tokens)

const ALIBABA_CONFIG = {
  baseURL: process.env.ALIBABA_BASE_URL || 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
  apiKey: process.env.DASHSCOPE_API_KEY || process.env.ALIBABA_API_KEY || process.env.ALIBABA_FREE_KEY,
  models: {
    // DOCTRINA (humano, 25-08): Kimi K3 y Qwen 3.7 Max RESERVADOS para Copilot (chatLanguageModels.json).
    // Flagship = qwen3.8-max-0902.
    textPrimary: 'qwen3.8-max-0902',            // Texto, conversación, redacción y asistencia general
    fastPrimary: 'qwen3.8-flash',               // Conversación instantánea (<200ms TTFT) para saludos y mensajes simples
    textFallback: 'qwen3.6-plus-2026-04-02',     // Respaldo de alta elocuencia
    reasonerPrimary: 'qwq-plus',                 // Razonamiento lógico profundo y matemáticas
    coderPrimary: 'qwen3.8-max-0902',            // Generación de código y artefactos interactivos de vanguardia
    coderFallback: 'qwen3-coder-plus-2025-09-23',// Respaldo especializado en código
    visionPrimary: 'qwen-vl-max',                // Análisis de imágenes, visión multimodal y OCR
    visionEco: 'qwen3-vl-plus',
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
    hazakPrimary: 'qwen3.8-max-0902',
    hazakReasoner: 'qwq-plus',
    hazakCoder: 'qwen3.8-max-0902',
    hazakVision: 'qwen-vl-max',
    genesisSimple: 'qwen3.8-flash',
    genesisRedaccion: 'qwen3.6-plus-2026-04-02',
    genesisReasoner: 'qwq-plus',
    genesisCoder: 'qwen3.8-max-0902',
    genesisVision: 'qwen3-vl-plus',
  },
};

const PLAN_CONFIG = {
  free: {
    name: 'G1.1',
    // Límites configurables por env (beta: se rebajan para probar la
    // degradación; producción: 6000/50000 por defecto).
    dailyTokensLimit: parseInt(process.env.TOKENS_LIMIT_FREE, 10) || 6000,
    maxOutputTokensNormal: 8192,
    monthlyVisionLimit: Infinity,
    dailyImagesLimit: 3,              // G1.1: pocas imágenes al día
    allowThinking: true,
    primaryModel: 'qwen3.8-max-0902',
    fallbackChain: [
      'qwen3.8-max-0902',
    ],
    visionModels: ['qwen-vl-max'],
    isDegradable: false,
  },
  pro: {
    name: 'XPi',
    priceUsd: 4.99,
    dailyTokensLimit: parseInt(process.env.TOKENS_LIMIT_PRO, 10) || 50000,
    maxOutputTokens: 8192,
    monthlyVisionLimit: Infinity,
    dailyImagesLimit: 25,             // XPi: 25 imágenes/día (antes 66/mes implícito)
    allowThinking: true,
    primaryModel: 'qwen3.8-max-0902',
    fallbackChain: [
      'qwen3.8-max-0902',
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
    imagesPerMonth: PLAN_CONFIG.free.monthlyVisionLimit,
    filesEnabled: true,
  },
  hazak: {
    name: PLAN_CONFIG.pro.name,
    tokensPerDay: PLAN_CONFIG.pro.dailyTokensLimit,
    imagesPerMonth: PLAN_CONFIG.pro.monthlyVisionLimit,
    filesEnabled: true,
  },
};
PLANS.free = PLANS.genesis;
PLANS.pro = PLANS.hazak;

const ECO_MODELS = {
  text:   'qwen3.8-flash',
  vision: 'qwen3-vl-plus',
};

const MODEL_MAP = {
  SIMPLE: {
    genesis: 'qwen3.8-flash',
    hazak:   'qwen3.8-max-0902',
    free:    'qwen3.8-flash',
    pro:     'qwen3.8-max-0902',
  },
  REDACCION: {
    genesis: 'qwen3.6-plus-2026-04-02',
    hazak:   'qwen3.8-max-0902',
    free:    'qwen3.6-plus-2026-04-02',
    pro:     'qwen3.8-max-0902',
  },
  RAZONAMIENTO: {
    genesis: 'qwen3.8-flash',
    hazak:   'qwq-plus',
    free:    'qwen3.8-flash',
    pro:     'qwq-plus',
  },
  DOCUMENTO: {
    genesis: 'qwen3.6-plus-2026-04-02',
    hazak:   'qwen3.8-max-0902',
    free:    'qwen3.6-plus-2026-04-02',
    pro:     'qwen3.8-max-0902',
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
  // DashScope Qwen / DeepSeek Active Free Tier Models
  'qwen3.8-max-0902':               'alibaba',
  'qwen3.6-max-preview':            'alibaba',
  'qwen3.8-flash':                  'alibaba',
  'qwen3.6-flash':                  'alibaba',
  'qwen3.6-plus-2026-04-02':        'alibaba',
  'qwq-plus':                       'alibaba',
  'qwen3-coder-plus-2025-09-23':    'alibaba',
  'qwen3-coder-plus-2025-07-22':    'alibaba',
  'qwen-vl-max':                    'alibaba',
  'qwen3-vl-plus':                  'alibaba',
  'glm-5.1':                        'alibaba',
  'deepseek-v3.2':                  'alibaba',
  'deepseek-v4-flash':              'alibaba',
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

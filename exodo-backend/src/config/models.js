// Constantes de modelos, proveedores y límites — Matriz Éxodo v2 (Pruebas Free con DeepSeek)

const PLANS = {
  genesis: {
    name: 'Genesis G1.1',
    tokensPerDay: 1000,
    historyDays: 7,
    imagesPerMonth: 0,
    filesEnabled: false,
  },
  hazak: {
    name: 'Hazak J1.9',
    tokensPerDay: 100000,
    historyDays: null, // ilimitado
    imagesPerMonth: 30,
    filesEnabled: true,
  },
};

// Modelo principal por intención y plan
// Plan Genesis (Free) usando deepseek-chat para pruebas de consumo de tokens
const MODEL_MAP = {
  SIMPLE: {
    genesis: 'deepseek-chat',
    hazak:   'deepseek-chat',
  },
  REDACCION: {
    genesis: 'deepseek-chat',
    hazak:   'deepseek-chat',
  },
  RAZONAMIENTO: {
    genesis: 'deepseek-chat',
    hazak:   'deepseek-reasoner',
  },
  DOCUMENTO: {
    genesis: 'deepseek-chat',
    hazak:   'deepseek-chat',
  },
  VISION: {
    genesis: 'gpt-4o-mini',
    hazak:   'gpt-4o-mini',
  },
  IMAGEN: {
    genesis: null,
    hazak:   null,
  },
};

const GENESIS_FALLBACK_CHAIN = [];
const XPI_FALLBACK_CHAIN = [];

const MODEL_TO_PROVIDER = {
  'deepseek-chat':     'deepseek',
  'deepseek-reasoner': 'deepseek',
  'gpt-4o-mini':       'openai',
};

module.exports = {
  PLANS,
  MODEL_MAP,
  GENESIS_FALLBACK_CHAIN,
  XPI_FALLBACK_CHAIN,
  MODEL_TO_PROVIDER,
};

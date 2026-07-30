// Constantes de modelos, proveedores y límites — Backend limpio

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

// Mapa temporal. El usuario definirá las reglas más adelante.
// Por ahora mapeamos a los únicos dos sobrevivientes.
const MODEL_MAP = {
  SIMPLE: {
    genesis: 'gpt-4o-mini',
    hazak:   'deepseek-chat',
  },
  REDACCION: {
    genesis: 'gpt-4o-mini',
    hazak:   'deepseek-chat',
  },
  RAZONAMIENTO: {
    genesis: 'gpt-4o-mini',
    hazak:   'deepseek-reasoner',
  },
  DOCUMENTO: {
    genesis: 'gpt-4o-mini',
    hazak:   'deepseek-chat',
  },
  VISION: {
    genesis: 'gpt-4o-mini', // gpt-4o-mini es multimodal
    hazak:   'gpt-4o-mini', // deepseek no ve, apoyamos en gpt-4o-mini
  },
  IMAGEN: {
    genesis: null,
    hazak:   null,
  },
};

// Cadenas de fallback vacías por el momento, hasta nuevas reglas.
const GENESIS_FALLBACK_CHAIN = [];
const XPI_FALLBACK_CHAIN = [];

// Mapeo modelo → proveedor
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

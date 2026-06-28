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
    genesis: 'nim-minimax-m3',
    hazak:   'nim-nemotron-3-ultra',
  },
  REDACCION: {
    genesis: 'nim-glm-5-1',
    hazak:   'nim-nemotron-3-ultra',
  },
  RAZONAMIENTO: {
    genesis: 'nim-minimax-m2-7',
    hazak:   'nim-deepseek-v4-pro',
  },
  DOCUMENTO: {
    genesis: 'nim-deepseek-v4-flash',
    hazak:   'nim-kimi-2-6',
  },
  IMAGEN: {
    genesis: null,
    hazak:   'flux-local',
  },
};

// Cadena de fallback para Genesis G1.1 Free (modelos rápidos + Ollama local al final)
const GENESIS_FALLBACK_CHAIN = [
  'nim-minimax-m3',          // ✅ verificado OK, respuesta rápida
  'nim-glm-5-1',             // ✅ verificado OK
  'nim-minimax-m2-7',        // ✅ verificado OK
  'nim-deepseek-v4-flash',   // ✅ verificado OK
  'qwen2.5:7b',              // Ollama Local (al final, solo si todo NIM cae)
];

// Cadena de fallback para XPi / Plan Hazak Pro (los 3 mejores modelos NIM + Ollama local al final)
const XPI_FALLBACK_CHAIN = [
  'nim-deepseek-v4-pro',     // Razonamiento profundo supremo
  'nim-nemotron-3-ultra',    // Inteligencia general pesada
  'nim-kimi-2-6',            // Documentos y contexto largo
  'qwen2.5:7b',              // Ollama Local como red de seguridad final
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
  'nim-llama-4':        'nim',
  'qwen2.5:7b':         'ollama',
  'flux-local':         'flux',
};

module.exports = {
  PLANS,
  MODEL_MAP,
  GENESIS_FALLBACK_CHAIN,
  XPI_FALLBACK_CHAIN,
  MODEL_TO_PROVIDER,
};

/**
 * Provider: NVIDIA NIM (Multi-Model Cascade)
 * Soportando: Nemotron 3 Ultra, DeepSeek V4 Flash/Pro, MiniMax M3/M2.7, Kimi 2.6, GLM 5.1
 *
 * Dos modos:
 *   • call(modelId, messages, systemPrompt) → respuesta completa (bloqueante).
 *   • callStream(modelId, messages, systemPrompt, onChunk) → SSE chunk por chunk.
 * El router decide cuál usar según el endpoint.
 */

const NIM_CONFIG = {
  'nim-nemotron-3-ultra': {
    model: 'nvidia/nemotron-3-ultra-550b-a55b',
    apiKeyEnv: 'NIM_KEY_NEMOTRON',
    defaultKey: '',
    name: 'nemotron-3-ultra'
  },
  'nim-deepseek-v4-flash': {
    model: 'deepseek-ai/deepseek-v4-flash',
    apiKeyEnv: 'NIM_KEY_DEEPSEEK_FLASH',
    defaultKey: '',
    name: 'deepseek-v4-flash'
  },
  'nim-deepseek-v4-pro': {
    model: 'deepseek-ai/deepseek-v4-pro',
    apiKeyEnv: 'NIM_KEY_DEEPSEEK_PRO',
    defaultKey: '',
    name: 'deepseek-v4-pro'
  },
  'nim-minimax-m3': {
    model: 'minimaxai/minimax-m3',
    apiKeyEnv: 'NIM_KEY_MINIMAX_M3',
    defaultKey: '',
    name: 'minimax-m3'
  },
  'nim-kimi-2-6': {
    model: 'moonshotai/kimi-k2.6',
    apiKeyEnv: 'NIM_KEY_KIMI',
    defaultKey: '',
    name: 'kimi-2.6'
  },
  'nim-glm-5-1': {
    model: 'z-ai/glm-5.1',
    apiKeyEnv: 'NIM_KEY_GLM',
    defaultKey: '',
    name: 'glm-5.1'
  },
  'nim-minimax-m2-7': {
    model: 'minimaxai/minimax-m2.7',
    apiKeyEnv: 'NIM_KEY_MINIMAX_M2_7',
    defaultKey: '',
    name: 'minimax-m2.7'
  },
  'nim-llama-4': {
    model: 'nvidia/llama-3.1-nemotron-70b-instruct',
    apiKeyEnv: 'NIM_API_KEY',
    defaultKey: '',
    name: 'nim-llama-4'
  }
};

async function call(modelId, messages, systemPrompt) {
  const cfg = NIM_CONFIG[modelId] || NIM_CONFIG['nim-nemotron-3-ultra'];
  const apiKey = process.env[cfg.apiKeyEnv] || cfg.defaultKey;

  const controller = new AbortController();
  // 45s: el cold start de NIM puede tardar 10-30s la primera vez,
  // y respuestas largas también. 4.5s mataba la cascada antes de
  // que el primer modelo siquiera respondiera.
  const timeoutMs = 45000;
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  let response;
  try {
    response = await fetch('https://integrate.api.nvidia.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: cfg.model,
        messages: [
          { role: 'system', content: systemPrompt },
          ...messages,
        ],
        max_tokens: 4096,
        temperature: 0.7,
      }),
      signal: controller.signal,
    });
  } catch (err) {
    clearTimeout(timer);
    const isAbort = err.name === 'AbortError' || controller.signal.aborted;
    if (isAbort) {
      const e = new Error(`NIM timeout (${cfg.model}) después de ${timeoutMs}ms`);
      e.code = 'TIMEOUT';
      throw e;
    }
    const e = new Error(`NIM network error (${cfg.model}): ${err.message}`);
    e.code = 'NETWORK';
    throw e;
  }
  clearTimeout(timer);

  if (!response.ok) {
    const errBody = await response.text().catch(() => '');
    // Clasificar el error para que el router decida cómo continuar.
    const e = new Error(`NIM error (${cfg.model}) HTTP ${response.status}: ${errBody.substring(0, 200)}`);
    if (response.status === 401 || response.status === 403) {
      e.code = 'AUTH';          // key inválida/revocada → siguiente
    } else if (response.status === 404) {
      e.code = 'NOT_FOUND';     // modelo no disponible para esta key → siguiente
    } else if (response.status === 429) {
      e.code = 'RATE_LIMIT';    // rate limit → siguiente
    } else if (response.status >= 500) {
      e.code = 'SERVER';        // problema del proveedor → siguiente
    } else {
      e.code = 'CLIENT';        // 400/otros → siguiente pero loguear
    }
    throw e;
  }

  const data = await response.json().catch(() => null);
  if (!data) {
    const e = new Error(`NIM respuesta inválida (${cfg.model}): JSON no parseable`);
    e.code = 'CLIENT';
    throw e;
  }

  const text = data.choices?.[0]?.message?.content || '';
  return {
    text,
    model: cfg.name,
    tokensInput: data.usage?.prompt_tokens || 0,
    tokensOutput: data.usage?.completion_tokens || 0,
  };
}

/**
 * Variante streaming real del provider NIM.
 * Devuelve la respuesta completa vía callback `onChunk(chunk)` por cada
 * fragmento que emite el modelo (no es pseudo-streaming).
 *
 * @param {string} modelId
 * @param {Array}  messages
 * @param {string} systemPrompt
 * @param {(chunk: string) => void} onChunk  llamado por cada delta del modelo
 * @returns {Promise<{text:string, model:string, tokensInput:number, tokensOutput:number}>}
 */
async function callStream(modelId, messages, systemPrompt, onChunk) {
  const cfg = NIM_CONFIG[modelId] || NIM_CONFIG['nim-nemotron-3-ultra'];
  const apiKey = process.env[cfg.apiKeyEnv] || cfg.defaultKey;

  const controller = new AbortController();
  const timeoutMs = 45000;
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  let response;
  try {
    response = await fetch('https://integrate.api.nvidia.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: cfg.model,
        messages: [
          { role: 'system', content: systemPrompt },
          ...messages,
        ],
        max_tokens: 4096,
        temperature: 0.7,
        stream: true, // ← clave: pide chunks en vez de respuesta completa
      }),
      signal: controller.signal,
    });
  } catch (err) {
    clearTimeout(timer);
    const isAbort = err.name === 'AbortError' || controller.signal.aborted;
    const e = new Error(
      isAbort
        ? `NIM stream timeout (${cfg.model}) después de ${timeoutMs}ms`
        : `NIM stream network error (${cfg.model}): ${err.message}`
    );
    e.code = isAbort ? 'TIMEOUT' : 'NETWORK';
    throw e;
  }

  if (!response.ok) {
    clearTimeout(timer);
    const errBody = await response.text().catch(() => '');
    const e = new Error(`NIM stream error (${cfg.model}) HTTP ${response.status}: ${errBody.substring(0, 200)}`);
    if (response.status === 401 || response.status === 403) e.code = 'AUTH';
    else if (response.status === 404) e.code = 'NOT_FOUND';
    else if (response.status === 429) e.code = 'RATE_LIMIT';
    else if (response.status >= 500) e.code = 'SERVER';
    else e.code = 'CLIENT';
    throw e;
  }

  // Parsear SSE manualmente (cada chunk llega como `data: {...}\n\n`).
  let fullText = '';
  let tokensInput = 0;
  let tokensOutput = 0;
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop() || ''; // última línea incompleta se queda en buffer

      for (const rawLine of lines) {
        const line = rawLine.trim();
        if (!line.startsWith('data:')) continue;
        const payload = line.slice(5).trim();
        if (payload === '[DONE]' || payload === '') continue;
        try {
          const parsed = JSON.parse(payload);
          const delta = parsed.choices?.[0]?.delta?.content;
          if (delta) {
            fullText += delta;
            onChunk(delta);
          }
          // NIM incluye usage en el último chunk si stream_options.include_usage=true,
          // pero por default no viene. Lo estimamos al final.
        } catch (_) {
          // línea malformada, ignorar
        }
      }
    }
  } catch (err) {
    clearTimeout(timer);
    reader.cancel().catch(() => {});
    const isAbort = err.name === 'AbortError' || controller.signal.aborted;
    const e = new Error(
      isAbort
        ? `NIM stream abortado (${cfg.model})`
        : `NIM stream parse error (${cfg.model}): ${err.message}`
    );
    e.code = isAbort ? 'TIMEOUT' : 'CLIENT';
    throw e;
  }
  clearTimeout(timer);

  // NIM no devuelve usage cuando streamea por default.
  // Estimación gruesa: ~4 chars/token en español.
  tokensInput = Math.ceil((systemPrompt.length + JSON.stringify(messages).length) / 4);
  tokensOutput = Math.ceil(fullText.length / 4);

  return {
    text: fullText,
    model: cfg.name,
    tokensInput,
    tokensOutput,
  };
}

module.exports = { call, callStream };

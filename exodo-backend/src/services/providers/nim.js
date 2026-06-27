/**
 * Provider: NVIDIA NIM (Multi-Model Cascade)
 * Soportando: Nemotron 3 Ultra, DeepSeek V4 Flash/Pro, MiniMax M3/M2.7, Kimi 2.6, GLM 5.1
 */

const NIM_CONFIG = {
  'nim-nemotron-3-ultra': {
    model: 'nvidia/nemotron-3-ultra-550b-a55b',
    apiKeyEnv: 'NIM_KEY_NEMOTRON',
    defaultKey: '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',
    name: 'nemotron-3-ultra'
  },
  'nim-deepseek-v4-flash': {
    model: 'deepseek-ai/deepseek-v4-flash',
    apiKeyEnv: 'NIM_KEY_DEEPSEEK_FLASH',
    defaultKey: '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',
    name: 'deepseek-v4-flash'
  },
  'nim-deepseek-v4-pro': {
    model: 'deepseek-ai/deepseek-v4-pro',
    apiKeyEnv: 'NIM_KEY_DEEPSEEK_PRO',
    defaultKey: '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',
    name: 'deepseek-v4-pro'
  },
  'nim-minimax-m3': {
    model: 'minimaxai/minimax-m3',
    apiKeyEnv: 'NIM_KEY_MINIMAX_M3',
    defaultKey: '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',
    name: 'minimax-m3'
  },
  'nim-kimi-2-6': {
    model: 'moonshotai/kimi-k2.6',
    apiKeyEnv: 'NIM_KEY_KIMI',
    defaultKey: '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',
    name: 'kimi-2.6'
  },
  'nim-glm-5-1': {
    model: 'z-ai/glm-5.1',
    apiKeyEnv: 'NIM_KEY_GLM',
    defaultKey: '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',
    name: 'glm-5.1'
  },
  'nim-minimax-m2-7': {
    model: 'minimaxai/minimax-m2.7',
    apiKeyEnv: 'NIM_KEY_MINIMAX_M2_7',
    defaultKey: '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',
    name: 'minimax-m2.7'
  },
  'nim-llama-4': {
    model: 'nvidia/llama-3.1-nemotron-70b-instruct',
    apiKeyEnv: 'NIM_API_KEY',
    defaultKey: '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',
    name: 'nim-llama-4'
  }
};

async function call(modelId, messages, systemPrompt) {
  const cfg = NIM_CONFIG[modelId] || NIM_CONFIG['nim-nemotron-3-ultra'];
  const apiKey = process.env[cfg.apiKeyEnv] || cfg.defaultKey;

  const response = await fetch('https://integrate.api.nvidia.com/v1/chat/completions', {
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
    signal: AbortSignal.timeout(4500),
  });

  if (!response.ok) {
    const errBody = await response.text();
    throw new Error(`NIM error (${cfg.model}) ${response.status}: ${errBody}`);
  }

  const data = await response.json();
  return {
    text: data.choices?.[0]?.message?.content || '',
    model: cfg.name,
    tokensInput: data.usage?.prompt_tokens || 15,
    tokensOutput: data.usage?.completion_tokens || 25,
  };
}

module.exports = { call };

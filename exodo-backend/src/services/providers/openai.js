/**
 * Provider: OpenAI
 * Modelos: gpt-4o-mini
 */

async function call(modelId, messages, systemPrompt, imageDataUris) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error('OPENAI_API_KEY no configurada');

  const finalMessages = [];
  if (systemPrompt) {
    finalMessages.push({ role: 'system', content: systemPrompt });
  }

  // Si hay imágenes, las adjuntamos al último mensaje del usuario
  for (let i = 0; i < messages.length; i++) {
    const isLast = i === messages.length - 1;
    const msg = messages[i];
    
    if (isLast && msg.role === 'user' && imageDataUris && imageDataUris.length > 0) {
      const contentParts = [{ type: 'text', text: msg.content || '' }];
      
      for (const uri of imageDataUris) {
        contentParts.push({
          type: 'image_url',
          image_url: { url: uri }
        });
      }
      
      finalMessages.push({ role: 'user', content: contentParts });
    } else {
      finalMessages.push({ role: msg.role, content: msg.content || '' });
    }
  }

  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`
    },
    body: JSON.stringify({
      model: modelId || 'gpt-4o-mini',
      messages: finalMessages,
      temperature: 0.7,
      max_tokens: 200,
    })
  });

  if (!response.ok) {
    const errBody = await response.text();
    throw new Error(`OpenAI ${modelId} error ${response.status}: ${errBody}`);
  }

  const data = await response.json();
  const text = data.choices[0]?.message?.content || '';

  return {
    text,
    model: data.model || modelId,
    tokensInput: data.usage?.prompt_tokens || 0,
    tokensOutput: data.usage?.completion_tokens || 0
  };
}

async function callStream(modelId, messages, systemPrompt, onChunk, imageDataUris) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error('OPENAI_API_KEY no configurada');

  const finalMessages = [];
  if (systemPrompt) {
    finalMessages.push({ role: 'system', content: systemPrompt });
  }

  for (let i = 0; i < messages.length; i++) {
    const isLast = i === messages.length - 1;
    const msg = messages[i];
    
    if (isLast && msg.role === 'user' && imageDataUris && imageDataUris.length > 0) {
      const contentParts = [{ type: 'text', text: msg.content || '' }];
      
      for (const uri of imageDataUris) {
        contentParts.push({
          type: 'image_url',
          image_url: { url: uri }
        });
      }
      
      finalMessages.push({ role: 'user', content: contentParts });
    } else {
      finalMessages.push({ role: msg.role, content: msg.content || '' });
    }
  }

  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`
    },
    body: JSON.stringify({
      model: modelId || 'gpt-4o-mini',
      messages: finalMessages,
      temperature: 0.7,
      max_tokens: 200,
      stream: true,
    })
  });

  if (!response.ok) {
    const errBody = await response.text();
    throw new Error(`OpenAI stream ${modelId} error ${response.status}: ${errBody}`);
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder('utf-8');
  let buffer = '';
  let fullText = '';
  let tokensInput = 0;
  let tokensOutput = 0;

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop() || '';

    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed.startsWith('data: ')) continue;
      const jsonStr = trimmed.slice(6).trim();
      if (jsonStr === '[DONE]') continue;
      
      try {
        const data = JSON.parse(jsonStr);
        const chunkText = data.choices[0]?.delta?.content;
        if (chunkText) {
          fullText += chunkText;
          if (typeof onChunk === 'function') onChunk(chunkText);
        }
        
        // El stream de OpenAI devuelve usage en el último chunk (si stream_options.include_usage = true,
        // pero por simplicidad omitimos contar tokens en streaming para OpenAI a menos que se solicite).
      } catch (e) {
        // Ignorar
      }
    }
  }

  return {
    text: fullText,
    model: modelId,
    tokensInput,
    tokensOutput,
  };
}

module.exports = { call, callStream };

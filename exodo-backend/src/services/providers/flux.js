/**
 * Provider: Flux 1 local (generación de imágenes)
 * Uso: IMAGEN para Hazak únicamente
 * Bible sección 04: $0 durante validación (local)
 * Migrar a fal.ai cuando el volumen lo justifique.
 */

async function call(modelId, messages, _systemPrompt) {
  const fluxUrl = process.env.FLUX_LOCAL_URL || 'http://localhost:7860';
  const lastMessage = messages[messages.length - 1]?.content || '';

  try {
    const response = await fetch(`${fluxUrl}/api/predict`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        data: [lastMessage], // prompt de la imagen
      }),
    });

    if (!response.ok) {
      throw new Error(`Flux local error ${response.status}`);
    }

    const data = await response.json();

    return {
      text: '🎨 Imagen generada exitosamente.',
      image_url: data.data?.[0] || null,
      model: 'flux-local',
      tokensInput: 0,
      tokensOutput: 0,
    };
  } catch (err) {
    throw new Error(`Flux local no disponible: ${err.message}. ¿Está corriendo en ${fluxUrl}?`);
  }
}

module.exports = { call };

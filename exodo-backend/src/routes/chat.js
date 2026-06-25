const express = require('express');
const router = express.Router();
const auth = require('../middleware/auth');
const planGuard = require('../middleware/planGuard');
const { classifyIntent } = require('../services/intentClassifier');
const { routeMessage } = require('../services/modelRouter');
const { getHistory, saveMessage } = require('../services/historyManager');
const { estimateTokens, updateTokenUsage } = require('../services/tokenCounter');

/**
 * System prompt de Éxodo — Bible sección 11, Regla #7:
 * "El system prompt de Éxodo está en español. La personalidad es hispanohablante y caribeña."
 * Regla #9: "No puede instruirlo a mentir si el usuario pregunta directamente."
 */
const EXODO_SYSTEM_PROMPT = `Eres Éxodo, un asistente de inteligencia artificial creado por Behavior.

Tu personalidad:
- Eres cercano, directo y útil. Tu tono es profesional pero cálido.
- Tu idioma nativo es el español. Respondes en el idioma que el usuario use.
- Tienes contexto profundo sobre República Dominicana y Latinoamérica.
- Conoces el currículo del MINERD, legislación dominicana y el contexto cultural local.

Reglas:
- No reveles qué modelo de IA corre por debajo de ti. Eres Éxodo.
- Si el usuario pregunta directamente si fuiste entrenado por Behavior, sé honesto: eres una interfaz inteligente creada por Behavior que utiliza tecnología de IA avanzada.
- Nunca inventes información legal o médica. Si no sabes, dilo.
- Formatea tus respuestas con markdown cuando sea apropiado.`;

/**
 * POST /chat
 * Bible sección 08: flujo completo de un mensaje.
 * Regla #3: Streaming obligatorio en todas las respuestas (SSE).
 *
 * Body: { message: string, conversationId?: string }
 * Headers: Authorization: Bearer {supabase_jwt}
 */
router.post('/', auth, planGuard, async (req, res) => {
  const { message, conversationId } = req.body;
  const { userId, plan, anonymous } = req.user;

  if (!message || typeof message !== 'string' || message.trim().length === 0) {
    return res.status(400).json({ error: 'El campo "message" es requerido' });
  }

  try {
    // 1. Recuperar historial (últimos 10 mensajes) — Bible: reduce tokens 50%
    const history = await getHistory(conversationId, 10);

    // 2. Clasificar intención (~$0.000015 en Gemini Flash)
    const intent = await classifyIntent(message);

    // 3. Construir mensajes con contexto
    const messages = [
      ...history,
      { role: 'user', content: message },
    ];

    // 4. Rutear al modelo correcto según intención + plan
    const result = await routeMessage(plan, intent, messages, EXODO_SYSTEM_PROMPT);

    // Si el router devolvió un error (feature no disponible, etc.)
    if (result.error) {
      return res.status(403).json(result);
    }

    // 5. Contar tokens y actualizar uso
    const totalTokens = (result.tokensInput || 0) + (result.tokensOutput || 0);
    if (req.usage && !anonymous) {
      await updateTokenUsage(req.usage.id, req.usage.tokens_used, totalTokens);
    }

    // 6. Guardar mensajes en DB (si no es anónimo y hay conversationId)
    if (conversationId && !anonymous) {
      await saveMessage(conversationId, 'user', message, { intent });
      await saveMessage(conversationId, 'assistant', result.text, {
        intent,
        model: result.model,
        tokensInput: result.tokensInput,
        tokensOutput: result.tokensOutput,
      });
    }

    // 7. Responder
    // TODO: Implementar SSE streaming real cuando los providers lo soporten.
    // Por ahora, respuesta completa en JSON.
    res.json({
      response: result.text,
      intent,
      image_url: result.image_url || null,
      tokens: {
        used: (req.usage?.tokens_used || 0) + totalTokens,
        limit: req.usage?.tokens_limit || 15000,
        remaining: Math.max(0, (req.usage?.tokens_limit || 15000) - (req.usage?.tokens_used || 0) - totalTokens),
        input: result.tokensInput || 0,
        output: result.tokensOutput || 0,
      },
    });

  } catch (error) {
    console.error('[chat] Error procesando mensaje:', error);
    res.status(500).json({
      error: 'Error procesando tu mensaje',
      details: process.env.NODE_ENV !== 'production' ? error.message : undefined,
    });
  }
});

module.exports = router;

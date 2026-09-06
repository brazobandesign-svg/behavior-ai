import 'dart:convert';

/// Tarjeta de aclaración guiada (paridad web): el modelo emite un bloque
/// ```exodo-options con JSON {"question","options","recommend"}; la app lo
/// renderiza en el COMPOSER (no en el chat) y envía la elección como turno
/// oculto del usuario (marcador <!--GUIDED:--> en la nube).
class GuidedCardData {
  final String question;
  final List<String> options;
  final int? recommend; // índice de la opción que Exodo recomienda

  const GuidedCardData({
    required this.question,
    required this.options,
    this.recommend,
  });
}

/// Busca el ÚLTIMO bloque ```exodo-options (tolerante a fence sin cerrar:
/// los modelos a veces olvidan el ```; si el JSON parsea, vale). null si no
/// hay bloque o el JSON aún está incompleto (streaming).
GuidedCardData? parseGuidedCard(String content) {
  if (content.isEmpty) return null;
  final re = RegExp(r'```exodo-options\r?\n?([\s\S]*?)(?:```|$)');
  String? lastRaw;
  for (final m in re.allMatches(content)) {
    lastRaw = m.group(1);
  }
  if (lastRaw == null) return null;
  try {
    final parsed = jsonDecode(lastRaw.trim());
    if (parsed is! Map<String, dynamic>) return null;
    final question = parsed['question'];
    final optionsRaw = parsed['options'];
    if (question is! String || optionsRaw is! List) return null;
    final options = optionsRaw
        .whereType<String>()
        .where((o) => o.trim().isNotEmpty)
        .take(6)
        .map((o) => o.trim())
        .toList();
    if (question.trim().isEmpty || options.length < 2) return null;
    final rec = parsed['recommend'];
    final recommend = rec is int && rec >= 0 && rec < options.length ? rec : null;
    return GuidedCardData(question: question.trim(), options: options, recommend: recommend);
  } catch (_) {
    return null;
  }
}

/// true si el mensaje del assistant es SOLO un bloque de opciones: su
/// burbuja no se pinta (el formulario vive en el composer).
bool isOptionsOnlyMessage(String content) {
  return content.trimLeft().startsWith('```exodo-options');
}

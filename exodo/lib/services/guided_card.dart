import 'dart:convert';

/// Tarjeta de aclaración guiada (paridad web): el modelo emite un bloque
/// ```exodo-options con JSON {"question","options","recommend"}; la app lo
/// renderiza en el COMPOSER (no en el chat) y envía la elección como turno
/// oculto del usuario (marcador <!--GUIDED:--> en la nube).
class GuidedCardData {
  final String question;
  final List<String> options;
  final int? recommend; // índice de la opción que Exodo recomienda
  /// Textos de la tarjeta en el idioma de la pregunta (emitidos por el
  /// modelo): recommended/other/other_hint/back. Vacío = usar i18n del app.
  final Map<String, String> labels;

  const GuidedCardData({
    required this.question,
    required this.options,
    this.recommend,
    this.labels = const {},
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
    final labelsRaw = parsed['labels'];
    final labels = <String, String>{};
    if (labelsRaw is Map) {
      labelsRaw.forEach((k, v) {
        if (k is String && v is String && v.trim().isNotEmpty) labels[k] = v.trim();
      });
    }
    return GuidedCardData(question: question.trim(), options: options, recommend: recommend, labels: labels);
  } catch (_) {
    return null;
  }
}

/// true si el mensaje del assistant es SOLO un bloque de opciones: su
/// burbuja no se pinta (el formulario vive en el composer).
bool isOptionsOnlyMessage(String content) {
  return content.trimLeft().startsWith('```exodo-options');
}

/// Tabla de textos de la tarjeta por idioma (paridad con guided.* del i18n).
const Map<String, Map<String, String>> kGuidedLabelsByLang = <String, Map<String, String>>{
  'es': {'recommended': 'Exodo recomienda', 'other': 'Otro…', 'other_hint': 'Escribe tu respuesta…', 'back': '‹ Atrás'},
  'en': {'recommended': 'Exodo recommends', 'other': 'Other…', 'other_hint': 'Type your answer…', 'back': '‹ Back'},
  'fr': {'recommended': 'Exodo recommande', 'other': 'Autre…', 'other_hint': 'Écrivez votre réponse…', 'back': '‹ Retour'},
  'ht': {'recommended': 'Exodo rekòmande', 'other': 'Lòt…', 'other_hint': 'Ekri repons ou…', 'back': '‹ Retounen'},
  'pt': {'recommended': 'Exodo recomenda', 'other': 'Outro…', 'other_hint': 'Escreva sua resposta…', 'back': '‹ Voltar'},
  'it': {'recommended': 'Exodo consiglia', 'other': 'Altro…', 'other_hint': 'Scrivi la tua risposta…', 'back': '‹ Indietro'},
  'de': {'recommended': 'Exodo empfiehlt', 'other': 'Andere…', 'other_hint': 'Schreibe deine Antwort…', 'back': '‹ Zurück'},
  'ru': {'recommended': 'Exodo рекомендует', 'other': 'Другое…', 'other_hint': 'Напишите свой ответ…', 'back': '‹ Назад'},
  'zh': {'recommended': 'Exodo 推荐', 'other': '其他…', 'other_hint': '写下你的回答…', 'back': '‹ 返回'},
  'ja': {'recommended': 'Exodoのおすすめ', 'other': 'その他…', 'other_hint': '回答を入力…', 'back': '‹ 戻る'},
  'ko': {'recommended': 'Exodo 추천', 'other': '기타…', 'other_hint': '답변을 입력하세요…', 'back': '‹ 뒤로'},
  'ar': {'recommended': 'Exodo يوصي بـ', 'other': 'أخرى…', 'other_hint': 'اكتب إجابتك…', 'back': '‹ رجوع'},
  'hi': {'recommended': 'Exodo सुझाव', 'other': 'अन्य…', 'other_hint': 'अपना उत्तर लिखें…', 'back': '‹ वापस'},
};

/// Detecta el idioma de la pregunta (la respuesta del modelo SIEMPRE va en el
/// idioma del usuario): escritura no latina determina ru/zh/ja/ar/ko/hi al
/// 100%; en latino, palabras clave con desempate por fallback.
String detectQuestionLang(String question, String fallbackLocale) {
  final t = question.toLowerCase();
  if (RegExp(r'[Ѐ-ӿ]').hasMatch(t)) return 'ru';
  if (RegExp(r'[぀-ヿ]').hasMatch(t)) return 'ja';
  if (RegExp(r'[가-힯]').hasMatch(t)) return 'ko';
  if (RegExp(r'[一-鿿]').hasMatch(t)) return 'zh';
  if (RegExp(r'[؀-ۿ]').hasMatch(t)) return 'ar';
  if (RegExp(r'[ऀ-ॿ]').hasMatch(t)) return 'hi';
  final scores = <String, int>{
    'es': 0, 'en': 0, 'fr': 0, 'pt': 0, 'it': 0, 'de': 0, 'ht': 0,
  };
  // ¿ y ¡ son puntuación EXCLUSIVA del español: señal fuerte.
  if (question.contains('¿') || question.contains('¡')) scores['es'] = (scores['es']!) + 3;
  void add(String lang, List<String> words) {
    for (final w in words) {
      final word = RegExp.escape(w);
      if (RegExp(r'(^|[\s¿¡/])' + word + r'([\s?,:]|$)', caseSensitive: false).hasMatch(t)) {
        scores[lang] = (scores[lang] ?? 0) + 1;
      }
    }
  }

  add('es', ['qué', 'quién', 'cuál', 'cómo', 'para', 'quiero', 'tipo', 'mejor', 'tu', 'una', 'dónde', 'gustar', 'empez', 'aprend', 'organi', 'regalo', 'fiesta', 'página', 'hoy']);
  add('en', ['what', 'which', 'kind', 'type', 'want', 'best', 'your', 'help', 'page', 'gift', 'party', 'learn']);
  add('fr', ['quel', 'quelle', 'pour', 'quoi', 'veux', 'type', 'page', 'cadeau', 'fête', 'apprendre']);
  add('pt', ['qual', 'que', 'para', 'quero', 'tipo', 'página', 'presente', 'festa', 'aprender']);
  add('it', ['che', 'quale', 'per', 'vuoi', 'tipo', 'pagina', 'regalo', 'festa', 'imparare']);
  add('de', ['welche', 'was', 'für', 'willst', 'art', 'seite', 'geschenk', 'party', 'lernen']);
  add('ht', ['kilè', 'pou', 'ki', 'vle', 'kalite', ' paj', ' kado', 'fèt', 'aprann']);
  String best = 'es';
  int bestScore = -1;
  scores.forEach((k, v) {
    if (v > bestScore) {
      bestScore = v;
      best = k;
    }
  });
  if (bestScore <= 0) {
    final base = fallbackLocale.toLowerCase().split(RegExp('[-_]')).first;
    return kGuidedLabelsByLang.containsKey(base) ? base : 'es';
  }
  return best;
}

/// Textos de la tarjeta: los del modelo si los trajo; si no, los del idioma
/// detectado en la pregunta; último recurso, el i18n del caller.
Map<String, String> resolveGuidedLabels(
  Map<String, String> modelLabels,
  String question,
  String fallbackLocale,
) {
  if (modelLabels.isNotEmpty) return modelLabels;
  final lang = detectQuestionLang(question, fallbackLocale);
  return kGuidedLabelsByLang[lang] ?? kGuidedLabelsByLang['es']!;
}

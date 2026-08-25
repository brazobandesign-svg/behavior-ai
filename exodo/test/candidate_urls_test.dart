import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exodo/services/chat_service.dart';

/// SEGURIDAD (auditoría C3): en release el JWT NUNCA debe viajar por HTTP.
/// Los candidatos http://127.0.0.1 y http://192.168.* están gated por
/// kDebugMode dentro de ChatService._candidateUrls.
///
/// Ejecutar ambos modos para validar el gate completo:
///   flutter test                    (debug: kDebugMode == true)
///   flutter test --release          (release: kDebugMode == false)
void main() {
  group('ChatService.candidateUrls — gate kDebugMode', () {
    test('Railway HTTPS siempre presente como destino productivo', () {
      final urls = ChatService.candidateUrls;
      expect(
        urls.any((u) => u.startsWith('https://behavior-ai-production')),
        isTrue,
        reason: 'El fallback productivo HTTPS debe existir en todo modo',
      );
    });

    test('en release NO hay candidatos http:// (JWT jamás en claro)', () {
      final urls = ChatService.candidateUrls;
      if (kReleaseMode) {
        final plainHttp = urls.where((u) => u.startsWith('http://')).toList();
        expect(
          plainHttp,
          isEmpty,
          reason: 'Release no puede contener candidatos http://: '
              'encontrados=$plainHttp',
        );
        expect(urls, contains('https://behavior-ai-production.up.railway.app/api/chat'));
      } else {
        // En debug los candidatos LAN son intencionales y permitidos.
        expect(urls, everyElement(isNotEmpty));
      }
    });

    test('candidateUrls es inmodificable (vista de solo lectura)', () {
      expect(() => ChatService.candidateUrls.add('http://evil.example'),
          throwsUnsupportedError);
    });
  }, skip: false);
}

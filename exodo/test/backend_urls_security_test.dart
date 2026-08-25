import 'package:flutter_test/flutter_test.dart';
import 'helpers/pure_logic_helpers.dart';

void main() {
  group('candidateUrls (seguridad de transporte en release)', () {
    test('RELEASE: no contiene NINGÚN http:// (solo HTTPS)', () {
      final urls = candidateUrls(isDebug: false);
      expect(
        urls.where((u) => u.startsWith('http://')),
        isEmpty,
        reason: 'En release el JWT jamás debe viajar por HTTP plano',
      );
      expect(urls, isNotEmpty);
    });

    test('RELEASE: no incluye 127.0.0.1 ni 192.168.*', () {
      final urls = candidateUrls(isDebug: false).join('|');
      expect(urls, isNot(contains('127.0.0.1')));
      expect(urls, isNot(contains('192.168.')));
    });

    test('RELEASE: siempre contiene el endpoint productivo HTTPS', () {
      final urls = candidateUrls(isDebug: false);
      expect(
        urls,
        contains('https://behavior-ai-production.up.railway.app/api/chat'),
      );
    });

    test('DEBUG: sí expone los candidatos locales http:// (dev UX)', () {
      final urls = candidateUrls(isDebug: true);
      expect(urls, contains('http://127.0.0.1:3000/api/chat'));
      expect(urls, contains('http://192.168.8.223:3000/api/chat'));
    });

    test('env BACKEND_URL se normaliza con sufijo /api/chat', () {
      final urls = candidateUrls(
        isDebug: false,
        envUrls: ['https://mi-backend.com'],
      );
      expect(urls, contains('https://mi-backend.com/api/chat'));
    });

    test('env ya terminado en /api/chat no se duplica el sufijo', () {
      final urls = candidateUrls(
        isDebug: false,
        envUrls: ['https://mi-backend.com/api/chat'],
      );
      expect(urls, contains('https://mi-backend.com/api/chat'));
      expect(urls.where((u) => u.contains('/api/chat/api/chat')), isEmpty);
    });

    test('workingUrl fija devuelve un único candidato', () {
      final urls = candidateUrls(
        isDebug: true,
        workingUrl: 'https://custom.example.com/api/chat',
      );
      expect(urls, ['https://custom.example.com/api/chat']);
    });

    test('sin env y sin workingUrl en release: solo producción', () {
      expect(candidateUrls(isDebug: false), [
        'https://behavior-ai-production.up.railway.app/api/chat',
      ]);
    });
  });
}

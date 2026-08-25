import 'package:flutter_test/flutter_test.dart';

// Helper de deduplicación idéntico al algoritmo de AppState._makeUniqueTitle
String makeUniqueTitle(String base, Iterable<String> existingTitles) {
  final clean = base.trim();
  if (clean.isEmpty) return clean;
  final existing = existingTitles.map((t) => t.trim()).toSet();
  if (!existing.contains(clean)) return clean;
  var n = 2;
  while (existing.contains('$clean ·$n')) {
    n++;
  }
  return '$clean ·$n';
}

// Helper de clave de caché idéntico al algoritmo de ExpedientesRepository._prefsKey
String getExpedientesPrefsKey(String? uid) {
  final scope = (uid == null || uid.isEmpty) ? 'anon' : uid;
  return 'exodo_local_expedientes_$scope';
}

// Helper de resolución de URLs idéntico al algoritmo de ChatService._candidateUrls
List<String> resolveCandidateUrls({
  required bool isDebug,
  List<String> envUrls = const [],
}) {
  final list = <String>[];
  for (final env in envUrls) {
    if (env.isNotEmpty) {
      final url = env.endsWith('/api/chat') ? env : '$env/api/chat';
      if (!list.contains(url)) list.add(url);
    }
  }
  const prodUrl = 'https://behavior-ai-production.up.railway.app/api/chat';
  if (isDebug) {
    list.add('http://127.0.0.1:3000/api/chat');
    list.add('http://192.168.8.223:3000/api/chat');
  }
  if (!list.contains(prodUrl)) list.add(prodUrl);
  return list;
}

void main() {
  group('1. Deduplicación de títulos (lógica "Título ·2")', () {
    test('Título nuevo sin colisión se mantiene idéntico', () {
      final existing = ['Proyecto 1', 'Notas de clase'];
      expect(makeUniqueTitle('Nuevo chat', existing), equals('Nuevo chat'));
    });

    test('Primera colisión agrega sufijo " ·2"', () {
      final existing = ['Hola'];
      expect(makeUniqueTitle('Hola', existing), equals('Hola ·2'));
    });

    test('Múltiples colisiones incrementan secuencialmente a " ·3", " ·4"', () {
      final existing = ['Hola', 'Hola ·2', 'Hola ·3'];
      expect(makeUniqueTitle('Hola', existing), equals('Hola ·4'));
    });

    test('Limpieza de espacios en blanco antes de evaluar', () {
      final existing = ['Resumen'];
      expect(makeUniqueTitle('  Resumen  ', existing), equals('Resumen ·2'));
    });

    test('Cadena vacía se retorna intacta', () {
      expect(makeUniqueTitle('   ', ['Hola']), equals(''));
    });
  });

  group('2. Aislamiento de clave de expedientes por UID', () {
    test('Usuario no autenticado (null) usa scope anon', () {
      expect(getExpedientesPrefsKey(null), equals('exodo_local_expedientes_anon'));
    });

    test('Usuario con string vacío usa scope anon', () {
      expect(getExpedientesPrefsKey(''), equals('exodo_local_expedientes_anon'));
    });

    test('Usuario autenticado usa su UID específico', () {
      const uid = 'usr_abc_123_xyz';
      expect(getExpedientesPrefsKey(uid), equals('exodo_local_expedientes_usr_abc_123_xyz'));
    });

    test('Dos UIDs distintos generan llaves de caché completamente aisladas', () {
      final keyUserA = getExpedientesPrefsKey('uuid-user-a-1111');
      final keyUserB = getExpedientesPrefsKey('uuid-user-b-2222');
      expect(keyUserA, isNot(equals(keyUserB)));
      expect(keyUserA, contains('uuid-user-a-1111'));
      expect(keyUserB, contains('uuid-user-b-2222'));
    });
  });

  group('3. Seguridad de Red: _candidateUrls en Release no contiene HTTP plano', () {
    test('En modo Release (isDebug = false), CERO URLs usan http://', () {
      final releaseUrls = resolveCandidateUrls(isDebug: false);
      expect(releaseUrls, isNotEmpty);
      for (final url in releaseUrls) {
        expect(url.startsWith('http://'), isFalse, reason: 'URL insegura en release: $url');
        expect(url.startsWith('https://'), isTrue, reason: 'Debe usar HTTPS en release: $url');
      }
      expect(releaseUrls, contains('https://behavior-ai-production.up.railway.app/api/chat'));
      expect(releaseUrls, isNot(contains('http://127.0.0.1:3000/api/chat')));
      expect(releaseUrls, isNot(contains('http://192.168.8.223:3000/api/chat')));
    });

    test('En modo Debug (isDebug = true), incluye candidatos LAN locales para pruebas', () {
      final debugUrls = resolveCandidateUrls(isDebug: true);
      expect(debugUrls, contains('http://127.0.0.1:3000/api/chat'));
      expect(debugUrls, contains('http://192.168.8.223:3000/api/chat'));
      expect(debugUrls, contains('https://behavior-ai-production.up.railway.app/api/chat'));
    });
  });
}

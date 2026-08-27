// [Punto 5] GitHub Commits: lógica pura de OAuth×commit de artefactos.
//
// Importa el código de producción REAL (`github_commit_logic.dart`, Dart puro)
// más las políticas Guest existentes — sin réplicas.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:exodo/l10n/app_translations.dart';
import 'package:exodo/services/expedientes_access_policy.dart';
import 'package:exodo/services/github_commit_logic.dart';

void main() {
  group('P5-GitHub · llaves de almacenamiento scopeadas por uid', () {
    test('Cada cuenta tiene su propio PAT/último-repo; sin uid cae a anon', () {
      expect(githubPatPrefsKeyFor('u1'), isNot(githubPatPrefsKeyFor('u2')));
      expect(githubPatPrefsKeyFor(null), contains('_anon'));
      expect(githubPatPrefsKeyFor(''), contains('_anon'));
      expect(githubLastRepoPrefsKeyFor('u1'),
          isNot(githubLastRepoPrefsKeyFor('u2')));
      expect(githubPatPrefsKeyFor('uid-x'), 'exodo_github_pat_uid-x');
      expect(githubLastRepoPrefsKeyFor('uid-x'), 'exodo_gh_last_repo_uid-x');
    });
  });

  group('P5-GitHub · parseOwnerRepo', () {
    test('Forma corta owner/repo', () {
      expect(parseOwnerRepo('exodo-dev/artifacts'), ('exodo-dev', 'artifacts'));
    });

    test('Acepta URL completa con y sin .git y subrutas', () {
      expect(parseOwnerRepo('https://github.com/miuser/mirepo.git'),
          ('miuser', 'mirepo'));
      expect(
          parseOwnerRepo(
              'https://github.com/miuser/mirepo/tree/main/src'), 
          ('miuser', 'mirepo'));
      expect(parseOwnerRepo('git@github.com:a/b.git'), isNotNull);
    });

    test('Entradas inválidas → (null, null)', () {
      expect(parseOwnerRepo(''), (null, null));
      expect(parseOwnerRepo('solo-una-parte'), (null, null));
      expect(parseOwnerRepo('tres/partes/aqui'), (null, null));
      expect(parseOwnerRepo('-mal/mal-'), (null, null));
      expect(parseOwnerRepo('espacio raro/repo'), (null, null));
    });
  });

  group('P5-GitHub · validación de slugs y rutas', () {
    test('Slugs válidos e inválidos', () {
      expect(isValidRepoSlug('user-name.dev_x1'), isTrue);
      expect(isValidRepoSlug('-empieza-guion'), isFalse);
      expect(isValidRepoSlug('termina-guion-'), isFalse);
      expect(isValidRepoSlug(''), isFalse);
      expect(isValidRepoSlug('a' * 101), isFalse);
    });

    test('Rutas peligrosas o malformadas rechazadas', () {
      expect(isValidFilePath('../etc/passwd'), isFalse);
      expect(isValidFilePath('src/../../secret'), isFalse);
      expect(isValidFilePath('/absoluta.html'), isFalse);
      expect(isValidFilePath('a\\..\\b.txt'), isFalse);
      expect(isValidFilePath('src//doble.html'), isFalse);
      expect(isValidFilePath('colon:no.txt'), isFalse);
      expect(isValidFilePath('   '), isFalse);
    });

    test('Rutas legítimas aceptadas', () {
      for (final ok in ['app.html', 'src/artifacts/app.html', 'mi carpeta/a.md']) {
        expect(isValidFilePath(ok), isTrue, reason: ok);
      }
    });

  });

  group('P5-GitHub · nombres, ruta y mensaje por defecto', () {
    test('sanitizeFileNameBase limpia títulos reales', () {
      expect(sanitizeFileNameBase('Mi Tabla Genial!'), 'mi-tabla-genial');
      expect(sanitizeFileNameBase('  --Doble--Guion--  '), 'doble-guion');
      expect(sanitizeFileNameBase('🎨 emoji'), 'emoji');
      expect(sanitizeFileNameBase('!!!'), 'artefacto-exodo');
      expect(sanitizeFileNameBase(''), 'artefacto-exodo');
    });

    test('defaultExtForLanguage cubre lenguajes comunes y cae a txt', () {
      expect(defaultExtForLanguage('markdown'), 'md');
      expect(defaultExtForLanguage('python'), 'py');
      expect(defaultExtForLanguage('JavaScript'), 'js');
      expect(defaultExtForLanguage('svg'), 'svg');
      expect(defaultExtForLanguage('desconocido'), 'txt');
    });

    test('defaultFilePathFor sigue el formato src/artifacts/<slug>.<ext>', () {
      expect(defaultFilePathFor(title: 'Rubrica_semestral', ext: 'html'),
          'src/artifacts/rubrica_semestral.html');
    });

    test('defaultCommitMessage usa el patrón feat(exodo)', () {
      expect(defaultCommitMessage('Mi Artefacto'),
          'feat(exodo): add Mi Artefacto artifact');
      expect(defaultCommitMessage('   '), 'feat(exodo): add artifact artifact');
    });
  });

  group('P5-GitHub · API v3: URL, base64 y payload PUT', () {
    test('contentsApiUrl respeta el endpoint oficial de la especificación', () {
      expect(
        contentsApiUrl(owner: 'acme', repo: 'widgets', path: 'src/app.html'),
        'https://api.github.com/repos/acme/widgets/contents/src/app.html',
      );
      expect(
        contentsApiUrl(owner: 'acme', repo: 'w', path: r'a\b\\c.txt'),
        'https://api.github.com/repos/acme/w/contents/a/b/c.txt',
      );
    });

    test('encodeFileContent produce base64 UTF-8 decodificable', () {
      const src = 'const x = "café ñ";';
      final encoded = encodeFileContent(src);
      expect(utf8.decode(base64.decode(encoded)), src);
    });

    test('buildPutPayload: mensaje vacío cae al default; rama vacía → main', () {
      final p = buildPutPayload(commitMessage: '', fileContent: 'hi', branch: '');
      expect(p['message'], 'feat(exodo): add artifact artifact');
      expect(p['branch'], 'main');
      expect(p['content'], encodeFileContent('hi'));
      final q =
          buildPutPayload(commitMessage: 'fix: x', fileContent: 'hi', branch: 'dev');
      expect(q['message'], 'fix: x');
      expect(q['branch'], 'dev');
    });

    test('looksLikePlausibleToken filtra tokens débiles', () {
      expect(looksLikePlausibleToken('short'), isFalse);
      expect(looksLikePlausibleToken('tiene espacios dentro del token'), isFalse);
      expect(
          looksLikePlausibleToken('ghp_unTokenRazonablementeLargo123456'), isTrue);
    });

    test('extractUrlsFromGithubResponse lee shapes nuevos y mínimos', () {
      final full = extractUrlsFromGithubResponse(<String, dynamic>{
        'content': {'html_url': 'https://github.com/o/r/blob/main/f.html'},
        'commit': {'html_url': 'https://github.com/o/r/commit/abc123'},
      });
      expect(full.$1, contains('/blob/main/f.html'));
      expect(full.$2, contains('/commit/abc123'));
      final empty = extractUrlsFromGithubResponse(<String, dynamic>{});
      expect(empty.$1, isNull);
      expect(empty.$2, isNull);
    });
  });

  group('P5-GitHub · guest gating coherente con Punto 3', () {
    test('Invitado no puede commitear; autenticado sí (acción oculta)', () {
      expect(canSaveExpediente(isGuestUser: true), isFalse);
      expect(canSaveExpediente(isGuestUser: false), isTrue);
      expect(expedientesModuleVisible(isGuestUser: true),
          equals(canSaveExpediente(isGuestUser: true)));
    });
  });

  group('P5-GitHub · i18n github.* en los 14 locales', () {
    const codes = [
      'es', 'en', 'fr', 'ht', 'pt', 'pt_BR', 'it',
      'de', 'ru', 'zh', 'ja', 'ar', 'ko', 'hi',
    ];
    const keys = [
      'github.sheet_title', 'github.sheet_desc', 'github.repo_hint',
      'github.path_hint', 'github.msg_hint', 'github.branch_hint',
      'github.pat_hint', 'github.link_btn', 'github.commit_btn',
      'github.success', 'github.error', 'github.link_required',
    ];

    test('Las 12 claves existen y no están vacías en cada locale', () {
      for (final code in codes) {
        final map = translationsFor(code);
        for (final k in keys) {
          expect(map[k]?.trim(), allOf(isNotNull, isNot(isEmpty)),
              reason: '$code carece de $k');
        }
      }
    });

    test('El ES base define las 12 claves nuevas (universo)', () {
      final es = translationsFor('es');
      for (final k in keys) {
        expect(es.containsKey(k), isTrue, reason: k);
      }
    });
  });
}


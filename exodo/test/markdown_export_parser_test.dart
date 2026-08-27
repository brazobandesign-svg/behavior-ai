// Pruebas del parser puro de Markdown para exportación (DOCX/PDF).
// Importa el código de producción REAL (`markdown_export_parser.dart`).
import 'package:flutter_test/flutter_test.dart';
import 'package:exodo/services/markdown_export_parser.dart';

void main() {
  group('Parser · bloques básicos', () {
    test('Titulos #, ##, ### producen heading con nivel jerárquico', () {
      final b = MarkdownExportParser.parse('# Uno\n## Dos\n### Tres');
      expect(b, hasLength(3));
      expect(b[0].type, ExportBlockType.heading);
      expect(b[0].level, 1);
      expect(b[1].type, ExportBlockType.heading);
      expect(b[1].level, 2);
      expect(b[2].type, ExportBlockType.heading);
      expect(b[2].level, 3);
      expect(b[2].plainText, 'Tres');
    });

    test('Texto vacío o sólo espacios → lista vacía', () {
      expect(MarkdownExportParser.parse(''), isEmpty);
      expect(MarkdownExportParser.parse('   \n  '), isEmpty);
    });
  });

  group('Parser · inline (negrita/cursiva/código)', () {
    test('negrita doble ** y __', () {
      final s = MarkdownExportParser.parseInlines('hola **mundo** __feliz__');
      expect(s.map((e) => e.bold).toList(), [false, true, false, true]);
      expect(s.map((e) => e.text).join(), 'hola mundo feliz');
    });

    test('cursiva simple * y _', () {
      final s = MarkdownExportParser.parseInlines('texto *italica* aqui');
      final it = s.where((e) => e.italic).toList();
      expect(it, hasLength(1));
      expect(it.first.text, 'italica');
    });

    test('_ dentro de palabra NO toggla cursiva (foo_bar estu_m)', () {
      final s = MarkdownExportParser.parseInlines('foo_bar_y_negocio_x');
      expect(s.every((e) => !e.italic), isTrue);
      expect(s.map((e) => e.text).join(), 'foo_bar_y_negocio_x');
    });

    test('código inline `` ` `` captura verbatim', () {
      final s = MarkdownExportParser.parseInlines('usa `final x = 1;` aqui');
      final c = s.where((e) => e.code).toList();
      expect(c, hasLength(1));
      expect(c.first.text, 'final x = 1;');
    });
  });

  group('Parser · bloques de código', () {
    test('``` dart ``` produce codeBlock con lenguaje y líneas', () {
      final b = MarkdownExportParser.parse(
          '```dart\nvoid main() {}\nprint("ok");\n```');
      expect(b, hasLength(1));
      expect(b.first.type, ExportBlockType.codeBlock);
      expect(b.first.language, 'dart');
      expect(b.first.codeLines, ['void main() {}', 'print("ok");']);
    });

    test('fence sin cierre conserva las líneas', () {
      final b = MarkdownExportParser.parse('```\na\nb');
      expect(b.single.type, ExportBlockType.codeBlock);
      expect(b.single.codeLines, ['a', 'b']);
    });
  });

  group('Parser · listas con viñetas', () {
    test('items consecutivos - * + se agrupan', () {
      final b = MarkdownExportParser.parse('- uno\n- dos\n* tres');
      expect(b, hasLength(1));
      expect(b.single.type, ExportBlockType.bulletList);
      expect(b.single.items, hasLength(3));
      expect(b.single.items[0].first.text, 'uno');
      expect(b.single.items[1].first.text, 'dos');
      expect(b.single.items[2].first.text, 'tres');
    });
  });

  group('Parser · párrafos y mezcla', () {
    test('líneas de párrafo se unen y conservan la estructura', () {
      final b = MarkdownExportParser.parse(
          '# Intro\n\nPrimera linea\nSegunda linea\n\n- item');
      expect(b, hasLength(3));
      expect(b[0].type, ExportBlockType.heading);
      expect(b[1].type, ExportBlockType.paragraph);
      expect(b[1].plainText, 'Primera linea Segunda linea');
      expect(b[2].type, ExportBlockType.bulletList);
    });

    test('normaliza finales CR/LF', () {
      final b = MarkdownExportParser.parse('# A\r\nB\r\n- C');
      expect(b.map((e) => e.type),
          [ExportBlockType.heading, ExportBlockType.paragraph, ExportBlockType.bulletList]);
    });
  });
}
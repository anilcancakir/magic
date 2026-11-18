import 'dart:io';

import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/src/cli/commands/design_lint_command.dart';
import 'package:path/path.dart' as p;

/// A clean, well-ordered DESIGN.md that the linter must pass (exit 0), with the
/// single-file `dark:` overlay accepted (never flagged as an unknown key) and a
/// high-contrast component pair.
const String _clean = '''
---
name: Acme
colors:
  primary:
    light: "#5b21b6"
    dark: "#a78bfa"
  on-primary: "#ffffff"
  surface:
    light: "#f9f9ff"
    dark: "#0f1419"
typography:
  body-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 16px
rounded:
  md: 8px
spacing:
  md: 16px
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.md}"
    padding: "{spacing.md}"
---

## Overview

Acme system.

## Colors

Colors.

## Typography

Type.

## Layout

Layout.

## Components

Components.
''';

DowelContext _ctx(BufferedOutput output, List<String> args) {
  // The parser comes from the command's own signature, so the flag types and
  // defaults the real CLI uses are the ones under test.
  final parser = ArgParser();
  CommandSignature.parse(DesignLintCommand().signature).applyTo(parser);
  final input = ArgvInput.parse(parser, args);
  return DowelContext.bare(input, output);
}

void main() {
  group('DesignLintCommand metadata', () {
    final cmd = DesignLintCommand();

    test('declares name design:lint', () {
      expect(cmd.name, 'design:lint');
    });

    test('declares CommandBoot.none', () {
      expect(cmd.boot, CommandBoot.none);
    });
  });

  group('DesignLintCommand.handle()', () {
    late Directory root;
    late BufferedOutput output;

    setUp(() {
      root = Directory.systemTemp.createTempSync('design_lint_');
      output = BufferedOutput();
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    Future<int> lint(String content) {
      File(p.join(root.path, 'DESIGN.md')).writeAsStringSync(content);
      final cmd = DesignLintCommand(projectRoot: root.path);
      return cmd.handle(_ctx(output, <String>['--input=DESIGN.md']));
    }

    test('passes a clean file with the dark: overlay accepted', () async {
      final code = await lint(_clean);

      expect(code, 0);
      // The dark: overlay key must NOT trigger an unknown-key finding.
      expect(output.content, isNot(contains('Unknown key')));
    });

    test('flags a broken reference as an error and exits nonzero', () async {
      const broken = '''
---
name: Acme
colors:
  primary: "#5b21b6"
components:
  card:
    backgroundColor: "{colors.does-not-exist}"
---

## Colors
''';
      final code = await lint(broken);

      expect(code, isNot(0));
      expect(output.content, contains('does-not-exist'));
    });

    test('flags a WCAG contrast failure on a component bg/text pair', () async {
      const lowContrast = '''
---
name: Acme
colors:
  primary: "#aaaaaa"
  on-primary: "#cccccc"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
---

## Colors
''';
      await lint(lowContrast);

      expect(output.content.toLowerCase(), contains('contrast'));
    });

    test('warns when the primary color is missing', () async {
      const noPrimary = '''
---
name: Acme
colors:
  surface: "#f9f9ff"
---

## Colors
''';
      await lint(noPrimary);

      expect(output.content.toLowerCase(), contains('primary'));
    });

    test('warns on a top-level key that is a typo of a schema key', () async {
      const typo = '''
---
name: Acme
colers:
  primary: "#5b21b6"
---

## Colors
''';
      await lint(typo);

      expect(output.content, contains('colers'));
    });

    test('warns when sections appear out of canonical order', () async {
      const outOfOrder = '''
---
name: Acme
colors:
  primary: "#5b21b6"
---

## Typography

Type.

## Colors

Colors.
''';
      await lint(outOfOrder);

      expect(output.content.toLowerCase(), contains('order'));
    });

    test('flags an orphaned custom token never referenced', () async {
      const orphan = '''
---
name: Acme
colors:
  primary: "#5b21b6"
  on-primary: "#ffffff"
  brand-magenta: "#ff00ff"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
---

## Colors
''';
      await lint(orphan);

      expect(output.content, contains('brand-magenta'));
    });
  });

  group('DesignLintCommand.handle() --dart', () {
    late Directory root;
    late BufferedOutput output;

    setUp(() {
      root = Directory.systemTemp.createTempSync('design_lint_dart_');
      output = BufferedOutput();
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    void write(String relativePath, String content) {
      File(p.join(root.path, relativePath))
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    Future<int> lintDart([List<String> extra = const <String>[]]) {
      final cmd = DesignLintCommand(projectRoot: root.path);
      return cmd.handle(_ctx(output, <String>['--dart', ...extra]));
    }

    for (final literal in <String>[
      'Color(0xFF112233)',
      'Color.fromARGB(255, 17, 34, 51)',
      'Color.fromRGBO(17, 34, 51, 1)',
      'Colors.red',
    ]) {
      test('reports $literal as path:line and exits 1', () async {
        write('lib/ui/card.dart', 'import "x.dart";\n\nfinal c = $literal;\n');

        final code = await lintDart();

        expect(code, 1);
        expect(
          output.content,
          contains('lib/ui/card.dart:3: raw colour literal'),
        );
        expect(output.content, contains('[ERROR] 1 raw colour literal(s)'));
      });
    }

    test('exits 0 on a clean tree without reading DESIGN.md', () async {
      write(
        'lib/clean.dart',
        '// Colors.red\n'
            '/// Never `Color(0xFF112233)`.\n'
            '/* Color.fromARGB(255, 0, 0, 0)\n'
            '   Color.fromRGBO(0, 0, 0, 1) */\n'
            'final first = kBrandColors.first;\n'
            "final url = 'https://x.dev/a'; final ok = 1;\n",
      );

      final code = await lintDart();

      expect(code, 0);
      expect(output.content, isNot(contains('[ERROR]')));
      expect(output.content, isNot(contains('DESIGN.md not found')));
    });

    test('ignores --input in --dart mode', () async {
      write('lib/clean.dart', 'final ok = 1;\n');

      final code = await lintDart(<String>['--input=MISSING.md']);

      expect(code, 0);
    });

    test(
      'exits 1 when the project has no lib/, rather than pass empty',
      () async {
        final code = await lintDart();

        expect(code, 1);
        expect(output.content, contains('[ERROR] No lib/ directory'));
      },
    );

    test('prints hits as plain lines, not styled error output', () async {
      write('lib/ui/card.dart', 'final c = Colors.red;\n');

      await lintDart();

      expect(output.content, isNot(contains('[ERROR] lib/ui/card.dart')));
    });

    test('finds a hit after a triple-quoted string holding //', () async {
      write(
        'lib/doc.dart',
        "const help = '''\n"
            'see https://x.dev // not a comment\n'
            "''';\n"
            'final c = Colors.red;\n',
      );

      final code = await lintDart();

      expect(code, 1);
      expect(output.content, contains('lib/doc.dart:4: '));
      expect(output.content, isNot(contains('lib/doc.dart:2:')));
    });

    test('skips an allowlisted file and directory prefix', () async {
      write('lib/config/wind_theme.g.dart', 'final c = Color(0xFF112233);\n');
      write('lib/generated/a/b.dart', 'final c = Colors.red;\n');
      write(
        '.design-token-allowlist',
        '# Generated\n'
            'lib/config/wind_theme.g.dart | design:sync output\n'
            'lib/generated/ | generated tree\n',
      );

      final code = await lintDart();

      expect(code, 0);
    });

    test('reads the allowlist from --allowlist', () async {
      write('lib/legacy.dart', 'final c = Colors.red;\n');
      write('tool/colours.allow', 'lib/legacy.dart | legacy\n');

      final code = await lintDart(<String>['--allowlist=tool/colours.allow']);

      expect(code, 0);
    });

    test('never scans test/', () async {
      write('lib/clean.dart', 'final ok = 1;\n');
      write('test/widget_test.dart', 'final c = Colors.red;\n');

      final code = await lintDart();

      expect(code, 0);
    });
  });
}

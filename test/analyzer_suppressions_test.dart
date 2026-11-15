import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The package lints with zero suppressions: an issue is fixed where it
/// arises, so an `ignore` comment or a severity downgraded to `ignore` in
/// `analysis_options.yaml` hides a defect instead of recording one.
void main() {
  // `flutter test` runs from the package root.
  final String root = Directory.current.path;

  // Matches an analyzer directive comment, `ignore` or `ignore_for_file`.
  final RegExp directive = RegExp(r'//\s*ignore(_for_file)?\s*:');

  test('no Dart source carries an analyzer ignore directive', () {
    final List<String> offenders = <String>[
      for (final String dir in <String>['lib', 'test', 'bin', 'example/lib'])
        for (final File file in _dartFiles(p.join(root, dir)))
          for (final (int index, String line) in file.readAsLinesSync().indexed)
            if (directive.hasMatch(line))
              '${p.relative(file.path, from: root)}:${index + 1}',
    ];

    expect(offenders, isEmpty);
  });

  test('no analysis_options.yaml downgrades a diagnostic to ignore', () {
    final List<String> offenders = <String>[
      for (final String path in <String>[
        'analysis_options.yaml',
        'example/analysis_options.yaml',
      ])
        for (final String code in _ignoredDiagnostics(
          File(p.join(root, path)).readAsStringSync(),
        ))
          '$path: $code',
    ];

    expect(offenders, isEmpty);
  });

  test('the options check sees a commented or quoted ignore', () {
    const String options = '''
analyzer:
  errors:
    deprecated_member_use: ignore # temporary
    unused_import: 'ignore'
    todo: info
''';

    expect(_ignoredDiagnostics(options), [
      'deprecated_member_use',
      'unused_import',
    ]);
  });
}

/// The diagnostic codes an analysis_options.yaml downgrades to `ignore`.
///
/// Parsed, not matched line by line, so a trailing comment or a quoted value
/// cannot hide an entry.
List<String> _ignoredDiagnostics(String options) {
  final Object? document = loadYaml(options);
  if (document is! YamlMap) return const <String>[];

  final Object? analyzer = document['analyzer'];
  final Object? errors = analyzer is YamlMap ? analyzer['errors'] : null;
  if (errors is! YamlMap) return const <String>[];

  return <String>[
    for (final MapEntry<dynamic, dynamic> entry in errors.entries)
      if (entry.value == 'ignore') '${entry.key}',
  ];
}

Iterable<File> _dartFiles(String dir) {
  final Directory directory = Directory(dir);
  if (!directory.existsSync()) return const <File>[];

  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((File file) => file.path.endsWith('.dart'));
}

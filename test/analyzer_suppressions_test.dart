import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
        for (final String line in File(p.join(root, path)).readAsLinesSync())
          if (RegExp(r'^\s+\w+:\s*ignore\s*$').hasMatch(line))
            '$path: ${line.trim()}',
    ];

    expect(offenders, isEmpty);
  });
}

Iterable<File> _dartFiles(String dir) {
  final Directory directory = Directory(dir);
  if (!directory.existsSync()) return const <File>[];

  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((File file) => file.path.endsWith('.dart'));
}

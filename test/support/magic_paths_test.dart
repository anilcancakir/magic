import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:path/path.dart' as p;

const MethodChannel _pathProviderChannel = MethodChannel(
  'plugins.flutter.io/path_provider',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documentsDir;
  late Directory cacheDir;
  late List<String> asked;

  setUp(() {
    documentsDir = Directory.systemTemp.createTempSync('magic_paths_docs_');
    cacheDir = Directory.systemTemp.createTempSync('magic_paths_cache_');
    asked = <String>[];

    // The two directories are told apart by the method asked, so a test fails
    // when the wrong one is resolved rather than passing on a shared answer.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (
          MethodCall call,
        ) async {
          asked.add(call.method);

          return switch (call.method) {
            'getApplicationDocumentsDirectory' => documentsDir.path,
            'getApplicationCacheDirectory' => cacheDir.path,
            _ => null,
          };
        });
  });

  tearDown(() {
    MagicPlatform.debugTvOSOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    for (final Directory dir in <Directory>[documentsDir, cacheDir]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  group('MagicPaths.appData', () {
    test('is the documents directory off tvOS', () async {
      MagicPlatform.debugTvOSOverride = false;

      final Directory dir = await MagicPaths.appData();

      expect(dir.path, documentsDir.path);
      expect(asked, <String>['getApplicationDocumentsDirectory']);
    });

    test('is app_data under the cache directory on tvOS', () async {
      MagicPlatform.debugTvOSOverride = true;

      final Directory dir = await MagicPaths.appData();

      expect(dir.path, p.join(cacheDir.path, 'app_data'));
      expect(asked, <String>['getApplicationCacheDirectory']);
    });

    test('creates the tvOS directory when it is missing', () async {
      MagicPlatform.debugTvOSOverride = true;
      expect(
        Directory(p.join(cacheDir.path, 'app_data')).existsSync(),
        isFalse,
      );

      final Directory dir = await MagicPaths.appData();

      expect(dir.existsSync(), isTrue);
    });

    test('keeps what a tvOS directory already holds', () async {
      MagicPlatform.debugTvOSOverride = true;
      final File kept = File(p.join(cacheDir.path, 'app_data', 'kept.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync('kept');

      await MagicPaths.appData();

      expect(kept.readAsStringSync(), 'kept');
    });
  });
}

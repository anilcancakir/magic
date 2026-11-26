import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'magic_platform.dart';

/// Where an app keeps its files on disk (IO implementation).
class MagicPaths {
  MagicPaths._();

  /// The directory the app keeps its own data in, created when missing.
  ///
  /// The documents directory everywhere except tvOS. An Apple TV denies writes
  /// to Documents and cannot create Application Support, so the data lives in
  /// `app_data` under the cache directory instead. The system may purge
  /// `Library/Caches` when storage runs low, so what is kept there must be
  /// rebuildable.
  static Future<Directory> appData() async {
    if (!MagicPlatform.isTvOS) {
      return getApplicationDocumentsDirectory();
    }

    final Directory cache = await getApplicationCacheDirectory();

    return Directory(p.join(cache.path, 'app_data')).create(recursive: true);
  }
}

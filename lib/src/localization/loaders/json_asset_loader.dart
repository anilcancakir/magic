import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:magic/magic.dart';

import 'debug_asset_reader_stub.dart'
    if (dart.library.io) 'debug_asset_reader_io.dart'
    if (dart.library.js_interop) 'debug_asset_reader_web.dart';

/// The JSON Asset Loader.
///
/// Loads translation files from `assets/lang/{locale}.json`.
///
/// ## Setup
///
/// 1. Create translation files in `assets/lang/`:
///    - `assets/lang/en.json`
///    - `assets/lang/tr.json`
///
/// 2. Register in `pubspec.yaml`:
///    ```yaml
///    flutter:
///      assets:
///        - assets/lang/
///    ```
///
/// ## JSON Format
///
/// Supports nested keys that will be flattened:
///
/// ```json
/// {
///   "welcome": "Welcome, :name!",
///   "auth": {
///     "failed": "Login failed.",
///     "throttle": "Too many attempts."
///   }
/// }
/// ```
///
/// Becomes: `auth.failed`, `auth.throttle`
class JsonAssetLoader implements TranslationLoader {
  /// The base path for translation files.
  final String basePath;

  /// The fallback locale to use when the requested locale is not found.
  final String fallbackLocale;

  /// Whether this loader serves a package's catalogue, see [JsonAssetLoader.package].
  final bool _packageCatalogue;

  /// Create a new JSON asset loader.
  const JsonAssetLoader({
    this.basePath = 'assets/lang',
    this.fallbackLocale = 'en',
  }) : _packageCatalogue = false;

  /// A loader for a package's own catalogue, for `Lang.addSource`.
  ///
  /// The translator already falls back key by key and layers the host's
  /// catalogue over every package's, so this loader never falls back to
  /// another file itself: a package's own `en.json` would otherwise answer a
  /// locale it has no file for and outrank the host's English. A locale with no
  /// file is an empty layer, answered quietly; a file that is there but will
  /// not parse is logged (when a `log` service is bound) and is empty too.
  ///
  /// ```dart
  /// Lang.addSource(
  ///   'magic_starter',
  ///   const JsonAssetLoader.package(basePath: 'packages/magic_starter/assets/lang'),
  /// );
  /// ```
  const JsonAssetLoader.package({required this.basePath})
    : fallbackLocale = 'en',
      _packageCatalogue = true;

  /// Reads [locale]'s catalogue, falling back to [fallbackLocale]'s whole file
  /// (never for a [JsonAssetLoader.package] loader).
  ///
  /// **An empty map is the failure, and it used to be a silent one.** Every
  /// caller reads a miss as a key rendering as itself, so a catalogue that did
  /// not load and a catalogue with a missing key are indistinguishable on
  /// screen. The warnings below are what tell them apart, and they are guarded
  /// on `Magic.bound('log')` for exactly the reason
  /// `Translator._loadFallbackFor` already records: `Log` resolves `log`
  /// through the container and THROWS for an unbound key, so logging a failure
  /// unguarded would replace it with a different one.
  @override
  Future<Map<String, dynamic>> load(Locale locale) async {
    try {
      final json = await _loadJson(locale.languageCode);
      return flatten(json);
    } catch (e) {
      if (_packageCatalogue) {
        // Only a file that exists and is broken is worth a line; a locale the
        // package has no file for is the normal case.
        if ((e is FormatException || e is TypeError) && Magic.bound('log')) {
          Log.warning(
            'Could not read the [$basePath/${locale.languageCode}.json] '
            'translations: $e. That package contributes nothing for it.',
          );
        }

        return {};
      }

      // Try fallback locale
      if (locale.languageCode != fallbackLocale) {
        try {
          final json = await _loadJson(fallbackLocale);
          return flatten(json);
        } catch (fallbackError) {
          if (Magic.bound('log')) {
            Log.warning(
              'Could not load translations for [${locale.languageCode}] '
              '($e) or for the fallback [$fallbackLocale] ($fallbackError). '
              'Every key will render as itself.',
            );
          }

          return {};
        }
      }

      if (Magic.bound('log')) {
        Log.warning(
          'Could not load translations for [${locale.languageCode}] from '
          '[$basePath] ($e). Every key will render as itself.',
        );
      }

      return {};
    }
  }

  /// Load and parse JSON file.
  ///
  /// **Reads nothing out of the container, deliberately.** This used to open
  /// with `Log.info('Loading translation file [$path]')`, and `Log` resolves
  /// `log` through the container, which throws for an unbound key
  /// (`foundation/application.dart:269-274`). [load]'s catch then turned that
  /// throw into an empty catalogue, so a host that loads translations before
  /// its logging provider boots, or a widget test that never calls
  /// `Magic.init`, got every key rendering as itself with nothing to read.
  ///
  /// Measured from a consumer app's test: `rootBundle` reads the asset fine
  /// (19,345 bytes), `Translator.load` reports `loaded: true` for the right
  /// locale, and this loader still answers zero keys.
  ///
  /// A loader that reads a file should not need a service to do it. The line
  /// is gone rather than guarded: it fired twice per `Translator.load`, once
  /// for the locale and once for the fallback, and nothing consumed it.
  Future<Map<String, dynamic>> _loadJson(String languageCode) async {
    final path = '$basePath/$languageCode.json';

    // In debug mode, attempt to bypass the asset bundle cache so that
    // hot restart picks up JSON changes. Best-effort: works reliably on
    // desktop and web; on mobile the file usually does not exist on disk,
    // so we fall back to rootBundle.
    if (kDebugMode) {
      final content = await debugReadAssetFile(path);

      if (content != null) {
        return jsonDecode(content) as Map<String, dynamic>;
      }
    }

    final content = await rootBundle.loadString(path);
    return jsonDecode(content) as Map<String, dynamic>;
  }

  /// Flatten nested JSON keys for O(1) lookup.
  ///
  /// Public so a caller building its own [TranslationLoader] (see
  /// `MagicTest.loadTranslations`) can flatten with the exact same rule the
  /// translator's own loader uses, rather than growing a second copy that
  /// silently drifts from this one.
  ///
  /// Example:
  /// ```dart
  /// JsonAssetLoader.flatten({'auth': {'failed': 'Error'}}); // {'auth.failed': 'Error'}
  /// ```
  static Map<String, dynamic> flatten(
    Map<String, dynamic> json, [
    String prefix = '',
  ]) {
    final result = <String, dynamic>{};

    for (final entry in json.entries) {
      final key = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';

      if (entry.value is Map<String, dynamic>) {
        result.addAll(flatten(entry.value as Map<String, dynamic>, key));
      } else {
        result[key] = entry.value;
      }
    }

    return result;
  }
}

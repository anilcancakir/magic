import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../support/date_manager.dart';
import 'contracts/translation_loader.dart';
import 'loaders/json_asset_loader.dart';
import 'message_selector.dart';
import '../facades/log.dart';
import '../foundation/magic.dart';
import '../facades/event.dart';
import '../foundation/events/app_events.dart';

/// The Translator Service.
///
/// Singleton service that manages translations and provides O(1) lookups.
/// Integrates with DateManager for consistent date localization.
/// Supports runtime locale switching with change notifications.
///
/// ## Usage
///
/// The Translator is typically accessed via the `Lang` facade or `trans()` helper:
///
/// ```dart
/// // Via facade
/// Lang.get('welcome', {'name': 'Magic'});
///
/// // Change locale at runtime
/// await Lang.setLocale(Locale('tr'));
///
/// // Detect device locale
/// Lang.detectLocale();
/// ```
class Translator extends ChangeNotifier {
  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------

  static Translator? _instance;

  /// Get the singleton instance.
  static Translator get instance {
    _instance ??= Translator._();
    return _instance!;
  }

  Translator._();

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /// The current locale.
  Locale _locale = const Locale('en');

  /// Supported locales (from config).
  List<Locale> _supportedLocales = [const Locale('en')];

  /// The translation sentences (flattened keys).
  Map<String, String> _sentences = {};

  /// The translation loader.
  TranslationLoader _loader = const JsonAssetLoader();

  /// Whether translations have been loaded.
  bool _loaded = false;

  /// The fallback locale.
  Locale _fallbackLocale = const Locale('en');

  /// Package catalogues keyed by package name, in registration order.
  ///
  /// A `LinkedHashMap`, so assigning an existing key replaces the loader and
  /// keeps its position.
  final Map<String, TranslationLoader> _sources = <String, TranslationLoader>{};

  /// Bumped by every [addSource]; [_mergedSourcesVersion] is the value the
  /// current catalogue was merged at. They differ while a registered source is
  /// missing from the catalogue, which is when [load] must not return early.
  int _sourcesVersion = 0;
  int _mergedSourcesVersion = 0;

  /// Taken by every [load]; a load that finds a newer one started after it
  /// leaves the catalogue to that one.
  int _loadGeneration = 0;

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  /// Set the translation loader.
  void setLoader(TranslationLoader loader) {
    _loader = loader;
  }

  /// Register [package]'s own catalogue beneath the host's.
  ///
  /// Package keys are flat and shared with the host and with every other
  /// package, so `common.back` from a package answers `trans('common.back')`.
  /// The host's value for a locale always beats a package's; between packages
  /// the later registration wins. Registering [package] again replaces its
  /// loader and keeps its position.
  ///
  /// The intended place is a provider's `register()`, which runs before the
  /// localisation provider's `boot()` loads the catalogue. A source added
  /// after that shows from the next [load] or [setLocale].
  void addSource(String package, TranslationLoader loader) {
    _sources[package] = loader;
    _sourcesVersion++;
  }

  /// Set supported locales.
  void setSupportedLocales(List<Locale> locales) {
    _supportedLocales = locales;
  }

  /// Set the fallback locale.
  void setFallbackLocale(Locale locale) {
    _fallbackLocale = locale;
  }

  /// Get the fallback locale.
  Locale get fallbackLocale => _fallbackLocale;

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  /// Load translations for the given locale.
  ///
  /// This method:
  /// 1. Loads the fallback catalogue, then [locale]'s, and layers the second
  ///    over the first so a key missing from [locale] is served by the
  ///    fallback
  /// 2. Flattens and caches the sentences
  /// 3. Syncs DateManager locale for date formatting
  /// 4. Notifies listeners of the locale change
  ///
  /// ### Why the fallback is merged rather than chosen
  ///
  /// [get] answers `_sentences[key] ?? key`, and the only fallback that
  /// existed was `JsonAssetLoader`'s, which is whole-FILE: it reads the
  /// fallback catalogue when the requested one fails to load at all, and never
  /// when the requested one loads and is simply incomplete. A half-translated
  /// app therefore rendered raw dotted keys on screen rather than the English
  /// sentence sitting in its own `en.json`.
  ///
  /// Merging here rather than in the loader is deliberate: this class owns
  /// [fallbackLocale], and every [TranslationLoader] a host writes gets the
  /// behaviour without knowing about it.
  ///
  /// ### Package sources
  ///
  /// Catalogues registered with [addSource] layer in below the host for each
  /// locale, lowest to highest: packages for [fallbackLocale], host for
  /// [fallbackLocale], packages for [locale], host for [locale]. So the host
  /// beats a package within a locale, and a package's [locale] string beats
  /// the host's fallback string.
  Future<void> load(Locale locale) async {
    if (_loaded &&
        _mergedSourcesVersion == _sourcesVersion &&
        _locale == locale) {
      return;
    }

    // Taken before the reads start and stored only once the merge lands: a
    // source registered while they are in flight, or a host loader that
    // throws, leaves the next load to merge again.
    final mergedVersion = _sourcesVersion;
    final generation = ++_loadGeneration;
    final sources = _sources.entries.toList();
    final fallbackConflicts = <String, Set<String>>{};
    final ownConflicts = <String, Set<String>>{};

    // Every read starts before any is awaited, and they are joined so a host
    // loader that fails while a package read is pending still reaches the
    // caller, rather than the zone. A locale with a fallback pays one round
    // trip, not one per catalogue. The spread order below is what decides
    // precedence, and it is unaffected by the order the reads complete in.
    final layers = await Future.wait<Map<String, dynamic>>([
      _isFallback(locale)
          ? Future.value(const <String, dynamic>{})
          : _loadSources(sources, _fallbackLocale, fallbackConflicts),
      _loadFallbackFor(locale),
      _loadSources(sources, locale, ownConflicts),
      _loader.load(locale),
    ]);

    // A load that began after this one owns the catalogue: writing now would
    // put an older merge, one that may lack a source registered since, over it.
    if (generation != _loadGeneration) return;

    final data = <String, dynamic>{
      ...layers[0],
      ...layers[1],
      ...layers[2],
      ...layers[3],
    };

    _warnAboutConflicts(fallbackConflicts, _fallbackLocale);
    _warnAboutConflicts(ownConflicts, locale);

    // Convert all values to strings
    _sentences = data.map((key, value) => MapEntry(key, value.toString()));
    _locale = locale;
    _mergedSourcesVersion = mergedVersion;

    // Sync DateManager locale for date formatting (Carbon)
    await _syncDateManagerLocale(locale);

    _loaded = true;
    notifyListeners();
    await Event.dispatch(LocaleChanged(locale));
  }

  /// The fallback catalogue to layer [locale]'s own strings over.
  ///
  /// Empty when [locale] IS the fallback, so that case reads its file once
  /// rather than twice and never merges a map with itself.
  ///
  /// A fallback that will not load answers empty rather than throwing. It is a
  /// courtesy and never a requirement: a missing or broken fallback catalogue
  /// must not take the locale's own strings down with it, which is the one
  /// thing worse than a raw key on screen.
  Future<Map<String, dynamic>> _loadFallbackFor(Locale locale) async {
    if (_isFallback(locale)) {
      return const <String, dynamic>{};
    }

    try {
      return await _loader.load(_fallbackLocale);
    } on Object catch (error) {
      // `Log.warning` resolves `log` through the container, which THROWS for
      // an unbound key (`foundation/application.dart:269-274`). So logging
      // here unguarded would defeat the whole point of this catch: a widget
      // test that builds `MaterialApp` through `LangDelegate` without a full
      // `Magic.init()`, or a locale switch before `LogServiceProvider` boots,
      // would take the exception straight out of `load()`.
      if (Magic.bound('log')) {
        Log.warning(
          'Could not load the fallback locale '
          '[${_fallbackLocale.languageCode}]: $error. Keys missing from '
          '[${locale.languageCode}] will render as themselves.',
        );
      }

      return const <String, dynamic>{};
    }
  }

  /// Whether [locale] is the fallback locale, compared by language code.
  bool _isFallback(Locale locale) =>
      locale.languageCode == _fallbackLocale.languageCode;

  /// Every package catalogue for [locale], merged in registration order.
  ///
  /// A key two packages give different values is recorded in [conflicts]
  /// against both package names; equal values are the normal case for shared
  /// keys such as `common.back` and record nothing.
  Future<Map<String, dynamic>> _loadSources(
    List<MapEntry<String, TranslationLoader>> sources,
    Locale locale,
    Map<String, Set<String>> conflicts,
  ) async {
    final reads = [
      for (final source in sources)
        _loadSource(source.key, source.value, locale),
    ];

    final merged = <String, dynamic>{};
    final owners = <String, String>{};

    for (var i = 0; i < sources.length; i++) {
      final package = sources[i].key;

      for (final entry in (await reads[i]).entries) {
        final previous = owners[entry.key];

        if (previous != null &&
            merged[entry.key].toString() != entry.value.toString()) {
          conflicts.putIfAbsent(entry.key, () => <String>{})
            ..add(previous)
            ..add(package);
        }

        merged[entry.key] = entry.value;
        owners[entry.key] = package;
      }
    }

    return merged;
  }

  /// [package]'s catalogue for [locale], or an empty map when it will not load.
  ///
  /// A package catalogue is never a requirement, for the same reason the
  /// fallback is not (see [_loadFallbackFor]): one broken package must not take
  /// the host's strings, or another package's, down with it.
  Future<Map<String, dynamic>> _loadSource(
    String package,
    TranslationLoader loader,
    Locale locale,
  ) async {
    try {
      // Flattened as the host's own loader's output is, so a nested map and a
      // dotted key name one key and a conflict between packages is seen.
      return JsonAssetLoader.flatten(await loader.load(locale));
    } on Object catch (error) {
      // Guarded for the reason `_loadFallbackFor` records.
      if (Magic.bound('log')) {
        Log.warning(
          'Could not load the [$package] translations for '
          '[${locale.languageCode}]: $error. Its keys fall back to the host '
          'and the other packages.',
        );
      }

      return const <String, dynamic>{};
    }
  }

  /// One warning per key that two or more packages give different values for
  /// in [locale]'s catalogue.
  void _warnAboutConflicts(Map<String, Set<String>> conflicts, Locale locale) {
    if (conflicts.isEmpty || !Magic.bound('log')) return;

    for (final conflict in conflicts.entries) {
      Log.warning(
        'Translation key [${conflict.key}] has different values in the '
        '[${conflict.value.join(', ')}] packages for '
        '[${locale.languageCode}]; a value the host defines for the key wins.',
      );
    }
  }

  /// Switch to a new locale at runtime.
  ///
  /// ```dart
  /// await Translator.instance.setLocale(Locale('tr'));
  /// ```
  Future<void> setLocale(Locale locale) async {
    // Force reload even if already loaded
    _loaded = false;
    await load(locale);
  }

  /// Detect and set the best matching locale from device/browser.
  ///
  /// Matches the device locale against supported locales.
  /// Falls back to first supported locale if no match.
  ///
  /// ```dart
  /// await Translator.instance.detectAndSetLocale();
  /// ```
  Future<Locale> detectAndSetLocale() async {
    final detected = detectLocale();
    await setLocale(detected);
    return detected;
  }

  /// Detect the best matching locale from device/browser.
  ///
  /// Does NOT change the current locale, just returns the best match.
  Locale detectLocale() {
    // Get device locale
    final deviceLocale = PlatformDispatcher.instance.locale;

    // Try exact match
    for (final supported in _supportedLocales) {
      if (supported.languageCode == deviceLocale.languageCode &&
          (supported.countryCode == null ||
              supported.countryCode == deviceLocale.countryCode)) {
        return supported;
      }
    }

    // Try language-only match
    for (final supported in _supportedLocales) {
      if (supported.languageCode == deviceLocale.languageCode) {
        return supported;
      }
    }

    // Fallback to first supported
    return _supportedLocales.isNotEmpty
        ? _supportedLocales.first
        : const Locale('en');
  }

  /// Sync DateManager locale for Carbon date formatting.
  Future<void> _syncDateManagerLocale(Locale locale) async {
    try {
      await DateManager.instance.setLocale(locale.languageCode);
    } catch (_) {
      // DateManager might not be booted, ignore errors
    }
  }

  // ---------------------------------------------------------------------------
  // Translation
  // ---------------------------------------------------------------------------

  /// Get a translation by key.
  ///
  /// Supports `:key` replacements:
  ///
  /// ```dart
  /// // JSON: "welcome": "Welcome, :name!"
  /// translator.get('welcome', {'name': 'Magic'});
  /// // Returns: "Welcome, Magic!"
  /// ```
  String get(String key, [Map<String, dynamic>? replace]) {
    return _replace(_sentences[key] ?? key, replace);
  }

  /// Substitutes every `:name` in [sentence] from [replace].
  ///
  /// A plain `replaceAll` with no word boundary, so `:count` inside `:counts`
  /// is replaced too. That is Laravel's behaviour and it is what lets a
  /// catalogue abut a unit to its number, which several languages need.
  String _replace(String sentence, Map<String, dynamic>? replace) {
    if (replace == null) return sentence;

    var out = sentence;
    for (final entry in replace.entries) {
      out = out.replaceAll(':${entry.key}', entry.value.toString());
    }

    return out;
  }

  /// Get a translation by key, choosing the form that suits [number].
  ///
  /// Laravel's `trans_choice`. The sentence is a pipe-separated line and
  /// [MessageSelector] picks a segment from it, by the CURRENT locale's own
  /// plural rules rather than by English's:
  ///
  /// ```dart
  /// // JSON: "apples": "There is one apple|There are :count apples"
  /// translator.choice('apples', 1); // "There is one apple"
  /// translator.choice('apples', 4); // "There are 4 apples"
  /// ```
  ///
  /// `:count` is substituted from [number] without the caller passing it, and
  /// an explicit `count` in [replace] still wins. A key with no sentence
  /// answers the key, which is [get]'s own contract.
  String choice(String key, int number, [Map<String, dynamic>? replace]) {
    final line = _sentences[key];
    if (line == null) return key;

    final chosen = MessageSelector.choose(line, number, _locale.languageCode);

    return _replace(chosen, <String, dynamic>{'count': number, ...?replace});
  }

  /// Check if a translation exists.
  bool has(String key) => _sentences.containsKey(key);

  // ---------------------------------------------------------------------------
  // Accessors
  // ---------------------------------------------------------------------------

  /// Get the current locale.
  Locale get locale => _locale;

  /// Get supported locales.
  List<Locale> get supportedLocales => List.unmodifiable(_supportedLocales);

  /// Check if translations are loaded.
  bool get isLoaded => _loaded;

  /// Get all loaded sentences.
  Map<String, String> get sentences => Map.unmodifiable(_sentences);

  // ---------------------------------------------------------------------------
  // Testing
  // ---------------------------------------------------------------------------

  /// Reset the translator (for testing).
  static void reset() {
    _instance?.dispose();
    _instance = null;
  }
}

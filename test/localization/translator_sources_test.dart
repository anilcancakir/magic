import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart' show Log, Magic, MagicApp;
import 'package:magic/src/localization/contracts/translation_loader.dart';
import 'package:magic/src/localization/loaders/json_asset_loader.dart';
import 'package:magic/src/localization/translator.dart';

/// Serves one catalogue per language from a map and records what it was asked.
class _RecordingLoader implements TranslationLoader {
  _RecordingLoader(this._locales, {this.throwsFor});

  final Map<String, Map<String, dynamic>> _locales;

  /// Language code this loader refuses outright, so a test reaches the
  /// failure branch rather than the empty-map one.
  final String? throwsFor;

  final List<String> asked = <String>[];

  @override
  Future<Map<String, dynamic>> load(Locale locale) async {
    asked.add(locale.languageCode);

    if (locale.languageCode == throwsFor) {
      throw StateError('no catalogue for ${locale.languageCode}');
    }

    return Map<String, dynamic>.from(_locales[locale.languageCode] ?? {});
  }
}

/// A loader that throws before it returns a future, as a plain function does.
class _SyncThrowingLoader implements TranslationLoader {
  @override
  Future<Map<String, dynamic>> load(Locale locale) {
    throw StateError('thrown synchronously');
  }
}

/// A loader that answers when [release] completes, so a test holds one load
/// open while it registers a source.
class _GatedLoader implements TranslationLoader {
  _GatedLoader(this._data);

  final Map<String, dynamic> _data;
  final Completer<void> release = Completer<void>();

  @override
  Future<Map<String, dynamic>> load(Locale locale) async {
    await release.future;
    return Map<String, dynamic>.from(_data);
  }
}

/// Answers every locale at once except [gated], whose read waits for [release].
class _GatedLocaleLoader implements TranslationLoader {
  _GatedLocaleLoader(this._data, {required this.gated});

  final Map<String, Map<String, dynamic>> _data;
  final String gated;
  final Completer<void> release = Completer<void>();

  @override
  Future<Map<String, dynamic>> load(Locale locale) async {
    if (locale.languageCode == gated) await release.future;
    return Map<String, dynamic>.from(_data[locale.languageCode] ?? {});
  }
}

/// Never answers, as a package read that hangs would not.
class _HangingLoader implements TranslationLoader {
  @override
  Future<Map<String, dynamic>> load(Locale locale) =>
      Completer<Map<String, dynamic>>().future;
}

/// Holds its first read until [release] completes; every later read answers at
/// once, so a test finishes a second load before the first one lands.
class _FirstReadGatedLoader implements TranslationLoader {
  _FirstReadGatedLoader(this._data);

  final Map<String, dynamic> _data;
  final Completer<void> release = Completer<void>();
  bool _first = true;

  @override
  Future<Map<String, dynamic>> load(Locale locale) async {
    if (_first) {
      _first = false;
      await release.future;
    }
    return Map<String, dynamic>.from(_data);
  }
}

/// Package catalogues registered with `Translator.addSource`.
///
/// Merge order for locale L with fallback F, lowest to highest: package
/// sources for F, host for F, package sources for L, host for L.
void main() {
  group('Translator.addSource', () {
    setUp(() {
      MagicApp.reset();
      Magic.flush();
      Translator.reset();
      Translator.instance.setFallbackLocale(const Locale('en'));
    });

    test('the host beats a package for the same locale', () async {
      Translator.instance.setLoader(
        _RecordingLoader({
          'en': {'common.back': 'Go back'},
        }),
      );
      Translator.instance.addSource(
        'starter',
        _RecordingLoader({
          'en': {'common.back': 'Back', 'starter.title': 'Starter'},
        }),
      );

      await Translator.instance.load(const Locale('en'));

      expect(Translator.instance.get('common.back'), 'Go back');
      expect(Translator.instance.get('starter.title'), 'Starter');
    });

    test('a package string for L beats the host string for F', () async {
      Translator.instance.setLoader(
        _RecordingLoader({
          'en': {'common.back': 'Back'},
          'tr': <String, dynamic>{},
        }),
      );
      Translator.instance.addSource(
        'starter',
        _RecordingLoader({
          'tr': {'common.back': 'Geri'},
        }),
      );

      await Translator.instance.load(const Locale('tr'));

      expect(Translator.instance.get('common.back'), 'Geri');
    });

    test('the host string for L beats a package string for L', () async {
      Translator.instance.setLoader(
        _RecordingLoader({
          'tr': {'common.back': 'Geri dön'},
        }),
      );
      Translator.instance.addSource(
        'starter',
        _RecordingLoader({
          'tr': {'common.back': 'Geri'},
        }),
      );

      await Translator.instance.load(const Locale('tr'));

      expect(Translator.instance.get('common.back'), 'Geri dön');
    });

    test('F is the floor: a package F string fills a key L lacks', () async {
      Translator.instance.setLoader(
        _RecordingLoader({
          'tr': {'greeting': 'Merhaba'},
        }),
      );
      Translator.instance.addSource(
        'starter',
        _RecordingLoader({
          'en': {'starter.title': 'Starter'},
        }),
      );

      await Translator.instance.load(const Locale('tr'));

      expect(Translator.instance.get('greeting'), 'Merhaba');
      expect(Translator.instance.get('starter.title'), 'Starter');
    });

    test('when L is F each package is read once', () async {
      final package = _RecordingLoader({
        'en': {'starter.title': 'Starter'},
      });
      Translator.instance.setLoader(_RecordingLoader({'en': {}}));
      Translator.instance.addSource('starter', package);

      await Translator.instance.load(const Locale('en'));

      expect(package.asked, <String>['en']);
      expect(Translator.instance.get('starter.title'), 'Starter');
    });

    test('the later registration wins a shared key', () async {
      Translator.instance.setLoader(_RecordingLoader({'en': {}}));
      Translator.instance.addSource(
        'starter',
        _RecordingLoader({
          'en': {'common.back': 'Back'},
        }),
      );
      Translator.instance.addSource(
        'notifications',
        _RecordingLoader({
          'en': {'common.back': 'Return'},
        }),
      );

      await Translator.instance.load(const Locale('en'));

      expect(Translator.instance.get('common.back'), 'Return');
    });

    test('equal shared values are silent', () async {
      final log = Log.fake();
      Translator.instance.setLoader(_RecordingLoader({'en': {}}));
      Translator.instance.addSource(
        'starter',
        _RecordingLoader({
          'en': {'common.back': 'Back'},
        }),
      );
      Translator.instance.addSource(
        'notifications',
        _RecordingLoader({
          'en': {'common.back': 'Back'},
        }),
      );

      await Translator.instance.load(const Locale('en'));

      log.assertNothingLogged();
    });

    test(
      'different shared values warn once per locale, naming both packages',
      () async {
        final log = Log.fake();
        Translator.instance.setLoader(_RecordingLoader({'en': {}, 'tr': {}}));
        Translator.instance.addSource(
          'starter',
          _RecordingLoader({
            'en': {'common.back': 'Back'},
            'tr': {'common.back': 'Geri'},
          }),
        );
        Translator.instance.addSource(
          'notifications',
          _RecordingLoader({
            'en': {'common.back': 'Return'},
            'tr': {'common.back': 'Dön'},
          }),
        );

        await Translator.instance.load(const Locale('tr'));

        expect(log.entries, hasLength(2));
        for (final entry in log.entries) {
          expect(entry.level, 'warning');
          expect(entry.message, contains('common.back'));
          expect(entry.message, contains('starter'));
          expect(entry.message, contains('notifications'));
        }
        expect(log.entries.first.message, contains('[en]'));
        expect(log.entries.last.message, contains('[tr]'));
        expect(Translator.instance.get('common.back'), 'Dön');
      },
    );

    test('a different value warns nothing when no logger is bound', () async {
      expect(Magic.bound('log'), isFalse);
      Translator.instance.setLoader(_RecordingLoader({'en': {}}));
      Translator.instance.addSource(
        'starter',
        _RecordingLoader({
          'en': {'common.back': 'Back'},
        }),
      );
      Translator.instance.addSource(
        'notifications',
        _RecordingLoader({
          'en': {'common.back': 'Return'},
        }),
      );

      await expectLater(
        Translator.instance.load(const Locale('en')),
        completes,
      );
      expect(Translator.instance.get('common.back'), 'Return');
    });

    test('registering a package again replaces it in place', () async {
      Translator.instance.setLoader(_RecordingLoader({'en': {}}));
      Translator.instance.addSource(
        'starter',
        _RecordingLoader({
          'en': {'common.back': 'Old'},
        }),
      );
      Translator.instance.addSource(
        'notifications',
        _RecordingLoader({
          'en': {'common.back': 'Return'},
        }),
      );
      final replacement = _RecordingLoader({
        'en': {'common.back': 'New', 'starter.title': 'Starter'},
      });
      Translator.instance.addSource('starter', replacement);

      await Translator.instance.load(const Locale('en'));

      // Still registered before `notifications`, so it still loses the key.
      expect(Translator.instance.get('common.back'), 'Return');
      expect(Translator.instance.get('starter.title'), 'Starter');
      expect(replacement.asked, <String>['en']);
    });

    test('a package loader that throws is skipped', () async {
      Translator.instance.setLoader(
        _RecordingLoader({
          'tr': {'greeting': 'Merhaba'},
        }),
      );
      Translator.instance.addSource(
        'broken',
        _RecordingLoader(<String, Map<String, dynamic>>{}, throwsFor: 'tr'),
      );
      Translator.instance.addSource(
        'starter',
        _RecordingLoader({
          'tr': {'starter.title': 'Başlangıç'},
        }),
      );

      await expectLater(
        Translator.instance.load(const Locale('tr')),
        completes,
      );
      expect(Translator.instance.get('greeting'), 'Merhaba');
      expect(Translator.instance.get('starter.title'), 'Başlangıç');
    });

    test('a throwing package loader warns through a bound logger', () async {
      final log = Log.fake();
      Translator.instance.setLoader(_RecordingLoader({'en': {}}));
      Translator.instance.addSource(
        'broken',
        _RecordingLoader(<String, Map<String, dynamic>>{}, throwsFor: 'en'),
      );

      await Translator.instance.load(const Locale('en'));

      expect(log.entries, hasLength(1));
      expect(log.entries.single.level, 'warning');
      expect(log.entries.single.message, contains('broken'));
    });

    test('a package with no catalogue for the locale adds nothing', () async {
      Translator.instance.setLoader(
        _RecordingLoader({
          'en': {'greeting': 'Hello'},
        }),
      );
      Translator.instance.addSource(
        'empty',
        _RecordingLoader(<String, Map<String, dynamic>>{}),
      );

      await Translator.instance.load(const Locale('en'));

      expect(Translator.instance.sentences, {'greeting': 'Hello'});
    });

    test('a source added after load shows after the next load', () async {
      Translator.instance.setLoader(
        _RecordingLoader({
          'en': {'greeting': 'Hello'},
        }),
      );
      await Translator.instance.load(const Locale('en'));

      Translator.instance.addSource(
        'starter',
        _RecordingLoader({
          'en': {'starter.title': 'Starter'},
        }),
      );
      expect(Translator.instance.has('starter.title'), isFalse);

      await Translator.instance.load(const Locale('en'));

      expect(Translator.instance.get('starter.title'), 'Starter');
      expect(Translator.instance.get('greeting'), 'Hello');
    });

    test('a load with no new source still returns early', () async {
      final host = _RecordingLoader({
        'en': {'greeting': 'Hello'},
      });
      Translator.instance.setLoader(host);
      Translator.instance.addSource(
        'starter',
        _RecordingLoader({
          'en': {'starter.title': 'Starter'},
        }),
      );

      await Translator.instance.load(const Locale('en'));
      await Translator.instance.load(const Locale('en'));

      expect(host.asked, <String>['en']);
    });

    test('Translator.reset() clears the sources', () async {
      Translator.instance.addSource(
        'starter',
        _RecordingLoader({
          'en': {'starter.title': 'Starter'},
        }),
      );

      Translator.reset();
      Translator.instance.setLoader(_RecordingLoader({'en': {}}));
      await Translator.instance.load(const Locale('en'));

      expect(Translator.instance.has('starter.title'), isFalse);
    });

    test(':name replacement and choice work on a package string', () async {
      Translator.instance.setLoader(_RecordingLoader({'en': {}}));
      Translator.instance.addSource(
        'starter',
        _RecordingLoader({
          'en': {
            'starter.welcome': 'Welcome, :name!',
            'starter.items': 'One item|:count items',
          },
        }),
      );

      await Translator.instance.load(const Locale('en'));

      expect(
        Translator.instance.get('starter.welcome', {'name': 'Magic'}),
        'Welcome, Magic!',
      );
      expect(Translator.instance.choice('starter.items', 1), 'One item');
      expect(Translator.instance.choice('starter.items', 3), '3 items');
    });

    test(
      'the host fallback beats a package fallback for a third locale',
      () async {
        Translator.instance.setLoader(
          _RecordingLoader({
            'en': {'k': 'host en'},
            'tr': {},
          }),
        );
        Translator.instance.addSource(
          'starter',
          _RecordingLoader({
            'en': {'k': 'package en'},
            'tr': {},
          }),
        );

        await Translator.instance.load(const Locale('tr'));

        expect(Translator.instance.get('k'), 'host en');
      },
    );

    test(
      'a loader that throws before it returns a future contributes nothing',
      () async {
        Translator.instance.setLoader(
          _RecordingLoader({
            'en': {'host.key': 'Host'},
          }),
        );
        Translator.instance.addSource('broken', _SyncThrowingLoader());
        Translator.instance.addSource(
          'starter',
          _RecordingLoader({
            'en': {'starter.key': 'Starter'},
          }),
        );

        await Translator.instance.load(const Locale('en'));

        expect(Translator.instance.get('host.key'), 'Host');
        expect(Translator.instance.get('starter.key'), 'Starter');
      },
    );

    test('a locale with a country code reads each loader once', () async {
      final host = _RecordingLoader({
        'en': {'a': 'A'},
      });
      final package = _RecordingLoader({
        'en': {'b': 'B'},
      });
      Translator.instance.setLoader(host);
      Translator.instance.addSource('starter', package);

      await Translator.instance.load(const Locale('en', 'US'));

      expect(host.asked, ['en']);
      expect(package.asked, ['en']);
      expect(Translator.instance.get('b'), 'B');
    });

    test(
      'a source added while a load is in flight is merged by the next load',
      () async {
        final gate = _GatedLoader({'host.key': 'Host'});
        Translator.instance.setLoader(gate);

        final first = Translator.instance.load(const Locale('en'));
        Translator.instance.addSource(
          'late',
          _RecordingLoader({
            'en': {'late.key': 'Late'},
          }),
        );
        gate.release.complete();
        await first;

        expect(Translator.instance.has('late.key'), isFalse);

        await Translator.instance.load(const Locale('en'));

        expect(Translator.instance.get('late.key'), 'Late');
      },
    );

    test(
      'an older load that lands last does not overwrite a newer one',
      () async {
        final host = _FirstReadGatedLoader({'host.key': 'Host'});
        Translator.instance.setLoader(host);

        final older = Translator.instance.load(const Locale('en'));
        Translator.instance.addSource(
          'late',
          _RecordingLoader({
            'en': {'late.key': 'Late'},
          }),
        );
        await Translator.instance.load(const Locale('en'));
        expect(Translator.instance.get('late.key'), 'Late');

        host.release.complete();
        await older;

        // The older merge lacks the source and must not replace the newer one.
        expect(Translator.instance.get('late.key'), 'Late');
      },
    );

    test('two overlapping loads of one locale announce it once', () async {
      final host = _FirstReadGatedLoader({'k': 'Host'});
      Translator.instance.setLoader(host);
      var notified = 0;
      Translator.instance.addListener(() => notified++);

      final older = Translator.instance.load(const Locale('tr'));
      await Translator.instance.load(const Locale('tr'));
      host.release.complete();
      await older;

      expect(notified, 1);
      expect(Translator.instance.get('k'), 'Host');
    });

    test('a cached locale supersedes a pending load of another one', () async {
      final host = _GatedLocaleLoader({
        'en': {'k': 'English'},
        'tr': {'k': 'Turkish'},
      }, gated: 'tr');
      Translator.instance.setLoader(host);
      await Translator.instance.load(const Locale('en'));

      final pending = Translator.instance.load(const Locale('tr'));
      await Translator.instance.load(const Locale('en'));
      host.release.complete();
      await pending;

      expect(Translator.instance.get('k'), 'English');
    });

    test('a host loader that throws is reported without waiting for a hung '
        'package read', () async {
      Translator.instance.setLoader(_SyncThrowingLoader());
      Translator.instance.addSource('hung', _HangingLoader());

      await expectLater(
        Translator.instance.load(const Locale('en')),
        throwsStateError,
      ).timeout(const Duration(seconds: 5));
    });

    test(
      'a load whose host loader throws leaves the source to the next load',
      () async {
        Translator.instance.setLoader(_SyncThrowingLoader());
        Translator.instance.addSource(
          'starter',
          _RecordingLoader({
            'en': {'starter.key': 'Starter'},
          }),
        );

        await expectLater(
          Translator.instance.load(const Locale('en')),
          throwsStateError,
        );

        Translator.instance.setLoader(_RecordingLoader({'en': {}}));
        await Translator.instance.load(const Locale('en'));

        expect(Translator.instance.get('starter.key'), 'Starter');
      },
    );

    test(
      'a package catalogue with nested keys conflicts with a dotted one',
      () async {
        final fakeLog = Log.fake();
        Translator.instance.setLoader(_RecordingLoader({'en': {}}));
        Translator.instance.addSource(
          'one',
          _RecordingLoader({
            'en': {'auth.failed': 'One'},
          }),
        );
        Translator.instance.addSource(
          'two',
          _RecordingLoader({
            'en': {
              'auth': {'failed': 'Two'},
            },
          }),
        );

        await Translator.instance.load(const Locale('en'));

        expect(Translator.instance.get('auth.failed'), 'Two');
        expect(
          fakeLog.entries.where((e) => e.level == 'warning'),
          hasLength(1),
        );
      },
    );

    test('a conflict is reported for the locale it exists in', () async {
      final fakeLog = Log.fake();
      Translator.instance.setLoader(_RecordingLoader({'en': {}, 'tr': {}}));
      Translator.instance.addSource(
        'one',
        _RecordingLoader({
          'en': {'k': 'One'},
          'tr': {},
        }),
      );
      Translator.instance.addSource(
        'two',
        _RecordingLoader({
          'en': {'k': 'Two'},
          'tr': {},
        }),
      );

      await Translator.instance.load(const Locale('tr'));

      final warnings = fakeLog.entries.where((e) => e.level == 'warning');
      expect(warnings, hasLength(1));
      expect(warnings.single.message, contains('[en]'));
      expect(warnings.single.message, isNot(contains('[tr]')));
    });

    group('a package JsonAssetLoader', () {
      test('a package loader answers a missing file empty and quiet', () async {
        final fakeLog = Log.fake();

        final loaded = await const JsonAssetLoader.package(
          basePath: 'test/fixtures/lang',
        ).load(const Locale('de'));

        expect(loaded, isEmpty);
        expect(fakeLog.entries, isEmpty);
      });

      test(
        'a file that will not parse is logged and contributes nothing',
        () async {
          final fakeLog = Log.fake();

          final loaded = await const JsonAssetLoader.package(
            basePath: 'test/fixtures/lang_broken',
          ).load(const Locale('en'));

          expect(loaded, isEmpty);
          expect(
            fakeLog.entries.where((e) => e.level == 'warning').single.message,
            contains('lang_broken/en.json'),
          );
        },
      );

      test(
        'by default answers a missing file with its whole fallback file',
        () async {
          final loaded = await const JsonAssetLoader(
            basePath: 'test/fixtures/lang',
          ).load(const Locale('de'));

          expect(loaded['greeting'], 'Hello');
        },
      );

      test('a package loader keeps the host English under a package '
          'catalogue that has no file for the locale', () async {
        Translator.instance.setLoader(
          _RecordingLoader({
            'en': {'greeting': 'Hi from the host'},
            'de': {},
          }),
        );
        Translator.instance.addSource(
          'starter',
          const JsonAssetLoader.package(basePath: 'test/fixtures/lang'),
        );

        await Translator.instance.load(const Locale('de'));

        expect(Translator.instance.get('greeting'), 'Hi from the host');
      });
    });

    test('a key no layer defines still answers the key', () async {
      Translator.instance.setLoader(_RecordingLoader({'en': {}}));
      Translator.instance.addSource(
        'starter',
        _RecordingLoader({
          'en': {'starter.title': 'Starter'},
        }),
      );

      await Translator.instance.load(const Locale('en'));

      expect(
        Translator.instance.get('nobody.defined.this'),
        'nobody.defined.this',
      );
    });
  });
}

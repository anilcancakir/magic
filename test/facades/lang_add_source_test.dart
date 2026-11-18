import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart' show Lang, Magic, MagicApp, trans;
import 'package:magic/src/localization/contracts/translation_loader.dart';
import 'package:magic/src/localization/translator.dart';

/// Serves one catalogue per language from a map.
class _MapLoader implements TranslationLoader {
  _MapLoader(this._locales);

  final Map<String, Map<String, dynamic>> _locales;

  @override
  Future<Map<String, dynamic>> load(Locale locale) async =>
      Map<String, dynamic>.from(
        _locales[locale.languageCode] ?? <String, dynamic>{},
      );
}

void main() {
  group('Lang.addSource', () {
    setUp(() {
      MagicApp.reset();
      Magic.flush();
      Translator.reset();
    });

    test('registers a package catalogue under the host', () async {
      Translator.instance.setLoader(
        _MapLoader({
          'en': {'common.back': 'Go back'},
        }),
      );

      Lang.addSource(
        'starter',
        _MapLoader({
          'en': {'common.back': 'Back', 'common.save': 'Save'},
        }),
      );
      await Translator.instance.load(const Locale('en'));

      expect(trans('common.back'), 'Go back');
      expect(trans('common.save'), 'Save');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

void main() {
  group('MagicPlatform.isTvOS', () {
    test('is false on a host that is not an Apple TV', () {
      expect(MagicPlatform.isTvOS, isFalse);
    });

    test('follows the debug override when it is true', () {
      addTearDown(() => MagicPlatform.debugTvOSOverride = null);

      MagicPlatform.debugTvOSOverride = true;

      expect(MagicPlatform.isTvOS, isTrue);
    });

    test('follows the debug override when it is false', () {
      addTearDown(() => MagicPlatform.debugTvOSOverride = null);

      MagicPlatform.debugTvOSOverride = false;

      expect(MagicPlatform.isTvOS, isFalse);
    });

    test('reads the platform again once the override is cleared', () {
      MagicPlatform.debugTvOSOverride = true;
      MagicPlatform.debugTvOSOverride = null;

      expect(MagicPlatform.isTvOS, isFalse);
    });
  });
}

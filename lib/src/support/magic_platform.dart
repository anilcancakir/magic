import 'package:flutter/foundation.dart' show visibleForTesting;

import 'magic_platform_io.dart'
    if (dart.library.js_interop) 'magic_platform_web.dart';

/// The one place magic and its plugins ask which platform they run on when
/// `TargetPlatform` cannot tell.
///
/// flutter-tvos reports an Apple TV as iOS (`Platform.isIOS`,
/// `defaultTargetPlatform`), so every iOS gate also fires on tvOS. Ask
/// [isTvOS] before the iOS check wherever tvOS differs: only `Library/Caches`
/// and `tmp` are writable there, and several native SDKs are absent.
///
/// ```dart
/// if (MagicPlatform.isTvOS) {
///   return;
/// }
/// ```
class MagicPlatform {
  MagicPlatform._();

  /// Replaces the platform answer in tests. `null` reads the platform.
  ///
  /// Restore it in the test's teardown:
  /// `addTearDown(() => MagicPlatform.debugTvOSOverride = null)`.
  @visibleForTesting
  static bool? debugTvOSOverride;

  /// Whether the app runs on tvOS. Always false on web.
  static bool get isTvOS => debugTvOSOverride ?? readIsTvOS();
}

/// Magic Paths, the conditional export router.
///
/// Routes to `magic_paths_io.dart` (path_provider) off the web and to
/// `magic_paths_web.dart` on the web, so `dart:io` never reaches a web build.
library;

export 'magic_paths_io.dart'
    if (dart.library.js_interop) 'magic_paths_web.dart';

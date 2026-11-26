/// Where an app keeps its files on disk (web implementation).
///
/// A browser has no file system to resolve, so nothing here is reachable: the
/// web drivers keep their data in `localStorage`.
class MagicPaths {
  MagicPaths._();

  /// Not available on web.
  static Future<Never> appData() {
    throw UnsupportedError('MagicPaths.appData() needs a file system.');
  }
}

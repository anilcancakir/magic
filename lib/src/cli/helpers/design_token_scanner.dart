import 'dart:io';

import 'package:path/path.dart' as p;

/// A raw colour literal found by [DesignTokenScanner.scan].
typedef DesignTokenHit = ({String path, int line});

/// The paths `design:lint --dart` skips, read from `.design-token-allowlist`.
///
/// One entry per line, `<path> | <reason>`. The path is everything before the
/// first `|` with surrounding whitespace trimmed; the reason is optional and
/// never read. A path ending in `/` is a directory prefix, anything else an
/// exact file, both relative to the project root with `/` separators. A
/// trailing `\r` is dropped, and empty lines and lines starting with `#` are
/// skipped.
class DesignTokenAllowlist {
  DesignTokenAllowlist._(this._directories, this._files);

  /// Parses allowlist [content] in the format above.
  factory DesignTokenAllowlist.parse(String content) {
    final directories = <String>[];
    final files = <String>{};

    for (final raw in content.split('\n')) {
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      if (line.isEmpty || line.startsWith('#')) continue;

      final path = line.split('|').first.trim();
      if (path.isEmpty) continue;

      if (path.endsWith('/')) {
        directories.add(path);
      } else {
        files.add(path);
      }
    }

    return DesignTokenAllowlist._(directories, files);
  }

  /// Reads the allowlist at [path]; a missing file is an empty allowlist.
  factory DesignTokenAllowlist.load(String path) {
    final file = File(path);

    return DesignTokenAllowlist.parse(
      file.existsSync() ? file.readAsStringSync() : '',
    );
  }

  final List<String> _directories;
  final Set<String> _files;

  /// Whether [relativePath] (project-root relative, `/` separators) is skipped.
  bool allows(String relativePath) =>
      _files.contains(relativePath) ||
      _directories.any(relativePath.startsWith);
}

/// One lexical context of [DesignTokenScanner.stripComments]: code (where
/// [quote] is null) or a string literal.
class _Frame {
  _Frame.code({this.interpolation = false})
    : quote = null,
      triple = false,
      raw = false;

  _Frame.string(String this.quote, {required this.triple, required this.raw})
    : interpolation = false;

  /// The quote character of a string frame, null for code.
  final String? quote;

  /// Whether a string frame is `'''` or `"""`.
  final bool triple;

  /// Whether a string frame is `r'...'`, where `\` and `$` are literal.
  final bool raw;

  /// Whether a code frame is a `${...}` interpolation, closed by its `}`.
  final bool interpolation;

  /// Open `{` count inside a code frame, so a map literal inside an
  /// interpolation does not close it.
  int braces = 0;

  String get closer => triple ? quote! * 3 : quote!;
}

/// Finds raw colour literals in a project's `lib/**/*.dart`, where DESIGN.md's
/// semantic tokens belong. A regex over comment-stripped source, not an AST.
class DesignTokenScanner {
  const DesignTokenScanner._();

  /// `Colors.` needs a left boundary or it matches `kBrandColors.first`.
  /// `Color(0x` has none on purpose: `MaterialColor(0xFF...)` is a raw hex
  /// too. `Color.from` covers `fromARGB`, `fromRGBO` and the bare `from(`.
  static final RegExp pattern = RegExp(
    r'Color\(0x|Color\.from(ARGB|RGBO)?\(|(^|[^A-Za-z0-9_])Colors\.',
  );

  static final RegExp _identifierChar = RegExp(r'[A-Za-z0-9_$]');

  /// Scans every `*.dart` under `<projectRoot>/lib`, sorted by path, and
  /// returns one hit per matching line. `test/` and files [allowlist] allows
  /// are never read.
  static List<DesignTokenHit> scan(
    String projectRoot,
    DesignTokenAllowlist allowlist,
  ) {
    final lib = Directory(p.join(projectRoot, 'lib'));
    if (!lib.existsSync()) return const <DesignTokenHit>[];

    final files = <String, File>{
      for (final file
          in lib
              .listSync(recursive: true, followLinks: false)
              .whereType<File>())
        if (file.path.endsWith('.dart'))
          p.posix.joinAll(p.split(p.relative(file.path, from: projectRoot))):
              file,
    };

    final hits = <DesignTokenHit>[];
    for (final path in files.keys.toList()..sort()) {
      if (allowlist.allows(path)) continue;

      final lines = stripComments(files[path]!.readAsStringSync()).split('\n');
      for (var index = 0; index < lines.length; index++) {
        if (pattern.hasMatch(lines[index])) {
          hits.add((path: path, line: index + 1));
        }
      }
    }

    return hits;
  }

  /// Removes `//`, `///` and (nested) `/* */` comments from Dart [source],
  /// keeping every newline so line numbers survive and keeping string content.
  ///
  /// Strings are tracked as Dart lexes them: `'`, `"`, `'''`, `"""`, the raw
  /// `r` prefix, escapes and `${...}` interpolations holding strings of their
  /// own. An unclosed single-line string ends at its line, as the compiler
  /// would report it. An unterminated block comment returns [source] whole:
  /// a gate that over-reports beats one that silently drops the file's tail.
  static String stripComments(String source) {
    final out = StringBuffer();
    final stack = <_Frame>[_Frame.code()];
    var blockDepth = 0;
    var i = 0;

    while (i < source.length) {
      final char = source[i];
      final pair = source.startsWith('/*', i) || source.startsWith('*/', i)
          ? source.substring(i, i + 2)
          : '';

      // 1. Inside a block comment only nesting and newlines matter.
      if (blockDepth > 0) {
        if (pair == '/*' || pair == '*/') {
          blockDepth += pair == '/*' ? 1 : -1;
          i += 2;
          continue;
        }
        if (char == '\n') out.write(char);
        i++;
        continue;
      }

      final frame = stack.last;

      // 2. Inside a string everything is content until its closing quote.
      if (frame.quote != null) {
        i = _stringStep(source, i, frame, stack, out);
        continue;
      }

      // 3. In code, a comment, a string opener or an interpolation's `}`.
      if (source.startsWith('//', i)) {
        final end = source.indexOf('\n', i);
        i = end == -1 ? source.length : end;
        continue;
      }
      if (pair == '/*') {
        blockDepth = 1;
        i += 2;
        continue;
      }

      final raw =
          char == 'r' &&
          i + 1 < source.length &&
          (source[i + 1] == "'" || source[i + 1] == '"') &&
          (i == 0 || !_identifierChar.hasMatch(source[i - 1]));
      final quoteAt = raw ? i + 1 : i;
      final quote = source[quoteAt];
      if (quote == "'" || quote == '"') {
        final triple = source.startsWith(quote * 3, quoteAt);
        final opener = source.substring(i, quoteAt + (triple ? 3 : 1));
        stack.add(_Frame.string(quote, triple: triple, raw: raw));
        out.write(opener);
        i += opener.length;
        continue;
      }

      if (char == '{') frame.braces++;
      if (char == '}') {
        if (frame.interpolation && frame.braces == 0) {
          stack.removeLast();
        } else {
          frame.braces--;
        }
      }
      out.write(char);
      i++;
    }

    return blockDepth > 0 ? source : out.toString();
  }

  /// Consumes one token of a string frame at [i] and returns the next index.
  static int _stringStep(
    String source,
    int i,
    _Frame frame,
    List<_Frame> stack,
    StringBuffer out,
  ) {
    final char = source[i];

    if (!frame.raw && char == r'\') {
      final end = i + 2 > source.length ? source.length : i + 2;
      out.write(source.substring(i, end));
      return end;
    }
    if (source.startsWith(frame.closer, i)) {
      stack.removeLast();
      out.write(frame.closer);
      return i + frame.closer.length;
    }
    if (!frame.raw && source.startsWith(r'${', i)) {
      stack.add(_Frame.code(interpolation: true));
      out.write(r'${');
      return i + 2;
    }
    if (char == '\n' && !frame.triple) stack.removeLast();
    out.write(char);
    return i + 1;
  }
}

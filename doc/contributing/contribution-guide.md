# Contribution Guide

This guide covers everything you need to contribute to the Magic framework: local setup, coding style, testing requirements, and the pull-request process.

- [Introduction](#introduction)
- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Coding Style](#coding-style)
- [Testing](#testing)
- [Pull Requests](#pull-requests)
- [Documentation](#documentation)
- [Questions](#questions)
- [Related Documentation](#related-documentation)

<a name="introduction"></a>
## Introduction

Thank you for considering contributing to Magic. This guide will help you get started with contributing to the framework.

<a name="development-setup"></a>
## Development Setup

### Prerequisites

- Dart SDK 3.13.0 or higher
- Flutter 3.47.0 or higher
- Git

### Clone the Repository

```bash
git clone https://github.com/anilcancakir/magic.git
cd magic
```

### Install Dependencies

```bash
flutter pub get
```

### Run Tests

```bash
flutter test
```

<a name="project-structure"></a>
## Project Structure

```
lib/
├── src/
│   ├── actions/        # MagicAction and RunsActions
│   ├── auth/           # Authentication system
│   ├── cache/          # Caching
│   ├── cli/            # magic:install and the make:* generators
│   ├── concerns/       # ValidatesRequests
│   ├── data/           # Repository and RepositoryQuery
│   ├── database/       # Base Eloquent model, casts, LocalModelStore
│   ├── events/         # Event system
│   ├── facades/        # Facade classes
│   ├── forms/          # MagicFormObject
│   ├── foundation/     # Core Magic class
│   ├── helpers/        # Date helpers
│   ├── http/           # Controllers, middleware pipeline, Kernel
│   ├── launch/         # URL, email, phone and SMS launching
│   ├── localization/   # i18n
│   ├── logging/        # Log manager and drivers
│   ├── network/        # HTTP client
│   ├── perf/           # Performance hooks
│   ├── policies/       # Policy base class
│   ├── providers/      # Service providers
│   ├── routing/        # Router
│   ├── security/       # Vault
│   ├── session/        # Form flash and SessionScope
│   ├── storage/        # File storage
│   ├── support/        # Helpers & utilities
│   ├── testing/        # Test fakes
│   ├── ui/             # View system
│   └── validation/     # Validation rules
├── cli.dart            # Flutter-free dowel provider barrel
├── magic.dart          # Barrel export
└── testing.dart        # Test fakes barrel
```

### Key Files

| File | Purpose |
|:---|:---|
| `lib/src/foundation/magic.dart` | Core Magic facade |
| `lib/src/facades/*.dart` | Public API facades |
| `lib/src/providers/*.dart` | Service providers |
| `lib/magic.dart` | Public exports |

<a name="coding-style"></a>
## Coding Style

### Dart Style

Follow the [Dart Style Guide](https://dart.dev/effective-dart/style):

```dart
// Use camelCase for variables and functions
final userName = 'John';
void loadUsers() {}

// Use PascalCase for classes
class UserController {}

// Use snake_case for file names
// user_controller.dart
```

### Documentation

Document all public APIs using DartDoc:

```dart
/// Retrieves a configuration value using dot notation.
///
/// ```dart
/// final name = Config.get<String>('app.name', 'Default');
/// ```
///
/// Returns [defaultValue] if the key doesn't exist.
static T? get<T>(String key, [T? defaultValue]) {
  // ...
}
```

### Laravel-Style APIs

When designing APIs, follow Laravel's patterns:

```dart
// ✅ Good: Laravel-like fluent API
MagicRoute.page('/users', () => UserController.instance.index())
    .name('users.index')
    .middleware(['auth']);

// ❌ Bad: Non-fluent API
registerRoute('/users', 'users.index', UserController, 'index', ['auth']);
```

<a name="testing"></a>
## Testing

### Test Structure

The `test/` tree mirrors `lib/src/`: a class in `lib/src/auth/` is tested in `test/auth/`.

### Writing Tests

Write the failing test first, then the code that makes it pass. Every `setUp` resets the container and the facade caches, so state never leaks between tests. Mock by implementing the contract (or use the fakes in `package:magic/testing.dart`), not with a mocking package:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

void main() {
  setUp(() {
    MagicApp.reset();
    Magic.flush();
  });

  group('ClassName', () {
    test('method does something', () {
      // Arrange
      final instance = ClassName();

      // Act
      final result = instance.method();

      // Assert
      expect(result, equals(expected));
    });
  });
}
```

### Test Coverage

Aim for high test coverage on new code:

```bash
flutter test --coverage
```

<a name="pull-requests"></a>
## Pull Requests

### Before Submitting

1. **Fork** the repository
2. **Create a branch** from `master` for your feature or fix (`feat/*`, `fix/*`, `chore/*` or `docs/*`)
3. **Write tests** for new functionality, failing test first
4. **Run all tests** to ensure nothing is broken
5. **Run the analyzer and formatter**: `flutter analyze --no-fatal-infos` and `dart format .` are clean
6. **Update documentation** and `CHANGELOG.md` (an entry under `[Unreleased]`)

### PR Template

```markdown
## What

-

## Why

-

## Testing

- [ ] A failing test came first, and `flutter test` is green
- [ ] `flutter analyze --no-fatal-infos` and `dart format .` are clean
- [ ] `CHANGELOG.md` has an entry under `[Unreleased]`
- [ ] README, `llms.txt`, `doc/`, the agent skill and `CLAUDE.md` match the change
- [ ] `python3 tool/check-docs.py` reports 0 issues
```

### Commit Messages

Use clear, descriptive commit messages:

```
feat(auth): add token refresh functionality

- Add refreshToken() method to Guard contract
- Implement auto-refresh in AuthInterceptor
- Update documentation
```

Prefixes:
- `feat:` for a new feature
- `fix:` for a bug fix
- `docs:` for documentation only
- `refactor:` for code refactoring
- `test:` for adding tests
- `chore:` for maintenance

<a name="documentation"></a>
## Documentation

### Updating Docs

Documentation lives in the `doc/` directory:

```
doc/
├── getting-started/
├── architecture/
├── basics/
├── security/
├── digging-deeper/
├── eloquent/
├── testing/
├── packages/
└── contributing/
```

### Documentation Style

Follow Laravel's documentation style:

1. Start with a one-sentence description, then a table of contents
2. Use anchor links for sections
3. Include code examples
4. Use GitHub-style alerts for important notes
5. Keep explanations concise

The page template and the per-feature checklist are in the [Documentation Authoring Guide](./documentation.md).

### Checking Docs

Check page shape, links and anchors from the repository root:

```bash
python3 tool/check-docs.py
```

<a name="questions"></a>
## Questions

If you have questions about contributing, open a GitHub issue.

<a name="related-documentation"></a>
## Related Documentation

- [Documentation Authoring Guide](./documentation.md): the page template and the doc-sync checklist.
- [Testing](../testing/getting-started.md): the test bootstrap and the facade fakes.
- [Facades](../architecture/facades.md): the public API surface a change usually touches.

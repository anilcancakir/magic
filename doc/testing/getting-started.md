# Testing: Getting Started

`MagicTest` and the fakes in `package:magic/testing.dart` reset the IoC container between tests, fake facades and HTTP, and keep controller and model behaviour assertable with `flutter_test`.

- [Introduction](#introduction)
- [Setting Up Tests](#setting-up-tests)
- [Writing Tests](#writing-tests)
- [Controller Testing](#controller-testing)
- [Model Testing](#model-testing)
- [Mock HTTP Responses](#mock-http-responses)
- [Running Tests](#running-tests)
- [Related Documentation](#related-documentation)

<a name="introduction"></a>
## Introduction

Magic tests run on `flutter_test`. `MagicTest.init()` clears the container and facade caches around every test, `Http.fake()` and the facade fakes replace the real network and storage, and mocks are written by implementing the contract (an abstract class) directly, never with code generation.

<a name="setting-up-tests"></a>
## Setting Up Tests

### Directory Structure

The `test/` tree mirrors where the `make:*` generators write their classes, and `make:test` scaffolds a matching test there:

```
test/
├── app/
│   ├── actions/
│   ├── controllers/
│   ├── forms/
│   ├── repositories/
│   └── validation/requests/
├── resources/views/
└── unit/
```

```bash
dart run magic:dowel make:test Monitor --kind=controller   # -> test/app/controllers/monitor_controller_test.dart
```

`--kind` is one of `controller`, `action`, `form`, `repository`, `request`, `view` or `unit`.

### Test Helper

Magic provides a `MagicTest` bootstrap helper via `package:magic/testing.dart`. Call `MagicTest.init()` once at the top of `main()`; it registers `setUpAll`, `setUp` and `tearDown` for you:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/testing.dart';

void main() {
  MagicTest.init(); // Registers setUpAll + setUp + tearDown automatically

  test('my test', () {
    // Magic container is clean, facades are reset
  });
}
```

`MagicTest.init()` handles:
- `setUpAll`: `TestWidgetsFlutterBinding.ensureInitialized()`
- `setUp`: `MagicApp.reset()` + `Magic.flush()` + `Gate.flush()`
- `tearDown`: `Magic.flush()` + `Gate.flush()` + `DateManager.reset()` + `Translator.reset()`, so a loaded catalogue or locale does not carry into the next test

`Gate` is a process static that `Magic.flush()` does not clear on its own, so without the extra call an ability defined in one test leaks into every later test in the same file.

For integration tests that need a full `Magic.init()` lifecycle, use `MagicTest.boot()` instead:

```dart
import 'package:magic/testing.dart';

void main() {
  setUpAll(() async {
    await MagicTest.boot(
      configs: [testAppConfig],
      envFileName: '.env.testing',
    );
  });

  test('full lifecycle test', () async {
    // Magic is fully initialised with providers booted
  });
}

Map<String, dynamic> get testAppConfig => {
  'app': {
    'name': 'Test App',
    'debug': true,
  },
};
```

### Booting a Handful of Providers

A widget test that needs real providers but no env file or config boots them with `MagicTest.bootProviders(providers)`. It reproduces `Magic.init`'s order: every `register()` first, then every `boot()`, both in list order. Pair it with `MagicTest.disposeBooted()` in `tearDown`:

```dart
setUp(() async {
  await MagicTest.bootProviders([
    AppServiceProvider(Magic.app),
    AuthServiceProvider(Magic.app),
  ]);
});

tearDown(MagicTest.disposeBooted);
```

`disposeBooted()` undoes what `Magic.flush()` does not reach: it disposes the registered controllers (newest first), detaches `SessionScope` from auth state, resets `MagicRouter`, then flushes the container. Anything an app keeps in its own statics, such as a timer a provider arms in `boot()`, stays the app's to reset.

### Loading a Translation Catalogue

A widget test that renders `trans()` output needs a real catalogue loaded first; without one, `trans()` renders the raw dotted key. `MagicTest.loadTranslations(locale, {directory})` reads `<directory>/<locale>.json` off disk (default `assets/lang`, the app's own catalogue location), flattens it the same way the app's own loader does, and installs it before awaiting the translator's load:

```dart
await MagicTest.loadTranslations('tr');
expect(trans('auth.login'), 'Giriş yap');
```

Point `directory` at a temp directory with a small fixture json to test one key in isolation without touching the app's real catalogue. Loading never requires a fallback-locale file on disk: the translator only warns and falls back to an empty map when the fallback catalogue fails to load.

<a name="writing-tests"></a>
## Writing Tests

### Basic Test Structure

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic/testing.dart';

void main() {
  MagicTest.init();

  group('Validator', () {
    test('rejects an invalid email', () {
      final validator = Validator.make(
        {'email': 'invalid-email'},
        {'email': [Required(), Email()]},
      );

      expect(validator.fails(), isTrue);
      expect(validator.errors().containsKey('email'), isTrue);
    });

    test('accepts a valid email', () {
      final validator = Validator.make(
        {'email': 'john@example.com'},
        {'email': [Required(), Email()]},
      );

      expect(validator.passes(), isTrue);
    });
  });
}
```

<a name="controller-testing"></a>
## Controller Testing

Register the controller with `Magic.put`, fake the network, call a method, and assert the state transitions:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic/testing.dart';

void main() {
  MagicTest.init();

  late TaskController controller;

  setUp(() {
    Http.fake({
      'tasks': Http.response({
        'data': [
          {'id': 1, 'name': 'Write docs'},
        ],
      }),
    });

    controller = TaskController();
    Magic.put<TaskController>(controller);
  });

  tearDown(() {
    controller.dispose();
    Http.unfake();
  });

  test('loadTasks moves from loading to success', () async {
    expect(controller.isLoading, isFalse);

    final loading = controller.loadTasks();
    expect(controller.isLoading, isTrue);

    await loading;
    expect(controller.isSuccess, isTrue);
    expect(controller.rxState, hasLength(1));
  });
}
```

### Testing State Changes

```dart
test('setSuccess updates state correctly', () {
  final controller = TaskController();

  expect(controller.isLoading, isFalse);
  expect(controller.isSuccess, isFalse);

  controller.setLoading();
  expect(controller.isLoading, isTrue);

  controller.setSuccess([Task(name: 'Test')]);
  expect(controller.isSuccess, isTrue);
  expect(controller.rxState, isNotEmpty);
});
```

### Testing Validation Errors

A controller that mixes in `ValidatesRequests` keeps field errors you can assert on directly:

```dart
test('clearErrors removes all validation errors', () {
  final controller = AuthController();

  controller.setErrorsFromMap({'email': ['Invalid email']});
  expect(controller.hasError('email'), isTrue);

  controller.clearErrors();
  expect(controller.hasError('email'), isFalse);
});
```

<a name="model-testing"></a>
## Model Testing

Attribute behaviour (mass assignment, casts, dirty tracking) needs no fake; a model that talks to the backend is tested against `Http.fake()` (see [HTTP Tests](./http-tests.md)):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic/testing.dart';

void main() {
  MagicTest.init();

  group('User Model', () {
    test('fills attributes and exports them', () {
      final user = User()..fill({'name': 'John', 'email': 'john@example.com'});

      expect(user.toMap()['email'], equals('john@example.com'));
    });

    test('tracks dirty attributes', () {
      final user = User()..fill({'name': 'John'});
      user.syncOriginal();

      user.name = 'Updated Name';

      expect(user.isDirty('name'), isTrue);
    });
  });
}
```

A model with `useLocal => true` also needs the `magic_local_storage` plugin; its docs cover testing against the local store.

<a name="mock-http-responses"></a>
## Mock HTTP Responses

`Http.fake()` swaps the network driver for an in-memory one that answers from the stubs you give it and records every request:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic/testing.dart';

void main() {
  MagicTest.init();

  late AuthController controller;

  setUp(() {
    controller = AuthController();
  });

  tearDown(() {
    controller.dispose();
    Http.unfake();
  });

  test('login failure sets the error state', () async {
    final fake = Http.fake({
      'auth/login': Http.response({'message': 'Invalid credentials'}, 401),
    });

    await controller.login({
      'email': 'john@example.com',
      'password': 'wrong',
    });

    expect(controller.isError, isTrue);
    fake.assertSent((r) => r.method == 'POST' && r.url.contains('auth/login'));
  });
}
```

[HTTP Tests](./http-tests.md) covers URL patterns, callback stubs, request assertions and stray-request protection; [Facade Testing](./facades.md) covers the `Auth`, `Cache`, `Vault` and `Log` fakes.

<a name="running-tests"></a>
## Running Tests

### Run All Tests

```bash
flutter test
```

### Run Specific Test File

```bash
flutter test test/app/controllers/task_controller_test.dart
```

### Run With Coverage

```bash
flutter test --coverage
```

### Test Output

```bash
flutter test --reporter=expanded
```

<a name="related-documentation"></a>
## Related Documentation

- [HTTP Tests](./http-tests.md)
- [Facade Testing](./facades.md)
- [Controllers](../basics/controllers.md)
- [Actions](../basics/actions.md)
- [Magic CLI](../packages/magic-cli.md): `make:test`.

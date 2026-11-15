<p align="center">
  <img src="https://raw.githubusercontent.com/anilcancakir/magic/master/.github/magic-logo.svg" width="120" alt="Magic Logo" />
</p>

<h1 align="center">Magic</h1>

<p align="center">
  <strong>The full-stack framework for Flutter: Eloquent-style models, auth, routing, realtime and payments, wired and ready on every device.</strong><br/>
  The core package carries the container, facades, models over your REST API, routing without <code>BuildContext</code>, auth, validation, forms, events, cache, localisation and test fakes. Realtime, payments, SQLite, notifications, deep links, social sign-in, encryption, file picking and the starter kit are <a href="#the-plugin-family">official plugins</a>, and payments run through Stripe on the web and store purchase on iOS and Android, with no rail on desktop. Familiar to Laravel developers: the vocabulary carries over.
</p>

<p align="center">
  <a href="https://pub.dev/packages/magic"><img src="https://img.shields.io/pub/v/magic.svg" alt="pub package"></a>
  <a href="https://github.com/anilcancakir/magic/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/anilcancakir/magic/ci.yml?branch=master&label=CI" alt="CI"></a>
  <a href="https://codecov.io/gh/anilcancakir/magic"><img src="https://codecov.io/gh/anilcancakir/magic/graph/badge.svg" alt="codecov"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://pub.dev/packages/magic/score"><img src="https://img.shields.io/pub/points/magic" alt="pub points"></a>
</p>

<p align="center">
  <a href="https://anilcancakir.com/magic">Documentation</a> ·
  <a href="https://pub.dev/packages/magic">pub.dev</a> ·
  <a href="https://github.com/anilcancakir/magic/issues">Issues</a>
</p>

## At a glance

| Fact | Value |
|:---|:---|
| Package | [`magic`](https://pub.dev/packages/magic) |
| Install | `flutter pub add magic`, then `dart run magic:dowel magic:install` |
| Import | `package:magic/magic.dart` (`package:magic/testing.dart` in tests) |
| Entry points | `Magic.init()`, the facades (`Auth`, `Cache`, `Config`, `Event`, `Gate`, `Http`, `Lang`, `Launch`, `Log`, `MagicRoute`, `Session`, `Storage`, `Vault`), `Model`, `MagicController`, `ServiceProvider`, `dart run magic:dowel make:*` |
| Platforms | Android, iOS, macOS, Windows, Linux and the web. `Vault` keeps secrets in the platform's secure storage. |
| Requires | Dart >=3.13, Flutter >=3.47 |
| Dependencies | `wind_kit`, `material_ui`, `dowel`, `dio`, `go_router`, `flutter_secure_storage` and a few more, see [Dependencies](#dependencies) |
| License | MIT |

## Install

```bash
flutter pub add magic
dart run magic:dowel magic:install
```

Magic ships its own `dowel` executable, so the command works as soon as `magic` is a dependency, with no global activation. `magic:install` adds `wind_kit`, `material_ui` and `dowel` to your `pubspec.yaml`, writes the config files, the service providers, the `.env` files and a `lib/main.dart` that calls `Magic.init()`. It also scaffolds `bin/dispatcher.dart`, so plugin commands resolve.

`flutter pub add magic` installs core only. Realtime, payments, SQLite, notifications, encryption, the file picker and the rest of [the plugin family](#the-plugin-family) are separate packages. Add one with `flutter pub add <package>`, then `dart run magic:dowel plugin:install <package>`.

## A taste of Magic

A model maps a REST resource, a controller loads it and renders each state, a route serves the screen:

```dart
class User extends Model with HasTimestamps, InteractsWithPersistence, Authenticatable {
  @override String get table => 'users';
  @override String get resource => 'users';
  @override List<String> get fillable => ['name', 'email'];

  String? get name => get<String>('name');

  static User fromMap(Map<String, dynamic> map) =>
      User()..setRawAttributes(map, sync: true)..exists = map.containsKey('id');
  static Future<User?> find(dynamic id) =>
      InteractsWithPersistence.findById<User>(id, User.new);
}

class UserController extends MagicController with MagicStateMixin<List<User>> {
  static UserController get instance => Magic.findOrPut(UserController.new);

  Widget index() {
    if (isEmpty) fetchList('users', User.fromMap);
    return renderState((users) => WDiv(
      className: 'flex flex-col gap-2 p-4',
      children: [for (final user in users) WText(user.name ?? '')],
    ));
  }
}

// lib/routes/app.dart
void registerAppRoutes() {
  MagicRoute.page('/users', () => UserController.instance.index());
}
```

`fetchList` drives loading, success, error and empty for you, and navigation, auth and validation work from anywhere without a `BuildContext`: `MagicRoute.toNamed('user.show', params: {'id': '1'})`, `Auth.check()`, `Validator.make(data, rules).passes()`.

The sections below use the `User` model above; any other class a sample names (`PaymentGateway`, `HomePage`, `Post`) is the app's own.

## Container and service providers

Services live in a string-keyed container. A provider binds them in `register()` and wires them up in `boot()`; `Magic.init()` registers every provider in `app.providers`, then boots them in that order.

```dart
class PaymentServiceProvider extends ServiceProvider {
  PaymentServiceProvider(super.app);

  @override
  void register() {
    app.singleton('payments', () => PaymentGateway());
  }

  @override
  Future<void> boot() async {
    await Magic.make<PaymentGateway>('payments').connect();
  }
}

// lib/config/app.dart: 'providers': [..., (app) => PaymentServiceProvider(app)]
```

| Member | Does |
|:---|:---|
| `Magic.bind(key, factory, {shared})` | A factory binding: a new instance per `make`, or one cached instance with `shared: true` |
| `Magic.singleton(key, factory)` | A lazy shared instance |
| `Magic.make<T>(key)`, `Magic.bound(key)` | Resolve a service; check a key |
| `Magic.findOrPut<T>(builder)`, `Magic.find<T>()` | The controller registry, keyed by type |
| `ServiceProvider.register()`, `boot()` | Bind synchronously; initialise asynchronously, after every provider registered |

Fails when: `make` reads a key nothing bound (it throws, naming the key); a provider is missing from `app.providers` (it never runs); `register()` resolves another provider's service, which may not be bound yet (do it in `boot()`).

## Facades

Static facades front the container services, so no call needs a `BuildContext`.

```dart
final MagicResponse response = await Http.get('/plans', query: {'page': 1});
if (response.successful) {
  await Cache.put('plans', response.data, ttl: const Duration(minutes: 5));
}
Log.info('Loaded plans for ${Config.get<String>('app.name')}');
```

| Facade | Surface |
|:---|:---|
| `Auth`, `Gate` | Sign-in state and guards; abilities and policies |
| `Http` | `get`, `post`, `put`, `delete`, `upload` and the RESTful `index`, `show`, `store`, `update`, `destroy`, answering `MagicResponse` |
| `Cache`, `Config`, `Event`, `Lang`, `Log` | Caching, configuration, in-app events, translations, logging |
| `MagicRoute`, `Session` | Navigation without context; flash data across one navigation |
| `Storage`, `Vault`, `Launch` | Files, secure storage, opening URLs, mail, phone and SMS |

Fails when: a facade runs before `await Magic.init()` returns (its service is not bound yet); code calls `Http.patch` (there is no `patch` verb; `put` and `update` send PUT, which suits only an endpoint that accepts it, and a Laravel endpoint that takes only PATCH accepts `Http.post` with `'_method': 'PATCH'` in the body); `Launch` runs without `LaunchServiceProvider` in `app.providers`.

## Models

A model is an active record over a REST resource; `useLocal` adds SQLite through `magic_local_storage`.

```dart
final User? user = await User.find(1);
if (user != null) {
  user.fill({'name': 'Ada'}, strict: true);
  if (!await user.save()) {
    Log.warning('Not saved: ${user.validationErrors}');
  }
}
```

| Member | Does |
|:---|:---|
| `table`, `resource`, `fillable`, `casts`, `relations` | Describe the model; casts include `datetime` (to `Carbon`), `json`, `bool`, `int`, `double`, `EnumCast` and `ListCast` |
| `get<T>(key)`, `set(key, value)` | Typed attribute access for the model's own getters and setters |
| `fill(map, {strict})`, `setRawAttributes(map, {sync})` | Mass assignment through `fillable`; hydration that bypasses it |
| `save()`, `delete()` | Persist through the API (and the local store with `useLocal`); `save()` answers `true` when any leg succeeded, and `validationErrors` holds the remote leg's field errors |
| `InteractsWithPersistence.findById`, `allModels` | The reads behind a model's static `find` and `all` |
| `toMap()`, `toJson()`, `hidden`, `appends` | Serialisation |

Fails when: a relation was not nested in the payload (there is no lazy load and no `with()`, so it reads `null`); `fill` without `strict` meets a key outside `fillable` (it is dropped silently, `strict: true` throws `MassAssignmentException`); `get<T>` meets a value of another type (it answers `null`); a `useLocal` model has no `magic_local_storage` (it throws `StateError`); a hybrid model (`useLocal` and `useRemote`) whose API refuses the save while the local write succeeds answers `true` with `validationErrors` filled, so check the errors even after a `true`; when the API fails without field errors (a 500, a transport error) it also answers `true`, with `validationErrors` empty, and `lastRemoteResponse` tells you: the failed response, `statusCode` 0 for no readable answer, or `null` when the driver threw.

## Routing and middleware

Routes resolve to widgets on go_router, and middleware runs on navigation, not on an HTTP request.

```dart
// lib/routes/app.dart, called from RouteServiceProvider.boot()
void registerAppRoutes() {
  MagicRoute.page('/', () => const HomePage()).name('home');
  MagicRoute.group(
    prefix: '/admin',
    middleware: ['auth'],
    routes: () {
      MagicRoute.page('/users/:id', (String id) => UserPage(id: id))
          .name('admin.users.show')
          .title('User');
    },
  );
}

class EnsureAuthenticated extends MagicMiddleware {
  @override
  String? redirectTarget(String location) =>
      Auth.check() || location == '/login' ? null : '/login';
}

// lib/app/kernel.dart, called from RouteServiceProvider.register()
void registerKernel() {
  Kernel.register('auth', EnsureAuthenticated.new);
}
```

| Member | Does |
|:---|:---|
| `MagicRoute.page(path, handler)` | A route; `.name()`, `.title()`, `.middleware()`, `.transition()`, `.stacked()` chain on it |
| `MagicRoute.group`, `layout`, `resource` | Prefixes and middleware, a persistent shell, the CRUD routes of a controller |
| `MagicRoute.to`, `toNamed`, `push`, `back`, `replace` | Navigation from anywhere |
| `MagicMiddleware.redirectTarget(location)`, `handle(next)` | A redirect decided before the route builds; async work that calls `next()` to allow |
| `Kernel.register(name, factory)`, `Kernel.global(factories)` | Middleware aliases and global middleware |

Fails when: a route, layout or observer is added after the router is built (the first read of `MagicRoute.config`, which `Magic.init()` does last) and it throws `StateError`; a route names a middleware alias nothing registered (`Magic.init` throws, naming the route); a drill-down route expects a swipe back after `to()` (it replaces the page list, mark the route `.stacked()`).

## Auth and authorisation

The app makes the login call; `Auth` stores the token in `Vault` and restores the session on the next cold start. `Gate` checks abilities on the client.

```dart
final MagicResponse response = await Http.post(
  '/auth/login',
  data: {'email': email, 'password': password},
);
if (response.successful) {
  await Auth.login(
    {'token': response['token']},
    User.fromMap(response['user'] as Map<String, dynamic>),
  );
}

Gate.define('update-post', (User user, Post post) => post.userId == user.id);
final bool canEdit = Gate.allows('update-post', post);
```

| Member | Does |
|:---|:---|
| `Auth.login(data, user)`, `logout()`, `restore()`, `refreshToken()` | Start, end, restore and refresh a session |
| `Auth.check()`, `Auth.guest`, `Auth.user<T>()`, `Auth.id()` | Read the session; `guest` is a getter |
| `Auth.manager.setUserFactory(factory)` | Rebuild the user from the stored session |
| `Gate.define`, `before`, `allows`, `denies`, `Policy` | Abilities, a super-admin bypass, checks, model policies |
| `MagicCan`, `MagicCannot` | Widgets shown or hidden by an ability |

Fails when: no user factory is set before `AuthServiceProvider` boots (the stored session is not restored; set it in `AppServiceProvider.boot()` and list that provider first); an ability is undefined, nobody is signed in or the callback throws (`Gate` denies without an error). `Gate` is advisory: the backend authorises again.

## Validation and forms

Rules are classes, messages are translation keys, and a 422 from a Laravel backend lands on the same fields.

```dart
final Validator validator = Validator.make(
  {'email': email, 'password': password},
  {
    'email': [Required(), Email()],
    'password': [Required(), Min(8)],
  },
);
if (validator.fails()) {
  Log.warning('Invalid: ${validator.errors()}');
}
```

| Member | Does |
|:---|:---|
| `Validator.make(data, rules)` | `passes()`, `fails()`, `errors()`, `validate()` (throws `ValidationException`), `validateAsync()` |
| `Required`, `Email`, `Min`, `Max`, `Confirmed`, `In`, `Unique` and more | Rules; a custom rule extends `Rule` |
| `FormRequest` | `authorize()`, `prepared()`, `rules()` and `validate(data)` in one class |
| `MagicFormData`, `MagicForm` | Form state with a text controller per field, and the widget that shows server errors |
| `ValidatesRequests` | A controller mixin: `validateRequest`, `handleApiError(response)`, `hasError`, `getError` |

Fails when: `FormRequest.validate` drops a key that `rules()` does not name, even one `prepared()` added; a custom rule's `message()` returns a sentence instead of a key (its `messages` override never matches); `Unique` meets a network error (it passes, the backend has the last word).

## Events

In-app publish and subscribe: not queued and not transaction-aware.

```dart
class UserRegistered extends MagicEvent {
  UserRegistered(this.user);

  final User user;
}

class SendWelcomeMail extends MagicListener<UserRegistered> {
  @override
  Future<void> handle(UserRegistered event) async {
    await Http.post('/mail/welcome', data: {'user_id': event.user.id});
  }
}
```

```dart
// In a provider's register():
Event.listen<UserRegistered>(() => SendWelcomeMail());

// Anywhere, once the user exists:
await Event.dispatch(UserRegistered(user));
```

| Member | Does |
|:---|:---|
| `Event.listen<T>(factory)` | Register a listener factory for event type `T` |
| `Event.dispatch(event)` | Run every listener of the event's type, in order |
| `Event.listenAny(callback)` | Observe every event; answers an unsubscribe function |
| `BaseEventServiceProvider` | Maps event types to listener factories in one place |

Fails when: `listen` is called without a type argument (Dart infers `MagicEvent` and no event matches); a listener is registered in `boot()` (an event dispatched while the auth guard boots is missed, register in `register()`).

## Cache

A cache with a time-to-live, file-backed by default.

```dart
final List<dynamic> plans = await Cache.remember<List<dynamic>>(
  'plans',
  const Duration(hours: 1),
  () async {
    final MagicResponse response = await Http.get('/plans');
    // Throwing keeps a failed answer out of the cache: remember stores only
    // what the callback returns.
    if (!response.successful) throw StateError('Plans failed: ${response.statusCode}');
    return response.data as List<dynamic>;
  },
);
```

| Member | Does |
|:---|:---|
| `Cache.put(key, value, {ttl})`, `get(key, {defaultValue})` | Write and read |
| `Cache.has`, `forget`, `flush` | Check, remove one key, clear |
| `Cache.remember<T>(key, ttl, callback)` | Read, or compute and store |

Fails when: `CacheServiceProvider` is not in `app.providers` (the `cache` key is unbound); `cache.driver` is not a `CacheStore` (it throws); `remember<T>` finds a cached value of another type (the cast throws); a `remember` callback returns a failed response's body (it is cached for the whole TTL, so throw instead).

## Localisation

JSON catalogues under `assets/lang/`, Laravel-style keys and pluralisation, and a locale switch at runtime.

```dart
// assets/lang/en.json: {"welcome": "Welcome, :name!", "apples": "One apple|:count apples"}
final String greeting = trans('welcome', {'name': 'Ada'});
final String count = Lang.choice('apples', 3); // "3 apples": :count is filled in
await Lang.setLocale(const Locale('tr'));
```

| Member | Does |
|:---|:---|
| `trans(key, [replace])`, `Lang.get` | A translated string with `:name` placeholders |
| `Lang.choice(key, number, [replace])`, `transChoice` | The plural form for the current locale's rules |
| `Lang.setLocale`, `detectLocale`, `detectAndSetLocale`, `current` | Switch and read the locale |

Fails when: a key is missing (it answers the key itself, no error); `LocalizationServiceProvider` is not registered (no catalogue loads); `trans` runs before the translations load (check `Lang.isLoaded`).

## Testing

`package:magic/testing.dart` resets the framework between tests and fakes the facades in memory, with no mock library.

```dart
void main() {
  MagicTest.init();

  test('a 422 becomes field errors', () async {
    final FakeNetworkDriver http = Http.fake({
      'users': Http.response({
        'errors': {
          'email': ['Taken.'],
        },
      }, 422),
    });

    final MagicResponse response = await Http.post('/users', data: {'email': 'a@b.co'});

    expect(response.errors['email'], ['Taken.']);
    http.assertSent((request) => request.method == 'POST');
  });
}
```

| Member | Does |
|:---|:---|
| `MagicTest.init()` | Resets the container, controllers and `Gate` around every test |
| `Http.fake`, `Auth.fake`, `Cache.fake`, `Vault.fake`, `Log.fake` | In-memory fakes with `assert*` helpers |
| `MagicTest.bootProviders(providers)`, `disposeBooted()` | Boot a few real providers for a widget test |

Fails when: a test skips the reset (state leaks and a test passes for the wrong reason); a plain `test` reaches `MagicRoute.to` (`MagicTest.init()` builds no router, so cover navigation in a widget test).

## The plugin family

Magic core stays small, and realtime, payments and the other layers below are official plugins, not part of `flutter pub add magic`. Each plugin adds one layer and has its own page.

| Plugin | Adds |
|:---|:---|
| [`magic_local_storage`](https://anilcancakir.com/magic/local_storage) | SQLite for models with `useLocal`: `DB` and `Schema` facades, migrations, seeders, factories, a query builder and sync. |
| [`magic_socket`](https://anilcancakir.com/magic/socket) | Real-time broadcasting: the `Echo` facade, Reverb and null drivers, private and presence channels. |
| [`magic_encryption`](https://anilcancakir.com/magic/encryption) | AES-256-CBC encryption: the `Crypt` facade and `key:generate`. |
| [`magic_picker`](https://anilcancakir.com/magic/picker) | File and image picking through the `Pick` facade, plus the share-sheet download handler. |
| [`magic_deeplink`](https://anilcancakir.com/magic/deeplink) | Universal Links and App Links, resolved to Magic routes. |
| [`magic_notifications`](https://anilcancakir.com/magic/notifications) | Database (in-app), push (OneSignal) and mail channels behind one `Notify` facade. |
| [`magic_social_auth`](https://anilcancakir.com/magic/social_auth) | Social sign-in with extensible drivers, in the style of Laravel Socialite. |
| [`magic_payments`](https://anilcancakir.com/magic/payments) | One entitlement contract over Stripe on the web and store in-app purchase on mobile. |
| [`magic_sentry`](https://anilcancakir.com/magic/sentry) | Sentry for Magic apps: a web-safe boot, HTTP failure reports and an auth-synced user scope. |
| [`magic_starter`](https://anilcancakir.com/magic/starter) | A starter kit: auth, profile, teams and notifications as opt-in features with overridable views. |
| [`magic_device`](https://anilcancakir.com/magic/device) | Gate background work on mains power, viewer idle and macOS window fullscreen. |
| [`magic_devtools`](https://anilcancakir.com/magic/devtools) | Magic adapters for the `tapir` and `crumbs` dev tools. |

## For AI coding agents

Rules for an agent writing code against Magic. Each one is a mistake that costs a debugging session.

| Do | Because |
|:---|:---|
| Import `package:magic/magic.dart`, and `package:magic/testing.dart` in tests | Everything under `src/` is private. The barrel also re-exports `wind_kit`, `dio` and `go_router`. |
| `await Magic.init(...)` in `main()` before any facade call | Facades resolve from the container that `init` builds. |
| Scaffold with `dart run magic:dowel make:*` | The generators place files where the rest of the framework looks for them. |
| Call `Auth.manager.setUserFactory(...)` in `AppServiceProvider.boot()`, and list `AppServiceProvider` before the auth provider | Without a user factory, session restore fails. |
| Register listeners from a provider's `register()`, as factories: `Event.listen<T>(() => Listener())` | The auth guard can dispatch during `AuthServiceProvider.boot`. `T` must be named, or Dart infers `MagicEvent` and no event matches. |
| Pass configs that read `Env.get()` as `configFactories` | `Magic.init` loads `.env` first and evaluates the factories after it. |
| Add the plugin when you use a layer that left core | A model with `useLocal` and no `magic_local_storage` throws `StateError`, and `Storage.download` on IO without `magic_picker` throws `UnsupportedError`. |
| Add `LaunchServiceProvider` to the `providers` config if `magic:install` did not | It is not registered automatically, and `Launch` needs it. |
| Open tests with `MagicTest.init()` and fake with `Http.fake()`, `Auth.fake()`, `Cache.fake()`, `Vault.fake()`, `Log.fake()` | Container and facade state leaks between tests otherwise. Mock by inheriting a contract, not with mockito. |

[`llms.txt`](llms.txt) carries the same facts in one file, and `npx skills add anilcancakir/magic` installs the [agent skill](skills/magic-framework/SKILL.md).

## Documentation

Every page is at `https://anilcancakir.com/magic/docs/<section>/<page>`.

| Section | Pages |
|:---|:---|
| Getting started | [Installation](https://anilcancakir.com/magic/docs/getting-started/installation) · [Configuration](https://anilcancakir.com/magic/docs/getting-started/configuration) · [Service Providers](https://anilcancakir.com/magic/docs/getting-started/service-providers) · [Directory Structure](https://anilcancakir.com/magic/docs/getting-started/directory-structure) |
| Architecture | [Service Container](https://anilcancakir.com/magic/docs/architecture/service-container) · [Facades](https://anilcancakir.com/magic/docs/architecture/facades) · [Request Lifecycle](https://anilcancakir.com/magic/docs/architecture/request-lifecycle) · [Application Structure](https://anilcancakir.com/magic/docs/architecture/application-structure) |
| Basics | [Routing](https://anilcancakir.com/magic/docs/basics/routing) · [Controllers](https://anilcancakir.com/magic/docs/basics/controllers) · [Views](https://anilcancakir.com/magic/docs/basics/views) · [Middleware](https://anilcancakir.com/magic/docs/basics/middleware) · [HTTP Client](https://anilcancakir.com/magic/docs/basics/http-client) · [Forms](https://anilcancakir.com/magic/docs/basics/forms) · [Actions](https://anilcancakir.com/magic/docs/basics/actions) · [UI Helpers](https://anilcancakir.com/magic/docs/basics/ui-helpers) |
| Digging deeper | [Cache](https://anilcancakir.com/magic/docs/digging-deeper/cache) · [Events](https://anilcancakir.com/magic/docs/digging-deeper/events) · [File Storage](https://anilcancakir.com/magic/docs/digging-deeper/file-storage) · [Helpers](https://anilcancakir.com/magic/docs/digging-deeper/helpers) · [Launch](https://anilcancakir.com/magic/docs/digging-deeper/launch) · [Localization](https://anilcancakir.com/magic/docs/digging-deeper/localization) · [Logging](https://anilcancakir.com/magic/docs/digging-deeper/logging) · [Session](https://anilcancakir.com/magic/docs/digging-deeper/session) · [Session Scope](https://anilcancakir.com/magic/docs/digging-deeper/session-scope) · [Validation](https://anilcancakir.com/magic/docs/digging-deeper/validation) · [Carbon](https://anilcancakir.com/magic/docs/digging-deeper/carbon) · [Perf Hooks](https://anilcancakir.com/magic/docs/digging-deeper/perf-hooks) |
| Eloquent | [Getting Started](https://anilcancakir.com/magic/docs/eloquent/getting-started) · [Mutators](https://anilcancakir.com/magic/docs/eloquent/mutators) · [Repositories](https://anilcancakir.com/magic/docs/eloquent/repositories) · [Serialization](https://anilcancakir.com/magic/docs/eloquent/serialization) |
| Security | [Authentication](https://anilcancakir.com/magic/docs/security/authentication) · [Authorization](https://anilcancakir.com/magic/docs/security/authorization) · [Vault](https://anilcancakir.com/magic/docs/security/vault) |
| Testing | [Getting Started](https://anilcancakir.com/magic/docs/testing/getting-started) · [Facades](https://anilcancakir.com/magic/docs/testing/facades) · [HTTP Tests](https://anilcancakir.com/magic/docs/testing/http-tests) |
| Packages | [Magic CLI](https://anilcancakir.com/magic/docs/packages/magic-cli) · [Magic DevTools](https://anilcancakir.com/magic/docs/packages/magic-devtools) |
| Contributing | [Contribution Guide](https://anilcancakir.com/magic/docs/contributing/contribution-guide) · [Documentation Authoring Guide](https://anilcancakir.com/magic/docs/contributing/documentation) |

## Dependencies

`wind_kit` for styling, re-exported so `WDiv` and `WText` come with the barrel; `material_ui` for the `MaterialApp` that `MagicApplication` builds; `dowel` for the CLI behind `dart run magic:dowel`; `dio` for the `Http` facade; `go_router` for routing; `flutter_secure_storage` for `Vault`; `flutter_dotenv` for `.env`; `intl` and `jiffy` for localisation and dates; `logger` for logging; `url_launcher` for `Launch`. Core has no code generation and no dependency on the dev tools: `magic_devtools` carries those adapters.

## Links

- [Documentation](https://anilcancakir.com/magic/docs/getting-started/installation): installation, the container, facades, routing, Eloquent, security and testing
- [API reference](https://pub.dev/documentation/magic/latest/)
- [llms.txt](llms.txt) and the [agent skill](skills/magic-framework/SKILL.md) for AI coding agents: `npx skills add anilcancakir/magic`
- [Changelog](CHANGELOG.md)
- [Report an issue](https://github.com/anilcancakir/magic/issues)
- [Security policy](SECURITY.md)

## License

MIT, see [LICENSE](LICENSE). Built by [Anılcan Çakır](https://anilcancakir.com).

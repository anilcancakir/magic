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
|---|---|
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
class User extends Model with HasTimestamps, InteractsWithPersistence {
  @override String get table => 'users';
  @override String get resource => 'users';

  String? get name => getAttribute('name') as String?;

  static User fromMap(Map<String, dynamic> map) =>
      User()..setRawAttributes(map, sync: true)..exists = map.containsKey('id');
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

## The plugin family

Magic core stays small, and realtime, payments and the other layers below are official plugins, not part of `flutter pub add magic`. Each plugin adds one layer and has its own page.

| Plugin | Adds |
|---|---|
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
|----|---------|
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
|---|---|
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

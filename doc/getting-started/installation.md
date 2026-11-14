# Installation

Add the `magic` package, scaffold the app with `dart run magic:dowel magic:install`, and call `Magic.init()` to get the IoC container, facades, Eloquent-style models, routing and auth.

- [Meet Magic](#meet-magic)
- [Why Magic?](#why-magic)
- [Requirements](#requirements)
- [Installing Magic](#installing-magic)
- [Bootstrapping Your Application](#bootstrapping-your-application)
- [Wind UI Plugin](#wind-ui-plugin)
- [Upgrading from 0.0.x](#upgrading-from-0-0-x)
- [Related Documentation](#related-documentation)

<a name="meet-magic"></a>
## Meet Magic

Magic is the full-stack framework for Flutter: Eloquent-style models, auth, routing, realtime and payments, wired and ready on every device. The core package provides the container, facades, models, auth, routing, validation, forms, events, cache, localisation and test fakes. Realtime, payments, SQLite, notifications, deep links, social sign-in, encryption, file picking and the starter kit are official plugin packages, so `flutter pub add magic` alone does not include them: see [Installing Magic](#installing-magic) for how to add one. Core provides:

- **Eloquent-style models**: active-record models over your REST API (and over local storage with a plugin).
- **Expressive routing**: the app's navigation defined with fluent route definitions.
- **Service container**: dependency injection and service management.
- **Facades**: static-style access to core services.
- **CLI**: scaffolding, a `dowel` plugin, for controllers, models, views, actions and more.
- **Wind UI**: Tailwind-style utility classes for Flutter widgets.

<a name="why-magic"></a>
## Why Magic?

Magic is progressive: start with the container, routing and a controller, and adopt the rest as the app grows.

### Familiar to Laravel Developers

Magic's structure and vocabulary follow Laravel, so the names carry over:

```dart
// Routing
MagicRoute.get('/users', () => UserController().index());
MagicRoute.get('/users/:id', (id) => UserController().show(id));

// Eloquent
final users = await User.all();
final user = await User.find(1);
await user.delete();

// HTTP
final response = await Http.get('/api/users');
if (response.successful) {
  // Handle data
}
```

### No BuildContext Needed

Dialogs and navigation work from controllers, services and plain Dart classes:

```dart
// Show dialogs from anywhere
Magic.success('Done!', 'Profile updated successfully');
Magic.dialog(ConfirmationDialog());
Magic.loading();

// Navigate without context
MagicRoute.to('/dashboard');
MagicRoute.back();
```

### Wind UI

Build UIs with utility-first classes instead of nested widgets:

```dart
WDiv(
  className: 'flex flex-col p-4 bg-white shadow-lg rounded-xl',
  children: [
    WText('Hello World', className: 'text-xl font-bold text-primary'),
    WButton(
      onTap: () => MagicRoute.to('/next'),
      className: 'bg-blue-500 hover:bg-blue-600 px-4 py-2 rounded-lg',
      child: WText('Get Started', className: 'text-white'),
    ),
  ],
)
```

<a name="requirements"></a>
## Requirements

Magic requires:

- **Dart SDK**: 3.13.0 or higher
- **Flutter**: 3.47.0 or higher

<a name="installing-magic"></a>
## Installing Magic

### 1. Add the Package

Add `magic` to your Flutter project:

```bash
flutter pub add magic
```

This pulls in Magic and its dependencies, including **Wind UI** (`wind_kit`) and the CLI. Layers beyond the core are separate plugin packages. Add one with `flutter pub add <package>` then `dart run magic:dowel plugin:install <package>`:

| Package | Provides |
|:--------|:---------|
| [`magic_local_storage`](https://anilcancakir.com/magic_local_storage/docs/getting-started/installation) | SQLite, query builder, migrations, seeders, factories, sync |
| [`magic_encryption`](https://anilcancakir.com/magic_encryption/docs/getting-started/installation) | AES encryption (`Crypt`) |
| [`magic_picker`](https://anilcancakir.com/magic_picker/docs/getting-started/installation) | File, image and video picking, share sheet |
| [`magic_socket`](https://anilcancakir.com/magic_socket/docs/getting-started/installation) | Real-time broadcasting (`Echo`) |

### 2. Scaffold Your Application

The Magic CLI ships as a `dowel` executable bundled with the `magic` package (declared in its `pubspec.yaml` `executables:`). Run it from any project that depends on magic:

```bash
dart run magic:dowel magic:install
```

No global activation or package-name substitution is needed: `dart run magic:dowel` resolves magic's bundled executable directly.

The installer adds `wind_kit`, `material_ui` and `dowel` to your `pubspec.yaml` and scaffolds `bin/dispatcher.dart` (plus the fast wrapper `bin/dowel`) through dowel's `install`. This command creates everything you need:

- `lib/config/`: Configuration files (app, auth, cache, network, logging, routing, view)
- `lib/app/`: Controllers, models, providers, middleware, policies
- `lib/routes/`: Route definitions
- `lib/resources/views/`: UI view classes
- `lib/main.dart`: Bootstrapped entry point with `Magic.init()`
- `.env` / `.env.example`: Environment configuration

You can exclude features you don't need:

```bash
dart run magic:dowel magic:install --without-auth --without-cache
```

Available flags: `--without-auth`, `--without-network`, `--without-cache`, `--without-localization`, `--without-logging`.
<a name="bootstrapping-your-application"></a>
## Bootstrapping Your Application

If you used `dart run magic:dowel magic:install`, your application is already bootstrapped. The install command generates a ready-to-run `main.dart` and all configuration files. Here's what was created:

### Generated Entry Point

The generated `lib/main.dart` initializes Magic and runs your app:

```dart
import 'package:material_ui/material_ui.dart';
import 'package:magic/magic.dart';
import 'config/app.dart';
import 'config/view.dart';
import 'config/auth.dart';
import 'config/network.dart';
import 'config/cache.dart';
import 'config/logging.dart';
import 'config/routing.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Magic.init(
    configFactories: [
      () => appConfig,
      () => viewConfig,
      () => authConfig,
      () => networkConfig,
      () => cacheConfig,
      () => loggingConfig,
      () => routingConfig,
    ],
  );

  runApp(
    MagicApplication(title: 'My App'),
  );
}
```

The `Magic.init()` method accepts:

| Parameter | Type | Description |
|-----------|------|-------------|
| `envFileName` | `String` | Environment file name (default: `.env`) |
| `configFactories` | `List<Function>` | Configuration factory functions |
| `configs` | `List<Map>` | Direct configuration maps |
| `providers` | `List<ServiceProvider>` | Additional service providers |

### Manual Setup (Without CLI)

If you prefer to set up manually without the CLI, create a `lib/config/app.dart`:

```dart
import 'package:magic/magic.dart';

final appConfig = {
  'app': {
    'name': Env.get('APP_NAME', 'Magic App'),
    'debug': Env.get('APP_DEBUG', true),
    'url': Env.get('APP_URL', 'http://localhost'),
    'providers': [
      (app) => RouteServiceProvider(app),
      (app) => AppServiceProvider(app),
    ],
  }
};
```

Then initialize in `lib/main.dart`:

```dart
import 'package:material_ui/material_ui.dart';
import 'package:magic/magic.dart';
import 'config/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Magic.init(
    configFactories: [() => appConfig],
  );

  runApp(MagicApplication(title: 'My App'));
}
```

### The Application Widget

`MagicApplication` is your root widget. It handles routing, themes, localization, and overlays automatically:

```dart
runApp(
  MagicApplication(
    title: 'My App',
    debugShowCheckedModeBanner: false,
  ),
);
```

To keep a widget on screen across every page, such as a floating player, pass a `builder`; see [A Layer Above Every Page](../basics/routing.md#a-layer-above-every-page).

<a name="wind-ui-plugin"></a>
## Wind UI Plugin

Magic includes **Wind UI** (`wind_kit`), a utility-first styling engine with Tailwind-style syntax. Instead of nesting widgets, you compose UIs with className strings like `flex flex-col p-4 bg-white rounded-xl shadow-md`.

> [!TIP]
> For the complete widget reference, utility classes, and advanced patterns, see the [Wind UI Documentation](https://anilcancakir.com/wind_kit/docs/getting-started/installation).

<a name="upgrading-from-0-0-x"></a>
## Upgrading from 0.0.x

The CLI, the styling package, the SDK floor and four layers changed in 1.0.0. See the changelog for the full list; the steps an app needs are:

1. Raise the SDK floor to Dart 3.13 and Flutter 3.47, then swap the packages: `dart pub remove fluttersdk_artisan fluttersdk_wind` and `dart pub add dowel wind_kit material_ui`. Run `flutter pub add magic` so the `magic` constraint moves to the 1.x line (a `^0.0.x` constraint does not admit it).
2. `fluttersdk_wind` is now `wind_kit`: change `package:fluttersdk_wind/fluttersdk_wind.dart` to `package:wind_kit/wind_kit.dart`. `MaterialApp`, `ThemeData` and `Colors` come from `package:material_ui/material_ui.dart`, because wind_kit builds on it and the two sets of types do not mix: run `dart fix --apply --code=deprecated_member_use` to swap the imports.
3. Move the project state from `.artisan/` to `.dowel/`, so the install records and their file hashes survive. Delete `.dowel/plugins.json` and the records under `.dowel/installed/` that belong to renamed packages (`fluttersdk_*`). Delete the generated `bin/dispatcher.dart`, `bin/fsa`, a leftover `bin/artisan.dart`, `lib/app/_plugins.g.dart` and `lib/app/commands/_index.g.dart`. In your own commands and providers replace `package:fluttersdk_artisan/artisan.dart` with `package:dowel/dowel.dart` and `Artisan*` classes with `Dowel*`.
4. Run `dart run dowel install`, which scaffolds `bin/dispatcher.dart` and `bin/dowel`, then `dart run dowel commands:refresh`. Register magic and each plugin again so they land in `.dowel/plugins.json`: `dart run dowel plugin:install magic`, then `dart run dowel plugin:install <package>`. A file a renamed plugin published earlier is reported as an `unmanaged-file` conflict: review it, then re-run with `--force`.
5. From then on run the CLI as `dart run magic:dowel <command>`. It hands over to your `bin/dispatcher.dart`, so plugin commands resolve. If `dart run dowel install` ran before `magic` was in the project, the dispatcher has no magic provider: run `dart run dowel plugin:install magic`.
6. Add the plugin for each layer your app used that left core, with `flutter pub add <package>` then `dart run magic:dowel plugin:install <package>`: `Crypt` is in `magic_encryption`; `Pick` and the `MagicFile.toXFile()` and `XFile.toMagicFile()` conversions are in `magic_picker`; `Echo`, the broadcasting manager and `ListensToBroadcasts` are in `magic_socket`; `DB`, `Schema`, `Model.query()`, migrations, seeders, factories, `SyncFeed` and `SyncLedger` are in `magic_local_storage`. An app installed on 0.0.41 has `lib/config/database.dart` and `lib/config/broadcasting.dart`: back up any customised settings in them and move those settings into the matching plugin configuration, then delete them before `plugin:install magic_local_storage` or `plugin:install magic_socket`, because the plugins export `databaseConfig` and `broadcastingConfig` and the import becomes ambiguous otherwise.
7. Replace what no longer exists in core: `Magic.seed` becomes `Seeding.run(List<Seeder>)` from `magic_local_storage`; `make:controller --broadcasts` is gone, so mix `ListensToBroadcasts` into the controller by hand; `--without-database` and `--without-broadcasting` are gone from `magic:install`. A model with `useLocal => true` throws a `StateError` naming `magic_local_storage` until that plugin is installed, and `Storage.download` on IO throws `UnsupportedError` until `magic_picker` is installed.

The dowel changelog for 0.0.21 carries the full recipe, including the `.mcp.json` cleanup.

<a name="related-documentation"></a>
## Related Documentation

- [Configuration](./configuration.md): how Magic's configuration system works.
- [Directory Structure](./directory-structure.md): the recommended project layout.
- [Service Providers](./service-providers.md): registering and booting services.
- [Routing](../basics/routing.md): defining your application's navigation.
- [Controllers](../basics/controllers.md): handling user interactions and business logic.
- [Eloquent ORM](../eloquent/getting-started.md): working with your models.
- [Magic CLI](../packages/magic-cli.md): `magic:install` and the `make:*` generators.

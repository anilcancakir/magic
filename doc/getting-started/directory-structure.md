# Directory Structure

The default Magic project layout organizes your app into folders for controllers, models, routes, config, and resources, so each is easy to locate at a glance, and it mirrors Laravel's conventions.

- [Introduction](#introduction)
- [The Root Directory](#the-root-directory)
- [The App Directory](#the-app-directory)
- [The Config Directory](#the-config-directory)
- [The Resources Directory](#the-resources-directory)
- [The Routes Directory](#the-routes-directory)
- [The Database Directory](#the-database-directory)
- [Related Documentation](#related-documentation)

<a name="introduction"></a>
## Introduction

The default Magic application structure is intended to provide a great starting point for both large and small applications. But you are free to organize your application however you like. Magic imposes almost no restrictions on where any given class is located, as long as the classes can be imported.

<a name="the-root-directory"></a>
## The Root Directory

A fresh Magic project contains the following directories:

```
my_app/
├── lib/
│   ├── app/                 # Application logic
│   ├── config/              # Configuration files
│   ├── resources/           # Views and assets
│   ├── routes/              # Route definitions
│   └── main.dart            # Application entry point
├── assets/
│   └── lang/                # Localization JSON files
├── .env                     # Environment variables
└── pubspec.yaml             # Dependencies
```

<a name="the-app-directory"></a>
## The App Directory

The `app` directory contains the core code of your application. Almost all of the classes in your application will be in this directory.

```
lib/app/
├── actions/                 # MagicAction writes
├── controllers/             # Request handlers
├── forms/                   # MagicFormObject form state
├── middleware/              # Route middleware
├── models/                  # Eloquent models
├── policies/                # Authorization policies
├── providers/               # Service providers
├── repositories/            # Repository row caches
└── kernel.dart              # Application kernel
```

### The Controllers Directory

The `controllers` directory contains all of your application's controller classes. Controllers are responsible for handling incoming requests and returning responses.

```dart
// lib/app/controllers/user_controller.dart
class UserController extends MagicController with MagicStateMixin<List<User>> {
  static UserController get instance => Magic.findOrPut(UserController.new);
  
  Widget index() => UserListView();
  Widget show(String id) => UserShowView(id: id);
}
```

### The Middleware Directory

The `middleware` directory contains your application's route middleware. Middleware provide a convenient mechanism for filtering requests entering your application.

```dart
// lib/app/middleware/auth_middleware.dart
class AuthMiddleware extends MagicMiddleware {
  @override
  String? redirectTarget(String location) {
    if (!Auth.check() && location != '/login') return '/login';
    return null;
  }
}
```

A redirect belongs in `redirectTarget`, which runs before the route builds, so the destination mounts once. Redirecting from `handle()` with `MagicRoute.to()` runs after the view has mounted and remounts the destination.

### The Models Directory

The `models` directory contains all of your Eloquent model classes. Each model maps to a REST resource and is used to interact with it.

```dart
// lib/app/models/user.dart
class User extends Model with HasTimestamps, InteractsWithPersistence {
  @override String get table => 'users';
  @override String get resource => 'users';
  
  String? get name => getAttribute('name') as String?;
  String? get email => getAttribute('email') as String?;
}
```

### The Policies Directory

The `policies` directory contains the authorization policy classes for your application. Policies are used to determine if a user can perform a given action against a resource.

### The Providers Directory

The `providers` directory contains all of the service providers for your application. Service providers bootstrap your application by binding services in the service container and registering events.

```dart
// lib/app/providers/route_service_provider.dart
class RouteServiceProvider extends ServiceProvider {
  RouteServiceProvider(super.app);

  @override
  void register() {
    registerKernel();
  }

  @override
  Future<void> boot() async {
    registerAppRoutes();
  }
}
```

<a name="the-config-directory"></a>
## The Config Directory

The `config` directory contains all of your application's configuration files. Each file returns a Map that is merged into Magic's configuration.

```
lib/config/
├── app.dart                 # App name, env, providers
├── auth.dart                # Guards, session config
├── network.dart             # API endpoints, timeouts
├── cache.dart               # Cache drivers
├── logging.dart             # Log channels
├── routing.dart             # Router options
└── view.dart                # Snackbar, dialog and loading styles
```

[`magic:install`](../packages/magic-cli.md) writes no localisation config; add a `localization` key (for example `supported_locales`) to a config file yourself when you need one.

<a name="the-resources-directory"></a>
## The Resources Directory

The `resources` directory contains your views and other UI resources.

```
lib/resources/
└── views/
    ├── auth/                # Authentication views
    │   ├── login_view.dart
    │   └── register_view.dart
    ├── layouts/             # Layout components
    │   ├── app_layout.dart
    │   └── guest_layout.dart
    ├── components/          # Reusable UI components
    │   ├── app_sidebar.dart
    │   └── app_header.dart
    └── dashboard_view.dart
```

Views in Magic are Dart classes that extend `MagicView` or `MagicStatefulView`:

```dart
// lib/resources/views/dashboard_view.dart
class DashboardView extends MagicView {
  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'p-4 flex flex-col gap-4',
      children: [
        WText('Dashboard', className: 'text-2xl font-bold'),
      ],
    );
  }
}
```

<a name="the-routes-directory"></a>
## The Routes Directory

The `routes` directory contains all of the route definitions for your application.

```
lib/routes/
└── app.dart                 # Application routes
```

Routes are defined using the `MagicRoute` facade:

```dart
// lib/routes/app.dart
void registerAppRoutes() {
  MagicRoute.group(
    prefix: '/',
    middleware: ['auth'],
    layoutId: 'app',
    layout: (child) => AppLayout(child: child),
    routes: () {
      MagicRoute.page('/', () => DashboardView());
      MagicRoute.page('/users', () => UserController.instance.index());
      MagicRoute.page('/users/:id', (id) => UserController.instance.show(id));
    },
  );
}
```

<a name="the-database-directory"></a>
## The Database Directory

A fresh project has no `database` directory. Migrations, seeders and model factories belong to the `magic_local_storage` plugin, which creates `lib/database/` when you install it: `flutter pub add magic_local_storage`, then `dart run magic:dowel plugin:install magic_local_storage`. See [Eloquent: Local Storage](../eloquent/getting-started.md#local-storage) and the [plugin's installation page](https://anilcancakir.com/magic/docs/local_storage/getting-started/installation).

<a name="related-documentation"></a>
## Related Documentation

- [Installation](./installation.md): the `magic:install` command that generates this layout.
- [Configuration](./configuration.md): the files under `lib/config`.
- [Service Providers](./service-providers.md): the files under `lib/app/providers`.
- [Actions](../basics/actions.md), [Forms](../basics/forms.md) and [Controllers](../basics/controllers.md): the `lib/app` classes.
- [Middleware](../basics/middleware.md): the files under `lib/app/middleware`.
- [Views](../basics/views.md): the files under `lib/resources/views`.
- [Routing](../basics/routing.md): the files under `lib/routes`.
- [Repositories](../eloquent/repositories.md): the files under `lib/app/repositories`.
- [Magic CLI](../packages/magic-cli.md): the `make:*` generators that create these files.

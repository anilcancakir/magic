# Service Providers

Service providers are the central bootstrapping point for Magic applications: each provider's `register` method binds services into the IoC container, and `boot` runs async setup after all providers have registered.

- [Introduction](#introduction)
- [Generating Providers](#generating-providers)
- [Writing Service Providers](#writing-service-providers)
    - [The Register Method](#the-register-method)
    - [The Boot Method](#the-boot-method)
- [Registering Providers](#registering-providers)
- [Providers Without Boot Logic](#providers-without-boot-logic)
- [Built-in Providers](#built-in-providers)
- [Related Documentation](#related-documentation)

<a name="introduction"></a>
## Introduction

Service providers are the central place of all Magic application bootstrapping. Your own application, as well as all of Magic's core services, are bootstrapped via service providers.

But, what do we mean by "bootstrapped"? In general, we mean **registering** things, including registering service container bindings, event listeners, middleware, and even routes. Service providers are the central place to configure your application.

If you open the `config/app.dart` file included with Magic, you will see a `providers` array. These are all of the service provider classes that will be loaded for your application.

<a name="generating-providers"></a>
## Generating Providers

Use the Magic CLI to generate a new service provider class:

```bash
dart run magic:dowel make:provider Payment
```

This creates `lib/app/providers/payment_service_provider.dart` with a `ServiceProvider` stub containing empty `register()` and `boot()` methods.

<a name="writing-service-providers"></a>
## Writing Service Providers

All service providers extend the `ServiceProvider` class. Most service providers contain a `register` and a `boot` method. Within the `register` method, you should **only bind things into the service container and register event listeners**. Within the `boot` method, you may do anything else: register routes, or any other functionality.

```dart
import 'package:magic/magic.dart';

class PaymentServiceProvider extends ServiceProvider {
  PaymentServiceProvider(super.app);

  @override
  void register() {
    // Bind services into the container
    app.singleton('payment.gateway', () => StripeGateway());
    app.bind('payment.processor', () => PaymentProcessor());
  }

  @override
  Future<void> boot() async {
    // Called after all providers are registered
    final gateway = app.make<StripeGateway>('payment.gateway');
    await gateway.initialize();
  }
}
```

<a name="the-register-method"></a>
### The Register Method

Within the `register` method, you should only bind things into the service container and register event listeners. You should never attempt to register routes, or any other piece of functionality within the `register` method.

This is because you may accidentally use a service from another provider that has not been loaded yet. Listeners are the exception: `BaseEventServiceProvider` registers them here, so they are in place before any provider's `boot` dispatches an event.

```dart
@override
void register() {
  // ✅ Good: Only bind services
  app.singleton('analytics', () => AnalyticsService());
  app.bind('report', () => ReportGenerator());
  
  // ❌ Bad: Don't use other services here
  // final auth = Auth.manager; // May not be ready!
}
```

#### Binding Types

The service container supports two types of bindings:

| Method | Description |
|--------|-------------|
| `app.bind(key, closure)` | Creates a new instance each time |
| `app.singleton(key, closure)` | Creates a single shared instance |

```dart
// New instance every time
app.bind('report', () => ReportGenerator());

// Same instance every time (singleton)
app.singleton('reports', () => ReportService());
```

<a name="the-boot-method"></a>
### The Boot Method

The `boot` method is called after **all** other service providers have been registered, meaning you have access to all services that have been registered by the framework:

```dart
@override
Future<void> boot() async {
  // ✅ Safe to access any registered service
  final config = Config.get('payment');
  final auth = Auth.manager;

  // Event listeners belong in register(), not here: the auth guard can
  // dispatch AuthLogin during AuthServiceProvider.boot, before this runs.

  // Perform async initialization
  await initializePaymentGateway();
}
```

> [!NOTE]
> The `boot` method supports `async` operations. You may perform asynchronous initialization here.

<a name="registering-providers"></a>
## Registering Providers

All service providers are registered in your `config/app.dart` configuration file using the `providers` key. Each provider is a factory function that receives the application instance:

```dart
import 'package:magic/magic.dart';

Map<String, dynamic> get appConfig => {
  'app': {
    'name': 'My App',
    'providers': [
      // Framework Providers
      (app) => CacheServiceProvider(app),
      (app) => NetworkServiceProvider(app),

      // Application Providers
      (app) => AppServiceProvider(app),
      (app) => PaymentServiceProvider(app),

      // Auth boots after AppServiceProvider has set the user factory
      (app) => AuthServiceProvider(app),
    ],
  },
};
```

### Provider Loading Order

Providers are loaded in the order they are listed:

1. **Register Phase**: `register()` is called on each provider in order
2. **Boot Phase**: `boot()` is called on each provider in order

> [!TIP]
> Place framework providers first, then your custom providers. If Provider B depends on Provider A, ensure A comes before B in the list. `AuthServiceProvider` is the exception to framework-first: its `boot()` restores the stored session with the user factory that `AppServiceProvider.boot()` sets, so it goes after `AppServiceProvider`; in the other order the restore is skipped.

<a name="providers-without-boot-logic"></a>
## Providers Without Boot Logic

Magic has no deferred providers: every registered provider is registered and booted at startup. `boot()` is optional, though. Its default implementation does nothing, so a provider that only binds services overrides `register()` alone:

```dart
class SimpleServiceProvider extends ServiceProvider {
  SimpleServiceProvider(super.app);

  @override
  void register() {
    app.singleton('simple', () => SimpleService());
  }
}
```

<a name="built-in-providers"></a>
## Built-in Providers

Magic includes several built-in service providers for core functionality:

| Provider | Purpose |
|----------|---------|
| `CacheServiceProvider` | Cache stores and drivers |
| `NetworkServiceProvider` | HTTP client configuration |
| `AuthServiceProvider` | Authentication guards and state |
| `LocalizationServiceProvider` | Language and locale support |
| `VaultServiceProvider` | Secure storage |
| `BaseEventServiceProvider` | Event listeners; subclass it to map events to listeners |
| `GateServiceProvider` | Authorization gates and policies; subclass it to define abilities |
| `LaunchServiceProvider` | Opening URLs, email, phone and SMS; not registered by default |

These providers are registered in your `config/app.dart` to enable framework features. Providers from plugin packages, such as `magic_encryption` or `magic_socket`, are added to the same list by `dart run magic:dowel plugin:install <package>`.

<a name="related-documentation"></a>
## Related Documentation

- [Service Container](../architecture/service-container.md): `bind`, `singleton` and `make`.
- [Request Lifecycle](../architecture/request-lifecycle.md): when `register()` and `boot()` run.
- [Configuration](./configuration.md): the `app.providers` list.
- [Events](../digging-deeper/events.md): listeners and `BaseEventServiceProvider`.
- [Authorization](../security/authorization.md): `GateServiceProvider`.
- [Installation](./installation.md): the plugins that add their own providers.

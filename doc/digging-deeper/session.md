# Session & Flash Data

The `Session` facade provides flash data that survives exactly one navigation hop, letting you pass form input and validation errors across a back-navigation without temporary controller state.

- [Introduction](#introduction)
- [Flashing Input](#flashing-input)
- [Flashing Errors](#flashing-errors)
- [Reading Old Input](#reading-old-input)
- [Automatic Flash in MagicFormData](#automatic-flash-in-magicformdata)
- [Advancing the Flash Bucket](#advancing-the-flash-bucket)
- [Testing](#testing)
- [Related Documentation](#related-documentation)

<a name="introduction"></a>
## Introduction

The `Session` facade provides Laravel-style flash data that survives exactly one navigation hop. Use it to repopulate a form after a failed submit and a back navigation without wiring temporary state through controllers, the router, or global singletons.

The store has two buckets: the **current** bucket (readable by the view being built right now) and the **next** bucket (being collected by the currently-active handler). A call to `Session.tick()` promotes `next` into `current`, so flashed data is visible on exactly one frame.

<a name="flashing-input"></a>
## Flashing Input

Flash a map of values before navigating away:

```dart
Session.flash({
  'name': 'John',
  'email': 'john@test.com',
});
MagicRoute.back();
```

<a name="flashing-errors"></a>
## Flashing Errors

Flash per-field error messages:

```dart
Session.flashErrors({
  'email': ['The email has already been taken.'],
});
```

<a name="reading-old-input"></a>
## Reading Old Input

In the form view, repopulate via the `old()` helper:

```dart
WFormInput(
  initialValue: old('email') ?? '',
);

if (Session.hasError('email'))
  WText(Session.error('email')!, className: 'text-red-500');
```

`Session.oldRaw(field)` returns the original typed value (booleans, numbers, custom objects) instead of stringifying it.

<a name="automatic-flash-in-magicformdata"></a>
## Automatic Flash in MagicFormData

`MagicFormData.validate()` automatically flashes the current form data when validation fails, so you never need to wire it manually:

```dart
void _submit() {
  if (!form.validate()) return; // form data is auto-flashed on failure
  controller.register(form.data);
}
```

After a back navigation and a `Session.tick()`, `old('email')` returns the last-submitted value.

<a name="advancing-the-flash-bucket"></a>
## Advancing the Flash Bucket

Flash data survives exactly one navigation. Advance the bucket only when the route stack actually changes. Do **not** wire `Session.tick` directly to the router delegate listener: the delegate can notify for more than real navigation (redirect re-evaluation, notifier rebuilds) and would expire flash data prematurely.

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Magic.init(configFactories: [() => appConfig]);

  final delegate = MagicRouter.instance.routerConfig.routerDelegate;
  var lastConfiguration = delegate.currentConfiguration;

  delegate.addListener(() {
    final currentConfiguration = delegate.currentConfiguration;
    if (currentConfiguration == lastConfiguration) return;
    lastConfiguration = currentConfiguration;
    Session.tick();
  });

  runApp(const MagicApplication(title: 'My App'));
}
```

Wire it in `main()` after `await Magic.init()`, not in a `ServiceProvider.boot()`. Every `boot()` runs inside `Magic.init()`, and the first read of `routerConfig` builds the router. A `boot()` that reads it before `RouteServiceProvider.boot()` has registered the routes freezes the router early, so the next `addRoute` throws a `StateError`. Once `Magic.init()` returns, the router is built with every route in it.

Compare the delegate's `currentConfiguration`, not `MagicRouter.instance.currentLocation`. The delegate sets its configuration and then notifies, while `currentLocation` changes only when the destination page builds, after the listeners have run: a listener reading `currentLocation` sees the previous page and ticks one navigation late. Two configurations are equal when their URI and route matches are, so a re-evaluation that lands on the same stack does not tick, and a push or a pop does.

<a name="testing"></a>
## Testing

In tests, always reset the store in `setUp()`:

```dart
setUp(() {
  MagicApp.reset();
  Magic.flush();
  Session.reset();
});
```

Swap the backing store with a custom `SessionStore` via `Session.setStore(store)` if you need isolated buckets per test group.

<a name="related-documentation"></a>
## Related Documentation

- [Session Scope](./session-scope.md)
- [Validation](./validation.md)
- [Forms](../basics/forms.md)
- [Routing](../basics/routing.md)

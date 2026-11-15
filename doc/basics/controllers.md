# Controllers

Controllers extend `MagicController` (a `ChangeNotifier`) to hold reactive state, run validation, and dispatch navigation, keeping business logic out of the widget tree.

- [Introduction](#introduction)
- [Writing Controllers](#writing-controllers)
    - [Basic Controllers](#basic-controllers)
    - [Single Action Controllers](#single-action-controllers)
- [Controller State Management](#controller-state-management)
    - [The MagicStateMixin](#the-magicstatemixin)
    - [Rendering State](#rendering-state)
    - [Fetch Helpers](#fetch-helpers)
- [Validation Handling](#validation-handling)
- [Running Writes, Timers, and Broadcasts](#running-writes-timers-and-broadcasts)
- [Controller Lifecycle](#controller-lifecycle)
- [Generating Controllers](#generating-controllers)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="introduction"></a>
## Introduction

Instead of defining all of your request handling logic as closures in your route files, you may wish to organise this behaviour using "controller" classes. Controllers can group related request handling logic into a single class. Controllers are stored in the `lib/app/controllers` directory.

<a name="writing-controllers"></a>
## Writing Controllers

<a name="basic-controllers"></a>
### Basic Controllers

To generate a new controller, use the `make:controller` dowel command:

```bash
dart run magic:dowel make:controller User
```

A basic controller extends `MagicController` and contains action methods that return widgets:

```dart
import 'package:material_ui/material_ui.dart';
import 'package:magic/magic.dart';
import '../../resources/views/users/user_list_view.dart';
import '../../resources/views/users/user_show_view.dart';

class UserController extends MagicController {
  /// Singleton accessor, registered on first use.
  static UserController get instance => Magic.findOrPut(UserController.new);

  /// Display a listing of users.
  Widget index() => const UserListView();

  /// Display the specified user.
  Widget show(String id) => UserShowView(userId: id);

  /// Show the form for creating a new user.
  Widget create() => const CreateUserView();
}
```

Register the controller's methods as routes:

```dart
MagicRoute.page('/users', () => UserController.instance.index());
MagicRoute.page('/users/create', () => UserController.instance.create());
MagicRoute.page('/users/:id', (id) => UserController.instance.show(id));
```

> [!NOTE]
> `Magic.findOrPut()` registers the controller in the container on first use and returns that same instance afterwards.

<a name="single-action-controllers"></a>
### Single Action Controllers

If a controller action is particularly complex, you may dedicate an entire controller class to that single action:

```dart
class ExportReportController extends MagicController {
  static ExportReportController get instance => 
      Magic.findOrPut(ExportReportController.new);

  Widget invoke() {
    return const ExportReportView();
  }
}
```

<a name="controller-state-management"></a>
## Controller State Management

<a name="the-magicstatemixin"></a>
### The MagicStateMixin

Controllers may use `MagicStateMixin<T>` to manage async data and loading states:

```dart
class UserController extends MagicController 
    with MagicStateMixin<List<User>> {
  
  static UserController get instance => Magic.findOrPut(UserController.new);

  Widget index() {
    if (isEmpty) loadUsers();
    return const UserListView();
  }

  Future<void> loadUsers() => fetchList('users', User.fromMap);
}
```

`fetchList` drives `setLoading`, `setSuccess`, `setError` and `setEmpty` for you (see [Fetch Helpers](#fetch-helpers)); call the four methods below directly when you load by other means.

#### State Methods

| Method | Description |
|:---|:---|
| `setLoading()` | Set loading state |
| `setSuccess(T data)` | Set success state with data |
| `setError(String message)` | Set error state with message |
| `setEmpty()` | Set empty state (no data) |

#### State Properties

| Property | Type | Description |
|:---|:---|:---|
| `isLoading` | bool | Currently loading |
| `isSuccess` | bool | Successfully loaded |
| `isError` | bool | Error occurred |
| `isEmpty` | bool | Empty/no data |
| `rxState` | T? | The current data |

<a name="fetch-helpers"></a>
### Fetch Helpers

`MagicStateMixin` ships two convenience methods that handle the full loading → success/error/empty cycle without boilerplate. Both delegate to `Http.get()` internally.

#### `fetchList<E>`

Fetch a paginated or collection endpoint. The response body must contain a JSON array under `dataKey` (default: `'data'`).

```dart
Future<void> fetchList<E>(
  String url,
  E Function(Map<String, dynamic>) fromMap, {
  String dataKey = 'data',
  Map<String, dynamic>? query,
  Map<String, String>? headers,
})
```

```dart
class ProjectController extends MagicController
    with MagicStateMixin<List<Project>> {

  static ProjectController get instance =>
      Magic.findOrPut(ProjectController.new);

  Future<void> loadProjects(String teamId) =>
      fetchList('teams/$teamId/projects', Project.fromMap);

  // With query parameters
  Future<void> search(String q) =>
      fetchList('projects', Project.fromMap, query: {'q': q});
}
```

State transitions:

| Condition | Resulting State |
|:---|:---|
| Request fails (4xx/5xx) | `isError` with `response.errorMessage` |
| Transport failure (status `0`: no connection, timeout) | `isError` with the transport exception's message when the driver has one, otherwise `'Failed to load'` |
| Body is not a JSON object | `isEmpty` |
| `dataKey` list is null or empty | `isEmpty` |
| List has items | `isSuccess` with `List<E>` cast to `T` |

`MagicResponse.failed` is true for a status of 400 or more and for status `0`, so a timeout or dead link reaches `setError` rather than the empty state: "no rows" and "nobody answered" are different screens.

#### `fetchOne`

Fetch a single resource. The response body must contain the resource object under `dataKey` (default: `'data'`).

```dart
Future<void> fetchOne(
  String url,
  T Function(Map<String, dynamic>) fromMap, {
  String dataKey = 'data',
  Map<String, dynamic>? query,
  Map<String, String>? headers,
})
```

```dart
class ProjectDetailController extends MagicController
    with MagicStateMixin<Project> {

  static ProjectDetailController get instance =>
      Magic.findOrPut(ProjectDetailController.new);

  Future<void> loadProject(String id) =>
      fetchOne('projects/$id', Project.fromMap);
}
```

State transitions:

| Condition | Resulting State |
|:---|:---|
| Request fails (4xx/5xx) | `isError` with `response.errorMessage` |
| Transport failure (status `0`: no connection, timeout) | `isError` with the transport exception's message when the driver has one, otherwise `'Failed to load'` |
| Body is not a JSON object | `isError` with `'Invalid response format'` |
| `dataKey` value is null | `isError` with `'Resource not found'` |
| Data present | `isSuccess` with parsed `T` |

> [!TIP]
> Both helpers accept optional `query` and `headers` parameters, forwarded directly to `Http.get()`. Use `query` for pagination or filtering parameters.

<a name="rendering-state"></a>
### Rendering State

Use `renderState` in your view to declaratively handle different states, like Blade's `@if` directives:

```dart
class UserListView extends MagicView {
  @override
  Widget build(BuildContext context) {
    final controller = UserController.instance;
    
    return controller.renderState(
      (users) => ListView.builder(
        itemCount: users.length,
        itemBuilder: (_, i) => UserCard(user: users[i]),
      ),
      onLoading: Center(child: CircularProgressIndicator()),
      onError: (msg) => WText(msg),
      onEmpty: EmptyState(message: 'No users yet'),
    );
  }
}
```

<a name="validation-handling"></a>
## Validation Handling

Controllers can handle server-side validation errors using the `ValidatesRequests` mixin:

```dart
class AuthController extends MagicController 
    with MagicStateMixin<bool>, ValidatesRequests {
  
  static AuthController get instance => Magic.findOrPut(AuthController.new);

  Future<void> register(Map<String, dynamic> data) async {
    setLoading();
    clearErrors();  // Clear previous validation errors
    
    final response = await Http.post('/register', data: data);
    
    if (response.successful) {
      setSuccess(true);
      Magic.success('Success', 'Account created!');
      MagicRoute.to('/dashboard');
    } else {
      // Automatically handles 422 validation errors
      handleApiError(response, fallback: 'Registration failed');
    }
  }
}
```

### ValidatesRequests Methods

| Method | Description |
|:---|:---|
| `handleApiError(response)` | Handle 422 and other API errors automatically |
| `setErrorsFromResponse(response)` | Populate errors from 422 validation response |
| `hasError('field')` | Check if a field has an error |
| `getError('field')` | Get error message for a field |
| `hasErrors` | Check if any validation errors exist |
| `clearErrors()` | Clear all validation errors |

> [!TIP]
> Use `MagicFormData` in your view to collect form data. The validation errors automatically bind to form fields.

<a name="running-writes-timers-and-broadcasts"></a>
## Running Writes, Timers, and Broadcasts

Two mixins close the gaps a controller doing more than read-and-render runs into: `RunsActions` for a write and `OwnsTimers` for anything on a `Timer`. A third, `ListensToBroadcasts` for a shared realtime channel, ships in the `magic_socket` plugin (`flutter pub add magic_socket`, then `dart run magic:dowel plugin:install magic_socket`); see its [listeners page](https://anilcancakir.com/magic/docs/socket/basics/listeners). The two mixins above are documented in full at their own pages; this is the controller-side shape.

```dart
class MonitorController extends MagicController with RunsActions, OwnsTimers {
  Future<void> pause(String id) async {
    final outcome = await runAction(MagicAction.resolve(PauseMonitor.new), id, key: id);   // doc/basics/actions.md
    if (!outcome.succeeded) return;
  }

  void startCooldown(String id) => own(Countdown()).start(id, 30);     // cancelled on close automatically
}
```

`own(cancellable)` accepts a `PollHandle`, a `Countdown`, a `Debouncer`, a bare `Timer`, or a `StreamSubscription`, and hands it back so a call can chain (`final poll = own(Poll.until(...));`); `OwnsTimers.onClose` cancels every one of them, so a controller never hand-writes its own cancellation list. See `doc/digging-deeper/helpers.md` for `LatestRead`, `Poll`, `Countdown`, and `Debouncer` themselves.

<a name="controller-lifecycle"></a>
## Controller Lifecycle

Controllers have lifecycle methods you can override:

```dart
class UserController extends MagicController {
  @override
  void onInit() {
    super.onInit();
    // Called once, the first time a stateful view backs the controller
    // Initialize data, start listeners, etc.
  }

  @override
  void onClose() {
    // Called when the controller is disposed
    // Cancel subscriptions, clean up resources
    super.onClose();
  }
}
```

A controller is a Type-keyed singleton, so `onInit` runs once per instance and not on every mount of a view; a view that must refetch on each mount mixes `RefetchesOnMount` into its state. `refreshUI()` is the call that notifies listeners: it is a no-op once the controller is disposed. `SimpleMagicController` runs `onInit` from its constructor instead.

<a name="generating-controllers"></a>
## Generating Controllers

```bash
# Plain controller (the Controller suffix is appended when omitted)
dart run magic:dowel make:controller User

# Nested in a subfolder
dart run magic:dowel make:controller Admin/Dashboard

# Read controller over a repository
dart run magic:dowel make:controller Monitor --resource

# Read controller over another model's repository
dart run magic:dowel make:controller Monitor --resource --model=Ping

# Mix in the helpers, and scaffold the matching test
dart run magic:dowel make:controller Monitor --actions --timers --validates --test
```

### Command Options

| Option | Alias | Description |
|:---|:---|:---|
| `--resource` | `-r` | Generate a read controller that owns a `RepositoryQuery` over `<Model>Repository` |
| `--model` | `-m` | The model a `--resource` controller reads (default: the controller's own name) |
| `--actions` | | Mix in `RunsActions` |
| `--timers` | | Mix in `OwnsTimers` |
| `--validates` | | Mix in `ValidatesRequests` and `CollapsesIndexedErrorKeys` |
| `--test` | | Also scaffold the matching test |
| `--force` | | Overwrite an existing file |

Every generated controller has the `instance` accessor and implements `SessionScoped` (a plain one gets a `resetForSession` stub to fill in).

### Resource Controllers

A `--resource` controller imports `lib/app/models/<model>.dart` and `lib/app/repositories/<model>_repository.dart` and carries the read state only: `items`, `ensureFresh()` and `reload()`, with the query started in `onInit` and disposed in `onClose`. A write belongs on a `MagicAction`, not on the controller (see [Actions](./actions.md)).

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:---|:---|
| Loading data in `onInit` and expecting it to run on every visit | `onInit` fires once per controller instance, because controllers are Type-keyed singletons. Mix `RefetchesOnMount` into the view state when each mount must refetch |
| Omitting `super.onInit()` or `super.onClose()` | Both are `@mustCallSuper`; `OwnsTimers` cancels its timers inside `onClose`, so skipping the super call leaks them |
| Calling `notifyListeners()` directly | Call `refreshUI()`: it guards against a disposed controller and feeds the perf hooks |
| Caching per-user rows on a controller with no session hook | Implement `SessionScoped` so a login or team switch clears them, see [Session Scope](../digging-deeper/session-scope.md) |
| A view built on a controller nobody registered | `MagicView.controller` is `Magic.find<T>()`, so reach the controller through the `Magic.findOrPut(Controller.new)` accessor (or `Magic.put`) first |
| Calling `own(...)` on a controller that is already disposed | It throws a `StateError`; register timers in `onInit` or while the controller is alive |

<a name="related-documentation"></a>
## Related Documentation

- [Actions](./actions.md)
- [Views](./views.md)
- [Forms](./forms.md)
- [Routing](./routing.md)
- [Validation](../digging-deeper/validation.md)
- [Session Scope](../digging-deeper/session-scope.md)
- [Helpers](../digging-deeper/helpers.md)
- [Magic CLI](../packages/magic-cli.md): `make:controller` and its options.

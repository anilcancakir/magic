# Authentication

Magic provides a frontend-focused authentication system with secure token storage, user caching, automatic token refresh, and support for multiple configurable guards.

- [Introduction](#introduction)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [The Auth Facade](#the-auth-facade)
- [Guards](#guards)
    - [Built-in Guards](#built-in-guards)
    - [Custom Guards](#custom-guards)
- [Reactive Auth State](#reactive-auth-state)
- [Auto Token Refresh](#auto-token-refresh)
- [Protecting Routes](#protecting-routes)
- [Login & Logout](#login--logout)
- [Auth Events](#auth-events)
- [Testing](#testing)
- [Related Documentation](#related-documentation)

<a name="introduction"></a>
## Introduction

Magic provides a simple, frontend-focused authentication system with user caching and automatic token refresh. Like Laravel's Auth system, it's built around the concept of "guards" that define how users are authenticated.

### Key Features

| Feature | Description |
|---------|-------------|
| **User Caching** | Instant restore from secure cache, then sync from API |
| **Auto Token Refresh** | 401 response → refresh token → retry original request (for guards built with a refresh endpoint) |
| **Multiple Guards** | Support for Bearer, Basic, API Key, or custom guards |
| **Secure Storage** | Tokens stored in platform secure storage (Keychain/Keystore) |

<a name="quick-start"></a>
## Quick Start

```dart
// 1. Register user factory (tells Magic how to create User from API data)
Auth.registerModel<User>(User.fromMap);

// 2. Login after API call
final response = await Http.post('/login', data: {
  'email': email,
  'password': password,
});

if (response.successful) {
  final user = User.fromMap(response['data']['user']);
  await Auth.login({
    'token': response['data']['token'],
  }, user);
  
  MagicRoute.to('/dashboard');
}

// 3. Check authentication anywhere
if (Auth.check()) {
  final user = Auth.user<User>();
  print('Welcome, ${user?.name}');
}

// 4. Logout
await Auth.logout();
MagicRoute.to('/login');
```

> [!WARNING]
> `logout()` can throw. Secure storage is a platform service and a delete can
> fail (a locked keychain, a lost entitlement). When it does, every step is
> still attempted and the in-memory session is still cleared and announced, so
> your UI is correct either way, but the throw reaches you because a credential
> may have survived on the device. Navigate away and surface it; do not swallow
> it:
>
> ```dart
> try {
>   await Auth.logout();
> } catch (e) {
>   Log.warning('Logout could not clear stored credentials: $e');
> } finally {
>   MagicRoute.to('/login');
> }
> ```

<a name="configuration"></a>
## Configuration

Create `lib/config/auth.dart`:

```dart
Map<String, dynamic> get authConfig => {
  'auth': {
    'defaults': {
      'guard': 'api',
    },
    'guards': {
      'api': {
        'driver': 'bearer',
      },
    },
    'endpoints': {
      'user': '/api/user',
    },
    'token': {
      'key': 'auth_token',
      'header': 'Authorization',
      'prefix': 'Bearer',
    },
    'auto_refresh': true,
  },
};
```

Register in your config and add `AuthServiceProvider`:

```dart
'providers': [
  (app) => AuthServiceProvider(app),
  // ...
],
```

<a name="the-auth-facade"></a>
## The Auth Facade

The `Auth` facade provides convenient access to authentication functionality:

```dart
// Check if user is authenticated
Auth.check()              // bool

// Check if user is a guest (not authenticated)
Auth.guest                // bool (a getter)

// Get the authenticated user
Auth.user<User>()         // User?

// Get user ID
Auth.id()                 // dynamic

// Login
await Auth.login(tokenData, user)

// Logout
await Auth.logout()

// Restore session from cache
await Auth.restore()

// Manually refresh token
await Auth.refreshToken()

// Token management
await Auth.hasToken()     // bool
await Auth.getToken()     // String?

// Resolve a guard by name (default guard when name is omitted)
Auth.guard()              // Guard
Auth.guard('api')         // Guard (named)

// Notifier that bumps on every auth state change
Auth.stateNotifier        // ValueNotifier<int>
```

<a name="guards"></a>
## Guards

Guards define how users are authenticated. Each guard implements the `Guard` contract:

```dart
abstract class Guard {
  Future<void> login(Map<String, dynamic> data, Authenticatable user);
  Future<void> logout();
  bool check();
  bool get guest => !check();
  T? user<T extends Model>();
  dynamic id();
  void setUser(Authenticatable user);
  Future<bool> hasToken();
  Future<String?> getToken();
  Future<bool> refreshToken();
  Future<void> restore();

  /// Bumped on every auth state change (login, logout, restore).
  ValueNotifier<int> get stateNotifier;
}
```

<a name="built-in-guards"></a>
### Built-in Guards

| Guard | `driver` | Login Data | Use Case |
|-------|----------|-----------|----------|
| `BearerTokenGuard` | `bearer` (or `sanctum`) | `token` | JWT/OAuth APIs |
| `BasicAuthGuard` | `basic` | `username`, `password` | Basic HTTP Auth |
| `ApiKeyGuard` | `api_key` | `api_key` | API Key authentication |

<a name="custom-guards"></a>
### Custom Guards

Create custom guards by extending `BaseGuard`:

```dart
class MyGuard extends BaseGuard {
  MyGuard() : super(
    userEndpoint: '/api/me',
    refreshEndpoint: '/api/refresh',
    refreshTokenKey: 'refresh_token',
    userFactory: (data) => User.fromMap(data),
  );

  @override
  Future<void> login(Map<String, dynamic> data, Authenticatable user) async {
    await startSession(
      user,
      token: data['token'] as String?,
      refreshToken: data['refresh_token'] as String?,
    );
  }
}

// Register the driver, then name it in a guard's `driver` config key
Auth.manager.extend('myguard', (config) => MyGuard());
```

`startSession` marks the session as opened and moves the in-memory token before its first await, then persists the tokens, sets the user and caches it. Prefer it to `storeToken` followed by `setUser`: both mark a new session, so a boot-time user sync or a refresh still in the air ignores its answer, and both delete a stored refresh token the new session does not carry, but only `startSession` also deletes the stored access token when the login carries none and leaves the user alone when a newer sign-in began during its writes.

### Firebase Guard Example

```dart
class FirebaseGuard extends BaseGuard {
  final _auth = firebase.FirebaseAuth.instance;

  FirebaseGuard() : super(userFactory: (data) => User.fromMap(data));

  @override
  Future<void> login(Map<String, dynamic> data, Authenticatable user) async {
    final idToken = await _auth.currentUser?.getIdToken();
    await startSession(user, token: idToken);
  }

  @override
  Future<void> restore() async {
    // Try cached user first (instant UI)
    final cached = await loadCachedUser();
    if (cached != null) setUser(cached);

    // Then verify with Firebase
    final fbUser = _auth.currentUser;
    if (fbUser == null) {
      await logout();
      return;
    }

    final user = userFactory!({
      'id': fbUser.uid,
      'email': fbUser.email,
      'name': fbUser.displayName,
    });
    await startSession(user, token: await fbUser.getIdToken());
  }

  @override
  Future<void> logout() async {
    await _auth.signOut();
    await super.logout();
  }
}
```

<a name="reactive-auth-state"></a>
## Reactive Auth State

Every guard exposes a `ValueNotifier<int> stateNotifier` that increments on every auth state change (`setUser()`, `logout()`, and session restore). Use it to reactively rebuild UI without manual state management.

```dart
// Using ListenableBuilder (Flutter built-in)
ListenableBuilder(
  listenable: Auth.stateNotifier,
  builder: (context, _) {
    if (Auth.check()) {
      return Text('Hello, ${Auth.user<User>()?.name}');
    }
    return const Text('Not logged in');
  },
)
```

With `MagicBuilder` the pattern is identical; pass `stateNotifier` as the listenable:

```dart
MagicBuilder(
  listenable: Auth.stateNotifier,
  builder: (context, _) => Auth.check()
      ? const DashboardView()
      : const LoginView(),
)
```

`setUser()` is called internally by `login()`, `restore()`, and any custom guard that calls `setUser(user)` directly. Each call bumps `stateNotifier.value` by 1, triggering all registered listeners.

<a name="auto-token-refresh"></a>
## Auto Token Refresh

`AuthServiceProvider` registers an `AuthInterceptor` on the network driver, which handles 401 responses:

1. Original request fails with 401, **having presented the token**
2. Interceptor calls `Auth.refreshToken()`
3. If refresh succeeds, original request is retried with new token
4. If refresh fails, user is logged out (unless the session changed meanwhile, see below)

`BaseGuard.refreshToken()` returns `false` unless the guard was built with both `refreshEndpoint` and `refreshTokenKey`. The built-in guards resolved from the `auth` config are built with neither, so for them step 4 follows any 401 on a presented credential. To refresh tokens, register a custom guard that passes both (see [Custom Guards](#custom-guards)). The refresh posts `{'refresh_token': ...}` to `refreshEndpoint` and reads `token` or `access_token` (at the top level or under `data`) and an optional `refresh_token` from the response.

**A 401 on a request that carried no auth header, or an older token, is ignored.** The ladder above runs only when the refused request actually presented the header `auth.token.header` names, matched without regard to case, carrying the token the guard holds now. A request dispatched before a sign-in completed goes out anonymous, and its refusal arrives once the session exists; treating that as a rejection would end a session the server was never shown. Only a credential the server actually saw and refused ends a session.

**A request that raced a token change is handed back refused, not replayed.** When the refused request carried an older token and the guard already holds a newer one, the interceptor cannot tell a refresh from a different account signing in, and a replay with the newer token could answer one account's screen with another account's data. The caller receives the 401 and decides whether its request still stands.

**A refresh belongs to the session it started in.** When a sign-in, a sign-out or a restore of another account's token lands while a refresh is in the air, the refreshed token is discarded and the refused request is handed back with no retry and no logout, so the new session keeps its own token and stays signed in. A retry already on its way is sent with the refreshed token, never the new session's, and its answer is handed back as the 401. A sign-in without a `token` or a `refresh_token` deletes the stored one, so it never inherits the previous account's. `storeToken` counts as a sign-in too, and drops a stored refresh token it is not given; a custom guard that rotates its own token through it gets no retry and loses an in-flight boot sync, so rotate through `refreshToken()` with a `refreshEndpoint` instead.

**A guard that does not extend `BaseGuard`** keeps no token the interceptor can compare against, so it is judged on presence alone: a 401 ends its session only when the request carried the header `auth.token.header` names. A cookie-based guard, or one that sends its credential under another header, stays signed in while calls return 401; such a guard has to end its own session.

`Auth.refreshToken()` also returns `false` when the session changed while the refresh was in the air, so the example below signs out only when the stored token is still the one it refreshed. Comparing the stored token with the one that was refreshed does not detect a sign-in that stores the same token, so the example below can sign out a replacement session in that case. It can also sign out a sign-in that is still writing its tokens, because the second read can still find the previous token on disk. No public session-identity check is available.

```dart
// Manual token refresh
final refreshed = await Auth.getToken();
final success = await Auth.refreshToken();
if (!success && await Auth.getToken() == refreshed) {
  await Auth.logout();
  MagicRoute.to('/login');
}
```

<a name="protecting-routes"></a>
## Protecting Routes

Core ships no `auth` middleware: write one that checks `Auth.check()`, register it in the `Kernel` under an alias (see [Middleware](../basics/middleware.md)), and name the alias on the route:

```dart
class EnsureAuthenticated extends MagicMiddleware {
  @override
  String? redirectTarget(String location) {
    if (!Auth.check() && location != '/login') return '/login';
    return null;
  }
}

Kernel.register('auth', () => EnsureAuthenticated());

// Single route
MagicRoute.page('/dashboard', () => DashboardView())
    .middleware(['auth']);

// Route group
MagicRoute.group(
  middleware: ['auth'],
  routes: () {
    MagicRoute.page('/dashboard', () => DashboardView());
    MagicRoute.page('/profile', () => ProfileView());
    MagicRoute.page('/settings', () => SettingsView());
  },
);
```

Write a `guest` middleware the same way to redirect authenticated users:

```dart
class RedirectIfAuthenticated extends MagicMiddleware {
  @override
  String? redirectTarget(String location) {
    if (Auth.check() && location != '/dashboard') return '/dashboard';
    return null;
  }
}
```

<a name="login--logout"></a>
## Login & Logout

### Login Flow

```dart
class AuthController extends MagicController with ValidatesRequests {
  Future<void> login(Map<String, dynamic> data) async {
    clearErrors();
    
    final response = await Http.post('/login', data: data);
    
    if (response.successful) {
      final user = User.fromMap(response['data']['user']);
      
      await Auth.login({
        'token': response['data']['token'],
      }, user);
      
      Magic.success('Success', 'Welcome back!');
      MagicRoute.to('/dashboard');
    } else {
      handleApiError(response, fallback: 'Invalid credentials');
    }
  }
}
```

### Logout Flow

```dart
Future<void> logout() async {
  // Optionally notify backend
  await Http.post('/logout');
  
  // Clear local auth state
  await Auth.logout();
  
  Magic.snackbar('Logged Out', 'See you next time!');
  MagicRoute.to('/login');
}
```

### Restoring Session on App Start

`AuthServiceProvider.boot()` restores the session during `Magic.init`: when a user factory is registered (`Auth.registerModel` or `Auth.manager.setUserFactory`) and `auto_refresh` is not `false`, it calls `Auth.restore()`. Register the factory in a provider listed before `AuthServiceProvider`; a stored session with no factory is not restored and logs a warning.

With `auto_refresh` set to `false` the provider skips the restore, so call it yourself in `main.dart`:

```dart
void main() async {
  await Magic.init(...);
  
  // Restore auth session from cache
  await Auth.restore();
  
  runApp(MagicApplication(...));
}
```

A restore loads the cached user for a fast startup, then syncs with the API in the background.

A sign-in or a sign-out that completes while the sync is in the air wins: a late 401 about the restored token does not log out the new session, and a late 200 does not put the previous account back. A token refresh is not a new session, so a 200 that arrives under a refreshed token is still applied, and a 401 or 403 about a token that has since been refreshed is re-checked once under the current token, whose answer decides.

If `userFactory` is not set on the guard, the cache load and API sync steps are skipped gracefully (no error is thrown). Set `userFactory` via `Auth.manager.setUserFactory()` (or pass it to `BaseGuard`'s constructor) during the boot phase to enable full session restore.

<a name="auth-events"></a>
## Auth Events

`BaseGuard` (and `FakeAuthManager`'s fake guard) dispatch `MagicEvent`s through the `Event` facade; see [Events](../digging-deeper/events.md#framework-events) for `Event.listen<T>`'s registration shape.

- **`AuthLogin`** fires at the end of `startSession`, once the token (when given) is persisted and the user is set and cached. Not fired on a restore; a restored user announces itself through `AuthRestored` instead. Skipped when the session ended or was replaced while the user was being cached, so a sign-out racing a sign-in never gets a stray `AuthLogin` for the session it just ended.
- **`AuthLogout`** fires from `logout()`, after the `stateNotifier` bump and before a rethrown Vault failure. It carries the user held when the logout began (`null` for a guest), and a guest logout still dispatches. It means "the in-memory session ended", not "the credentials are gone": it fires even when a Vault delete failed, so a listener releasing server-side state must still gate on `Auth.hasToken()`.
- **`AuthRestored`** fires only after an API-confirmed sync (`BaseGuard`'s background `/user` fetch inside `restore()`), never for the cache-only step that runs first. A sign-in or sign-out racing that sync suppresses it the same way `AuthLogin` is suppressed. Its `changed` field is `false` when the synced user serializes (`toMap()`, compared deeply) the same as the user the guard held before the sync, the usual warm cold boot, and `true` when an attribute moved or no user was held; a listener that remounts or refetches on it should skip `changed: false`. It defaults to `true` for an event built by hand.

```dart
class LogAuthEvents extends MagicListener<AuthLogout> {
  @override
  Future<void> handle(AuthLogout event) async {
    Log.info('Session ended for ${event.user?.authIdentifier ?? 'guest'}');
  }
}

Event.listen<AuthLogout>(() => LogAuthEvents());
```

<a name="testing"></a>
## Testing

Replace the real auth manager with a `FakeAuthManager` using `Auth.fake()`. The fake routes all guard operations through an in-memory guard so tests run without platform channels or a real backend. Its `login()` and `logout()` dispatch `AuthLogin`/`AuthLogout` through the real `Event` facade too, same as the real guard, so a listener under test observes a faked session exactly as it would a real one.

```dart
import 'package:magic/testing.dart';

void main() {
  setUp(() {
    MagicApp.reset();
    Magic.flush();
  });

  tearDown(() => Auth.unfake());

  test('login sets authenticated state', () async {
    final fake = Auth.fake();

    await Auth.login({'token': 'abc'}, myUser);

    fake.assertLoggedIn();
    fake.assertLoginCount(1);
    expect(Auth.check(), isTrue);
    expect(Auth.user<User>(), same(myUser));
  });

  test('logout clears auth state', () async {
    final fake = Auth.fake(user: myUser);

    await Auth.logout();

    fake.assertLoggedOut();
  });
}
```

### FakeAuthManager Assertions

| Method | Description |
|--------|-------------|
| `fake.assertLoggedIn()` | Fails if no user is currently set. |
| `fake.assertLoggedOut()` | Fails if a user is currently set. |
| `fake.assertLoginAttempted()` | Fails if `Auth.login()` was never called. |
| `fake.assertLoginCount(n)` | Fails if `Auth.login()` was not called exactly `n` times. |
| `fake.reset()` | Clears user, token, and login-attempt history. |

Call `Auth.unfake()` in `tearDown()` to restore normal auth resolution after each test.

<a name="related-documentation"></a>
## Related Documentation

- [Authorization](./authorization.md)
- [Vault](./vault.md)
- [Middleware](../basics/middleware.md)
- [HTTP Client](../basics/http-client.md)
- [Events](../digging-deeper/events.md)

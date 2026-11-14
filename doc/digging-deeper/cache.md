# Cache

Magic provides an expressive, unified API for various caching backends, with built-in event dispatching so you can react to cache reads, writes, and removals.

- [Introduction](#introduction)
- [Configuration](#configuration)
- [Retrieving Items](#retrieving-items)
- [Storing Items](#storing-items)
- [The Remember Method](#the-remember-method)
- [Removing Items](#removing-items)
- [Custom Cache Drivers](#custom-cache-drivers)
- [Cache Events and Listeners](#cache-events-and-listeners)
- [Testing](#testing)
- [Related Documentation](#related-documentation)

<a name="introduction"></a>
## Introduction

Magic provides an expressive, unified API for various caching backends. The framework ships with a native `FileStore` driver that supports both Mobile/Desktop (File System) and Web (LocalStorage).

Caching is essential for reducing API calls, storing computed values, and improving application performance.

<a name="configuration"></a>
## Configuration

### Enabling Cache Support

Add `CacheServiceProvider` to your providers in `config/app.dart`:

```dart
'providers': [
  (app) => CacheServiceProvider(app),
  // ... other providers
],
```

### Cache Configuration

Create `lib/config/cache.dart`:

```dart
import 'package:magic/magic.dart';

Map<String, dynamic> get cacheConfig => {
  'cache': {
    'driver': FileStore(fileName: 'magic_cache'),
    'ttl': 3600, // Default TTL in seconds
  },
};
```

<a name="retrieving-items"></a>
## Retrieving Items

Use the `Cache` facade to retrieve items from the cache:

```dart
// Basic retrieval
final value = Cache.get('key');

// With default value
final username = Cache.get('username', defaultValue: 'Guest');

// Check existence
if (Cache.has('user_settings')) {
  final settings = Cache.get('user_settings');
}
```

`Cache.get()` and `Cache.has()` are synchronous. The write methods (`put`, `forget`, `flush`) and `remember` return a `Future`.

<a name="storing-items"></a>
## Storing Items

Store items with optional TTL (time-to-live):

```dart
// With custom TTL
await Cache.put('key', 'value', ttl: Duration(minutes: 10));

// With default TTL from config
await Cache.put('key', 'value');

// Store any serializable data
await Cache.put('user', {
  'id': 1,
  'name': 'John',
  'email': 'john@example.com',
});
```

<a name="the-remember-method"></a>
## The Remember Method

`Cache.remember()` retrieves an item from the cache, or computes and stores it:

```dart
final users = await Cache.remember(
  'users',
  Duration(minutes: 5),
  () async {
    final response = await Http.get('/users');
    return response.data;
  },
);
```

This method:
1. Checks if `users` exists in cache
2. If yes, returns the cached value
3. If no, calls the closure, stores the result, and returns it

### API Response Caching

```dart
class UserController extends MagicController {
  Future<List<User>> getUsers() async {
    return await Cache.remember('all_users', Duration(minutes: 10), () async {
      final response = await Http.get('/users');
      return (response.data as List).map((u) => User.fromMap(u)).toList();
    });
  }
}
```

### Computed Values

```dart
final dashboardStats = await Cache.remember('dashboard_stats', Duration(hours: 1), () async {
  final response = await Http.get('/dashboard/stats');
  return response.data;
});
```

<a name="removing-items"></a>
## Removing Items

```dart
// Remove a single item
await Cache.forget('users');

// Clear entire cache
await Cache.flush();
```

### Invalidating Related Cache

```dart
class UserController extends MagicController {
  Future<void> updateUser(Map<String, dynamic> data) async {
    final response = await Http.put('/users/${data['id']}', data: data);

    if (response.successful) {
      // Invalidate related caches
      await Cache.forget('all_users');
      await Cache.forget('user_${data['id']}');
      await Cache.forget('dashboard_stats');
    }
  }
}
```

<a name="custom-cache-drivers"></a>
## Custom Cache Drivers

Implement `CacheStore` for custom backends. `get()` and `has()` are synchronous in the contract, so a driver that talks to a remote backend keeps a local copy and loads it in `init()`, as `FileStore` does:

```dart
class MemoryStore implements CacheStore {
  final Map<String, dynamic> _items = {};
  final Map<String, DateTime> _expiresAt = {};

  @override
  Future<void> init() async {}

  @override
  dynamic get(String key, {dynamic defaultValue}) {
    return has(key) ? _items[key] : defaultValue;
  }

  @override
  Future<void> put(String key, dynamic value, {Duration? ttl}) async {
    _items[key] = value;

    // A null ttl means the item never expires.
    if (ttl == null) {
      _expiresAt.remove(key);
    } else {
      _expiresAt[key] = DateTime.now().add(ttl);
    }
  }

  @override
  bool has(String key) {
    final expiresAt = _expiresAt[key];

    if (expiresAt != null && !DateTime.now().isBefore(expiresAt)) {
      _items.remove(key);
      _expiresAt.remove(key);
    }

    return _items.containsKey(key);
  }

  @override
  Future<void> forget(String key) async {
    _items.remove(key);
    _expiresAt.remove(key);
  }

  @override
  Future<void> flush() async {
    _items.clear();
    _expiresAt.clear();
  }
}
```

Use your custom driver in config:

```dart
'cache': {
  'driver': MemoryStore(),
},
```

> [!TIP]
> Use caching for expensive API calls, complex computations, and data that doesn't change frequently.

<a name="cache-events-and-listeners"></a>
## Cache Events and Listeners

Magic dispatches events on every cache operation. You can listen to these events via your `AppEventServiceProvider` to add logging, metrics, or invalidation side-effects without coupling that logic to call sites.

### Event Classes

All cache events extend `MagicEvent` and live in `package:magic/magic.dart`:

| Event | Payload | Fired when |
|-------|---------|-----------|
| `CacheHit` | `key`, `value` | A `Cache.get()` returns a stored value. |
| `CacheMiss` | `key` | A `Cache.get()` finds no stored value. |
| `CachePut` | `key`, `value`, `ttl?` | A value is written via `Cache.put()` or `Cache.remember()`. |
| `CacheForget` | `key` | A single key is removed via `Cache.forget()`. |
| `CacheFlush` | _(none)_ | The entire cache is cleared via `Cache.flush()`. |

### Listening to Cache Events

Register listeners in your `AppEventServiceProvider`:

```dart
import 'package:magic/magic.dart';

class LogCacheHit extends MagicListener<CacheHit> {
  @override
  Future<void> handle(CacheHit event) async {
    Log.debug('Cache hit: ${event.key}');
  }
}

class LogCacheMiss extends MagicListener<CacheMiss> {
  @override
  Future<void> handle(CacheMiss event) async {
    Log.debug('Cache miss: ${event.key}');
  }
}
```

Then wire them in your event service provider:

```dart
import 'package:magic/magic.dart';

class AppEventServiceProvider extends BaseEventServiceProvider {
  AppEventServiceProvider(super.app);

  @override
  Map<Type, List<MagicListener Function()>> get listen => {
    CacheHit: [() => LogCacheHit()],
    CacheMiss: [() => LogCacheMiss()],
    CachePut: [() => RecordCacheWrite()],
    CacheForget: [() => RecordCacheRemoval()],
    CacheFlush: [() => RecordCacheFlush()],
  };
}
```

The separate `magic_devtools` package can observe these events during development; core does not depend on it.

<a name="testing"></a>
## Testing

Use `Cache.fake()` to replace the real cache manager with an in-memory `FakeCacheManager` during tests. The fake supports assertions and records every operation.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic/testing.dart';

void main() {
  setUp(() {
    MagicApp.reset();
    Magic.flush();
  });

  test('caches users after first fetch', () async {
    final fake = Cache.fake();

    await Cache.put('users', ['alice', 'bob']);

    fake.assertHas('users');
    fake.assertPut('users');
  });

  test('cleans up after test', () async {
    final fake = Cache.fake();
    fake.reset(); // clears store and recorded operations
    Cache.unfake();
  });
}
```

`FakeCacheManager` exposes:

- `assertHas(key)`: asserts the key currently exists in the store.
- `assertMissing(key)`: asserts the key is absent.
- `assertPut(key)`: asserts the key was stored at least once via `put`.
- `recorded`: the full chronological list of cache operations for manual inspection.
- `reset()`: clears the store and the recorded list between assertions.

<a name="related-documentation"></a>
## Related Documentation

- [Events](./events.md)
- [Logging](./logging.md)
- [Service Providers](../getting-started/service-providers.md)

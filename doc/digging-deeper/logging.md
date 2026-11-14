# Logging

The `Log` facade provides a Laravel-style logging API with configurable channels, minimum log levels, and a stack channel for fanning output to multiple drivers simultaneously.

- [Introduction](#introduction)
- [Configuration](#configuration)
    - [Available Channels](#available-channels)
    - [Minimum Log Level](#minimum-log-level)
    - [Stack Channel](#stack-channel)
- [Writing Log Messages](#writing-log-messages)
    - [Log Levels](#log-levels)
    - [Contextual Information](#contextual-information)
- [Creating Custom Channels](#creating-custom-channels)
    - [Implementing a Custom Driver](#implementing-a-custom-driver)
    - [Registering the Custom Driver](#registering-the-custom-driver)
- [Error Reporting](#error-reporting)
- [Testing](#testing)
- [Related Documentation](#related-documentation)

<a name="introduction"></a>
## Introduction

Magic provides a Laravel-style logging system based on RFC 5424 severity levels. The `Log` facade provides a simple interface for writing log messages to the configured channels.

The logging system is:
- **Channel-Based**: Route logs to specific destinations using named channels.
- **Extensible**: Create custom drivers to send logs anywhere (a webhook, a file, a remote service).
- **Level-Aware**: Filter messages based on severity threshold.

The `log` binding is registered by the framework itself, so `Log` works without a service provider.

<a name="configuration"></a>
## Configuration

The defaults log to the console through a `stack` channel. To customise them, create `lib/config/logging.dart`:

```dart
// lib/config/logging.dart
Map<String, dynamic> get loggingConfig => {
  'logging': {
    // Default channel used by the Log facade
    'default': 'stack',

    // Channel configurations
    'channels': {
      'console': {
        'driver': 'console',
        'level': 'debug',
      },

      'production': {
        'driver': 'console',
        'level': 'warning', // Only warning and above
      },

      'stack': {
        'driver': 'stack',
        'channels': ['console'],
      },
    },
  },
};
```

<a name="available-channels"></a>
### Available Channels

Magic includes these built-in drivers:

| Driver | Description |
|--------|-------------|
| `console` | Pretty-prints to the debug console with colors and emojis |
| `stack` | Broadcasts to multiple channels simultaneously |

A channel with an unknown `driver` name falls back to `console`, unless a custom driver is registered under that name (see [Creating Custom Channels](#creating-custom-channels)).

<a name="minimum-log-level"></a>
### Minimum Log Level

The `console` channel can specify a minimum `level`. Messages below this threshold are ignored:

```dart
'channels': {
  'production': {
    'driver': 'console',
    'level': 'warning', // Ignores debug, info, notice
  },
}
```

**Levels by priority** (RFC 5424):

| Level | Priority | Description |
|-------|----------|-------------|
| `emergency` | 0 | System is unusable |
| `alert` | 1 | Action must be taken immediately |
| `critical` | 2 | Critical conditions |
| `error` | 3 | Runtime errors |
| `warning` | 4 | Warning conditions |
| `notice` | 5 | Normal but significant |
| `info` | 6 | Informational |
| `debug` | 7 | Detailed debug information |

<a name="stack-channel"></a>
### Stack Channel

Use the `stack` driver to send logs to multiple channels at once:

```dart
'stack': {
  'driver': 'stack',
  'channels': ['console', 'slack'],
}
```

When you log to the `stack` channel, the message is forwarded to every channel listed in `channels`.

<a name="writing-log-messages"></a>
## Writing Log Messages

<a name="log-levels"></a>
### Log Levels

Use the `Log` facade to write messages at any RFC 5424 level:

```dart
Log.emergency('System is unusable');
Log.alert('Action must be taken immediately');
Log.critical('Critical condition');
Log.error('Runtime error');
Log.warning('Warning condition');
Log.notice('Normal but significant condition');
Log.info('Informational message');
Log.debug('Debug-level message');
```

For dynamic level selection:

```dart
Log.log('info', 'User logged in');
```

<a name="contextual-information"></a>
### Contextual Information

Pass additional data as the second argument:

```dart
Log.error('Payment failed', {
  'user_id': user.id,
  'amount': 50.00,
  'error': e.toString(),
  'stack_trace': stackTrace.toString(),
});
```

The console driver prints the context below the message.

<a name="creating-custom-channels"></a>
## Creating Custom Channels

Magic's logging system is extensible. You can create custom drivers to send logs to any destination.

<a name="implementing-a-custom-driver"></a>
### Implementing a Custom Driver

Create a class that extends `LoggerDriver` and implements `log()`. The level helpers (`error()`, `info()` and so on) are inherited and call `log()`:

```dart
// lib/app/logging/slack_logger_driver.dart
import 'package:magic/magic.dart';

class SlackLoggerDriver extends LoggerDriver {
  final String webhookUrl;
  final String channel;
  final String minLevel;

  SlackLoggerDriver({
    required this.webhookUrl,
    this.channel = '#alerts',
    this.minLevel = 'error',
  });

  static const _levels = [
    'emergency',
    'alert',
    'critical',
    'error',
    'warning',
    'notice',
    'info',
    'debug',
  ];

  @override
  void log(String level, String message, [dynamic context]) {
    // Only send when the level is at or above minLevel.
    if (_levels.indexOf(level) > _levels.indexOf(minLevel)) return;

    Http.post(webhookUrl, data: {
      'channel': channel,
      'text': '[$level] $message',
      'attachments': context != null ? [{'text': context.toString()}] : null,
    });
  }
}
```

<a name="registering-the-custom-driver"></a>
### Registering the Custom Driver

Register your driver via `LogManager.extend()` in a Service Provider's `register()` phase, not `boot()`. `LogManager` caches the default driver on the first `Log` call that names no channel, a channel whose driver name is not yet registered resolves to `console` at that moment, and `extend()` does not clear the cache. A `Log` call that runs before your `boot()` therefore leaves a default `stack` containing `slack` writing those logs to the console for the rest of the process:

```dart
// lib/app/providers/logging_service_provider.dart
class LoggingServiceProvider extends ServiceProvider {
  LoggingServiceProvider(super.app);

  @override
  void register() {
    LogManager.extend('slack', (config) => SlackLoggerDriver(
      webhookUrl: config['webhook_url'],
      channel: config['channel'] ?? '#alerts',
      minLevel: config['level'] ?? 'error',
    ));
  }
}
```

The factory receives the channel's config map and returns a `LoggerDriver` instance. Then use it in your config:

```dart
'channels': {
  'slack': {
    'driver': 'slack',
    'webhook_url': 'https://hooks.example.com/your-webhook',
    'level': 'error',
  },
}
```

And log to it:

```dart
Log.channel('slack').error('Something went wrong', {
  'user_id': user.id,
});
```

<a name="error-reporting"></a>
## Error Reporting

Sentry error and performance monitoring is not part of core. It ships as the `magic_sentry` plugin:

```bash
flutter pub add magic_sentry
dart run magic:dowel plugin:install magic_sentry
```

See the [installation guide](https://anilcancakir.com/magic_sentry/docs/getting-started/installation) and [HTTP failure reporting](https://anilcancakir.com/magic_sentry/docs/basics/http-reporting).

<a name="testing"></a>
## Testing

Replace the real `LogManager` with `FakeLogManager` during tests using `Log.fake()`. The fake captures all log calls in memory and provides assertion helpers.

```dart
import 'package:magic/testing.dart';

test('logs a payment error', () {
  final fake = Log.fake();

  Log.error('Payment failed', {'amount': 50.00});

  fake.assertLoggedError('Payment failed');
  fake.assertLoggedCount(1);

  Log.unfake();
});
```

The `FakeLogManager` exposes:

| Method | Description |
|--------|-------------|
| `assertLogged(level, message)` | Assert at least one entry matches the given level and message |
| `assertLoggedError(message)` | Shorthand for `assertLogged('error', message)` |
| `assertNothingLogged([level])` | Assert the log is empty, or empty at a specific level |
| `assertLoggedCount(n)` | Assert exactly `n` entries were recorded |
| `reset()` | Clear all captured entries |
| `entries` | Read-only list of all captured `FakeLogEntry` records |

Call `Log.unfake()` at the end of the test (or in `tearDown`) to restore the real binding.

<a name="related-documentation"></a>
## Related Documentation

- [Events](./events.md)
- [Cache](./cache.md)
- [Service Providers](../getting-started/service-providers.md)
- [Testing Facades](../testing/facades.md)

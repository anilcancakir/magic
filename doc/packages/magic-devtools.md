# Magic DevTools

Magic DevTools wires a magic app into the tapir and crumbs dev tools, and is loaded only under `!kReleaseMode` so release builds tree-shake it away entirely.

- [Introduction](#introduction)
- [What tapir and crumbs give you](#what-tapir-and-crumbs-give-you)
    - [Tapir: the E2E driver](#tapir-the-e2e-driver)
    - [Crumbs: the passive runtime inspector](#crumbs-the-passive-runtime-inspector)
- [Installation](#installation)
    - [Why a regular dependency, not a dev dependency](#why-a-regular-dependency-not-a-dev-dependency)
- [Wiring the integrations](#wiring-the-integrations)
    - [The install order](#the-install-order)
    - [Tapir](#tapir)
    - [Crumbs](#crumbs)
    - [Both together](#both-together)
- [The kReleaseMode guard](#the-kreleasemode-guard)
- [What the Magic watchers capture](#what-the-magic-watchers-capture)
    - [Magic watchers](#magic-watchers)
    - [The HTTP adapter](#the-http-adapter)
- [Release builds load nothing](#release-builds-load-nothing)

<a name="introduction"></a>
## Introduction

`magic_devtools` is the adapter layer that connects a magic app to two dev tools, the tapir and crumbs packages: `tapir` (an end-to-end driver for LLM agents and CI) and `crumbs` (a passive runtime inspector). It enriches what those tools observe with Magic-aware context: forms, navigation, controllers, gates, auth, broadcasting, and HTTP.

Magic core has zero dependency on tapir or crumbs. The adapter lives in the separate `magic_devtools` package precisely so the framework carries no dev-tooling production dependency. You opt in by adding `magic_devtools`, and you wire it under `!kReleaseMode` so it never reaches a release build.

This page covers what each tool gives you, how to install `magic_devtools`, the load-bearing install order, the `!kReleaseMode` guard that keeps release builds clean, and what the Magic watchers capture.

<a name="what-tapir-and-crumbs-give-you"></a>
## What tapir and crumbs give you

<a name="tapir-the-e2e-driver"></a>
### Tapir: the E2E driver

`tapir` drives a running Flutter app for LLM agents and CI. It exposes the app's Semantics tree as addressable elements and supports tapping, typing, scrolling, and asserting against them.

`MagicTapirIntegration` registers Magic-aware enrichers into tapir's snapshot pipeline. Each enricher annotates the snapshot with framework context the raw Semantics tree does not carry: the active route, the form field a text input is bound to, server-side validation errors, controller state, the most recent gate result, the active route's middlewares, the authenticated user, and the most recent HTTP, log and exception records (read from crumbs' `CrumbsStore`). An agent reading a snapshot sees your app the way Magic sees it, not just the way the accessibility tree does.

<a name="crumbs-the-passive-runtime-inspector"></a>
### Crumbs: the passive runtime inspector

`crumbs` passively records runtime activity (HTTP requests, logs, exceptions, queries, and framework events) into in-memory ring buffers and serves them to agents. It does not change app behavior; it observes.

`MagicCrumbsIntegration` registers Magic watchers and an HTTP adapter into crumbs. The watchers subscribe to Magic's model, cache, event, gate, and query activity; the adapter feeds Magic's HTTP traffic into crumbs' HTTP buffer. It also assigns tapir's `pendingHttpCountReader`, `recentLogsReader` and `recentExceptionsReader`, so tapir's network-idle wait and its console and exceptions tools read crumbs' buffers. Crumbs is read-only: it captures and surfaces telemetry, it never writes back into your app.

<a name="installation"></a>
## Installation

From a project that already has magic installed, one command adds the three packages and wires `lib/main.dart`:

```bash
dart run magic:dowel magic:install --with-devtools
```

See [Magic CLI](magic-cli.md#install) for exactly what it writes. To add the tooling by hand instead, put `magic_devtools` in your `pubspec.yaml`, plus whichever tooling packages you intend to use:

```yaml
dependencies:
  magic_devtools: ^1.0.0
  tapir: ^1.0.0   # add if you use tapir
  crumbs: ^1.0.0  # add if you use crumbs
```

`magic_devtools` depends on `magic`, `tapir`, and `crumbs` directly, so the tooling packages resolve through `magic_devtools` rather than transitively through `magic` itself.

<a name="why-a-regular-dependency-not-a-dev-dependency"></a>
### Why a regular dependency, not a dev dependency

`magic_devtools` and the tooling packages go under `dependencies`, not `dev_dependencies`. There are two reasons:

1. You import these packages from `lib/main.dart` (under `!kReleaseMode`). Because `lib/` imports them, a `dev_dependencies` entry would trip the `depend_on_referenced_packages` lint. Anything imported from `lib/` must be a regular dependency.
2. The `!kReleaseMode` guard is what keeps these packages out of release builds, not the dependency category. `kReleaseMode` is a compile-time constant; the compiler tree-shakes every `if (!kReleaseMode) { ... }` branch out of a release build, so the imported code is dropped entirely. There is zero production cost even though the package is a regular dependency.

This matches how `tapir` and `crumbs` are installed on their own.

<a name="wiring-the-integrations"></a>
## Wiring the integrations

You wire both integrations in `lib/main.dart`, inside `!kReleaseMode` guards. The wiring splits into two phases around `Magic.init()`, and the order between those phases is load-bearing.

<a name="the-install-order"></a>
### The install order

The plugin installs **before** `Magic.init()`, and the Magic integration installs **after** it:

1. **`TapirPlugin.install()` / `CrumbsPlugin.install()` run BEFORE `Magic.init()`.** This brings the snapshot pipeline (tapir) and the watcher store (crumbs) live during Magic boot, so crumbs' exception watcher catches errors thrown while Magic boots.
2. **`MagicTapirIntegration.install()` / `MagicCrumbsIntegration.install()` run AFTER `Magic.init()`.** The Magic integrations resolve Magic primitives through the IoC container: the tapir enrichers read `Magic.controllers`, `MagicRouter.instance`, `Gate.manager`, and `Auth.user()`; the crumbs adapter resolves the network driver from the container. Those bindings only exist once the service providers have booted, so the integration must run after `Magic.init()` completes.

Calling either `install()` twice in the same isolate is a no-op after the first call; both are idempotent.

<a name="tapir"></a>
### Tapir

```dart
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:magic/magic.dart';
import 'package:magic_devtools/tapir.dart';
import 'package:tapir/tapir.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode) {
    TapirPlugin.install();
  }
  await Magic.init(configFactories: [...]);
  if (!kReleaseMode) {
    MagicTapirIntegration.install();
  }
  runApp(MagicApplication());
}
```

<a name="crumbs"></a>
### Crumbs

```dart
import 'package:crumbs/crumbs.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:magic/magic.dart';
import 'package:magic_devtools/crumbs.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode) {
    CrumbsPlugin.install();
    CrumbsPlugin.registerWatcher(ExceptionWatcher()); // catches boot errors
    CrumbsPlugin.registerWatcher(DumpWatcher());      // captures debugPrint
  }
  await Magic.init(configFactories: [...]);
  if (!kReleaseMode) {
    MagicCrumbsIntegration.install();
  }
  runApp(MagicApplication());
}
```

<a name="both-together"></a>
### Both together

You can wire either integration on its own, or both at once. The rule is the same either way: install each plugin before `Magic.init()`, and each Magic integration after it.

```dart
import 'package:crumbs/crumbs.dart';
import 'package:crumbs/crumbs.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:magic/magic.dart';
import 'package:magic_devtools/crumbs.dart';
import 'package:magic_devtools/magic_devtools.dart';
import 'package:magic_devtools/tapir.dart';
import 'package:tapir/tapir.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode) {
    TapirPlugin.install();
  }
  if (!kReleaseMode) {
    CrumbsPlugin.install();
    CrumbsPlugin.registerWatcher(ExceptionWatcher());
    CrumbsPlugin.registerWatcher(DumpWatcher());
  }
  if (!kReleaseMode) {
    MagicPerfIntegration.install();
  }
  await Magic.init(configFactories: [...]);
  if (!kReleaseMode) {
    MagicCrumbsIntegration.install();
  }
  if (!kReleaseMode) {
    MagicTapirIntegration.install();
  }
  runApp(MagicApplication());
}
```

This is the shape `magic:install --with-devtools` writes, including `MagicPerfIntegration.install()` (the performance data path, installed before `Magic.init()`). The installer decides block by block from call presence: an app already calling `MagicDevtools.installPre(` is left untouched, and a block whose call (`TapirPlugin.install(`, `CrumbsPlugin.install(`, `MagicPerfIntegration.install(`, `MagicTapirIntegration.install(`, `MagicCrumbsIntegration.install(`) is already in `lib/main.dart` is not written again, so a re-run or hand wiring never duplicates a watcher. `tapir:install` and `crumbs:install` skip a block whose `TapirPlugin.install(` or `CrumbsPlugin.install(` call exists, so running them afterwards writes nothing twice.

`MagicDevtools.installPre()` and `MagicDevtools.installPost()` from `package:magic_devtools/magic_devtools.dart` are the alternative: they collapse the blocks above into one call per phase, and `installPre()` also installs the performance data path. It registers the exception and dump watchers once, so a second call adds none. Do not mix the umbrella with the wiring above.

<a name="the-kreleasemode-guard"></a>
## The kReleaseMode guard

Every devtools call sits inside `if (!kReleaseMode) { ... }`. This is the mechanism that keeps release builds clean while debug and profile builds carry the tools.

`kReleaseMode` is a compile-time constant from `package:flutter/foundation.dart`: it is `true` only in release builds. Because the value is known at compile time, the compiler eliminates the entire `if (!kReleaseMode)` branch from a release build. The calls to `TapirPlugin.install()`, `MagicTapirIntegration.install()`, and their crumbs counterparts are dropped, and with them the imported `magic_devtools`, `tapir`, and `crumbs` code is tree-shaken out.

Because the guard is `!kReleaseMode`, a profile build keeps the tools, which a performance measurement needs: run the measurement on a profile build.

The guard is what makes the regular-dependency choice safe: the package ships in your dependency graph for resolution, but none of its code survives into a release build.

<a name="what-the-magic-watchers-capture"></a>
## What the Magic watchers capture

`MagicCrumbsIntegration.install()` registers five watchers and one HTTP adapter into crumbs.

<a name="magic-watchers"></a>
### Magic watchers

| Watcher | Captures |
|---------|----------|
| `MagicModelWatcher` | Model lifecycle events: `ModelCreated`, `ModelSaved`, `ModelDeleted`. |
| `MagicCacheWatcher` | Cache activity: `CacheHit`, `CacheMiss`, `CachePut`, `CacheForget` and `CacheFlush`. |
| `MagicEventWatcher` | The curated set of magic auth, database, and gate-definition events. |
| `MagicGateWatcher` | Authorization checks via `GateAccessChecked` (ability, result, user). |
| `MagicQueryWatcher` | Database queries run through Magic's ORM (the `QueryExecuted` event). |

Each watcher is read-only: it subscribes to Magic activity and records it into crumbs' store. None of them writes back into your app.

<a name="the-http-adapter"></a>
### The HTTP adapter

`MagicHttpFacadeAdapter` wraps Magic's network driver with an interceptor that feeds every HTTP request and response into crumbs' HTTP buffer. The adapter resolves the network driver from the IoC container, which is why `MagicCrumbsIntegration.install()` must run after `Magic.init()`.

<a name="release-builds-load-nothing"></a>
## Release builds load nothing

There is no production load path. The integrations are reachable only through `if (!kReleaseMode)` branches in `main()`, and the compiler strips those branches from release builds. A release build loads none of `magic_devtools`, tapir, or crumbs: zero enrichers, zero watchers, zero adapters, zero runtime cost. The package is a regular dependency for resolution and lint correctness only; its code never runs in production.

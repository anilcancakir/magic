# Installing a plugin

What is the same for every official plugin: the install steps, provider order and the devtools wiring. What a plugin does, and how to use it, is in that plugin's own skill (the table in `SKILL.md` section 10 names it).

## Contents

- [The five install steps](#the-five-install-steps)
- [Provider order](#provider-order)
- [Devtools](#devtools)

## The five install steps

Run them from the app root, in this order. `dart run magic:dowel <cmd>` delegates to the app's own `bin/dispatcher.dart` when there is one, which is what makes a plugin's commands reachable.

1. `flutter pub add <package>`.
2. `dart run magic:dowel plugin:install <package>`. It registers the plugin's `DowelServiceProvider` in `.dowel/plugins.json` and regenerates `lib/app/_plugins.g.dart`, which makes the plugin's own commands dispatchable. Skip it and step 3 reports an unknown command.
3. `dart run magic:dowel <plugin>:install` (`deeplink:install`, `notifications:install`, `starter:install`, `social:install`, and so on). This is the manifest install: it publishes the config file, injects the service provider into `lib/config/app.dart` and adds the config factory to `lib/main.dart`. A plugin whose `install.yaml` declares a `bootstrap_command` (`magic_starter` does) has this chained for you by step 2; run it by hand when that subprocess reports a failure.
4. `dart run magic:dowel <plugin>:doctor` where the plugin ships one. It is the only step that tells you the install took; `dart run magic:dowel list` showing the plugin's commands is the fallback check.
5. Whatever the manifest cannot do, which the plugin's own skill or installation page names. This is where the real failures live: `magic_deeplink` needs the iOS associated-domains entitlement and an Android `autoVerify` intent filter, and a plugin installed without them compiles and never fires.

## Provider order

Order in `lib/config/app.dart` is free for BINDINGS and load-bearing for everything else. Every `register()` runs before any `boot()` (`lib/src/foundation/application.dart`), so a plugin that resolves another plugin's binding in `boot()` finds it whichever order they sit in. But `boot()` is a sequential await over the list, so anything a provider DOES in `boot()` is invisible to a provider that booted before it, and the failure is silent both ways:

- A same-key overwrite, where the later-booting provider's `Gate.define()` or config value wins.
- A publish nobody is subscribed to yet. A provider that publishes from its `boot()` (a cold-start push tap, for example) reaches only the providers that already subscribed; the event goes into a broadcast stream with no listener and is dropped. Neither order errors, and dowel's installer appends each provider to the END of the list, so install order decides which one an app gets.
- `AppServiceProvider` before `AuthServiceProvider`, so `setUserFactory` lands before auth restore runs.

When a provider's `boot()` has to observe what another provider's `boot()` did, order them; do not assume. A plugin may buffer such an event itself (the notifications and deep link plugins do for the cold-start tap), which closes that one case but not the shape.

## Devtools

`magic_devtools` is a regular dependency loaded under `!kReleaseMode`, so it tree-shakes out of release builds (debug and profile builds keep it). It has no skill yet; its page is `https://anilcancakir.com/magic/docs/packages/magic-devtools`. Two calls straddle the bootstrap: `MagicDevtools.installPre()` before `Magic.init()` boots the tapir and crumbs plugins and crumbs' `ExceptionWatcher` and `DumpWatcher`; `MagicDevtools.installPost()` after it wires `MagicCrumbsIntegration` and `MagicTapirIntegration`, which resolve through the container. Keep `!kReleaseMode` at the call site, never inside the methods, or the release tree-shake breaks.

`dart run magic:dowel magic:install --with-devtools` wires the same pieces in one step, including `MagicPerfIntegration.install()` rather than the `MagicDevtools` umbrella (do not mix the two), and never writes a call twice. Use it to drive and inspect a running app while verifying your work.

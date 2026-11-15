# Magic Example

In-repo smoke reference for the `magic` framework. Deliberately minimal: a handful of Dart files, declaring only `magic` (pinned to a local path, `magic: {path: ..}`), `dowel`, `material_ui` and Flutter's `cupertino_icons`, runs in magic's CI on every push, and regenerated per release. This is what pub.dev shows on the `magic` package example tab.

This example is NOT a starting point for a real product. A real app starts from `flutter create`, adds `magic` and runs `dart run magic:dowel magic:install`, then adds `magic_starter` (auth, teams, profile, billing) and the plugins it needs (magic_notifications, magic_deeplink, magic_social_auth, magic_devtools) as hosted dependencies, each with its own installer.

This example cannot take those plugins itself: pub refuses to unify a path dependency (`magic: {path: ..}` here) with hosted dependencies (like `magic_notifications: ^1.0.0`) in the same resolution graph. This is a hard technical constraint, not a choice.

## Stack

- Flutter >=3.47.0, Dart >=3.13.0
- `magic` (path dependency to the parent framework)
- Declares only `magic`, `dowel`, `material_ui` and `cupertino_icons`. Note
  that `magic` itself pulls a small number of plugins transitively (for
  example `flutter_timezone` for IANA timezone detection), so the built app is
  not plugin-free; what is minimal here is what this example declares.

## Getting started

The code here demonstrates basic magic patterns: IoC container setup in `lib/app/kernel.dart` (mostly commented out for clarity), routing in `lib/routes/app.dart`, and service provider registration. This is NOT a complete app; it is a minimal smoke test to verify the framework compiles and boots.

If you are starting a new app, follow the steps above instead. If you want to understand how magic works at the simplest level, read the source here.

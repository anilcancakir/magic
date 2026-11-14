# Security Policy

## Supported Versions

Only the latest published version receives fixes.

## Reporting a Vulnerability

Report it through GitHub's private vulnerability reporting:
**[Open a private vulnerability report](https://github.com/anilcancakir/magic/security/advisories/new)**

The report stays confidential until a fix is ready. Include the affected version, the platform, and the steps to reproduce.

## Scope

This policy covers the `magic` package: the service container, the facades (`Auth`, `Http`, `Vault`, `Storage`, `Cache` and the rest), the guards, the router and middleware, and the `dart run magic:dowel` commands with the files `magic:install` and the `make:*` generators write into an app. Issues in `wind_kit`, `dowel`, the plugin packages (`magic_encryption`, `magic_local_storage`, `magic_picker`, `magic_socket` and the other `magic_*` packages), the Flutter SDK and third-party dependencies belong to their maintainers.

Magic runs on the client. `Gate` and policies decide what an app shows, not what a user may do, so the backend must authorise every request on its own. A report that depends on a client-side check standing in for server-side authorisation describes that boundary, not a vulnerability; one that shows a secret read from `Vault`, a token sent to the wrong host or a guard that fails open is in scope.

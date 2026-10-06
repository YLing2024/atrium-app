[English](README.en.md) | [简体中文](README.md)

# atrium-app

The Android client (Flutter) for the personal site admin, the mobile counterpart of `atrium-console`.

## What it does

Nine pages in a navigation drawer, in the same order as the web version:

- **System**: real-time readings and history trends for CPU / memory / disk / network; trends switch between second / minute / hour / day granularity.
- **Version**: software version list, loaded once when the page is entered.
- **Blog**: post and collection management in two views, Markdown editing and preview, image insertion, draft auto-save.
- **Manage**: login device sessions, API tokens (plaintext shown only once at creation), reset authenticator.
- **Terminal**: a WebView embedding ttyd, with multiple tabs; beyond the site login, a separate terminal password is verified and the ticket is kept in memory only.
- **Files**: directory browsing, upload (with progress), rename, delete, download and time-limited temporary links.
- **Notifications**: notification center; a foreground service works with system local notifications so a new notification triggers an alert.
- **Debug**: API calls and the status code and response body of the most recent request.
- **Hermes**: embedded console, with the address injected at build time.

There is also a command palette (quick page switch, reset authenticator, log out); light/dark follows the system and can be toggled manually, using the same Swiss palette as the web version.

## Quick start

```bash
flutter pub get
flutter run    # on a device or emulator; private addresses must be injected at build time, see below
```

## Configuration

Private addresses are always injected at build time (`String.fromEnvironment`); the source contains only `example.com` placeholder domains:

| Name | Default | Description |
|---|---|---|
| `API_BASE` | `https://api.example.com` | Admin API base URL |
| `AUTH_BASE` | `https://auth.example.com` | Auth center base URL (sso mode) |
| `HERMES_URL` | `https://hermes.example.com` | Embedded address for the sidebar Hermes page |
| `OAUTH_CLIENT_ID` | `home-admin` | OAuth2 public client id, usually no need to override |

Without injection the app connects to the placeholder domains and cannot work.

## Build and artifact

```bash
flutter build apk --release \
  --dart-define=API_BASE=https://api.example.com \
  --dart-define=AUTH_BASE=https://auth.example.com \
  --dart-define=HERMES_URL=https://hermes.example.com
```

Artifact: `build/app/outputs/flutter-apk/app-release.apk`. Distributed self-signed, not through an app store.

When build-machine memory is tight the Gradle daemon can OOM easily; after the build you can reclaim the persistent memory with `pkill -f "[G]radleDaemon"`.

## Development self-check

```bash
flutter pub get
flutter analyze
flutter test
```

## Authentication and security

The login method follows the server's `AUTH_MODE`; the app needs no extra switch. At startup it probes `GET /api/admin/auth-mode`, and **a failed probe is always treated as sso**.

- **builtin (default)**: 6-digit code login `POST /api/admin/login`; tokens are valid for 12 hours with no refresh, and expiry returns to the login page; logout goes through `POST /api/admin/logout`. If the first login returns `totp_setup_required`, the user is guided to `GET /api/admin/totp/setup` to bind an authenticator.
- **sso**: standard OAuth2 PKCE (public client, no client_secret, S256). The auth center `/authorize` is opened in the system browser, and the app starts a temporary server listening only on `127.0.0.1:53682` to receive the callback and validate `state`. The port is fixed because the redirect_uri must match the registered client value exactly and custom schemes are not supported.

Tokens are stored in system secure storage (Android Keystore); `shared_preferences` holds only non-sensitive UI state such as the theme.
Business requests all carry `Authorization: Bearer`; on a 401 they silently renew with the `refresh_token` and retry once, and only a failure returns to the login page. The auth center's refresh_token is single-use and may only be renewed by the main isolate; the foreground-service isolate reports a 401 and lets the main isolate renew and then restart the service.

On the startup path nothing is awaited before `runApp`: secure storage, tokens, theme and the notification service are all initialized asynchronously after `runApp`, each with its own try/catch and timeout, so failures only degrade. When secure storage is unavailable the session runs in memory, and the UI clearly states "this login will not be saved persistently".

## License

MIT

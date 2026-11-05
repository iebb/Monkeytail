<p align="center"><img src="docs/brand/monkeytail-banner.png" alt="Monkeytail" width="880"></p>

**English** · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [简体中文](README.zh-Hans.md)

# Monkeytail

**A native API client for iPhone, iPad, Mac and Apple Vision Pro. Bring your Postman and Insomnia collections, keep your scripts, and skip the sign-in.**

Monkeytail opens the collections you already have and runs them the same way. There is no Monkeytail account, no login wall, no cloud workspace and no telemetry. Requests go straight to your servers, and your data stays on your devices or in your own iCloud Drive.

<p><img src="docs/screenshots/iphone-request.png" alt="Request editor on iPhone" width="285"> <img src="docs/screenshots/iphone-response.png" alt="JSON response on iPhone" width="285"></p>

## Download

**[Download on the App Store](https://apps.apple.com/app/id6814706725)**: free, with no in-app purchases, for iPhone, iPad, Mac and Apple Vision Pro. Website: [monk.ieb.app](https://monk.ieb.app)

## Switching from Postman or Insomnia

- **Import everything.** Postman collections (v1, v2, v2.1), environments, globals and full data dumps; Insomnia v4 and v5 exports; plus Bruno, Hoppscotch, Thunder Client, HAR, `.http` files, OpenAPI/Swagger and cURL. Pick several files or a whole folder at once.
- **Or pull straight from the cloud.** Sign in to Postman, Insomnia or Hoppscotch once to pull your synced workspaces, or point Monkeytail at a GitHub repository. The session is used only for that import and is never saved.
- **Your scripts keep working.** Pre-request and test scripts run with a Postman-compatible `pm` API, including `pm.test`, `pm.expect`, `pm.sendRequest`, CryptoJS, lodash and moment. Scripts from Insomnia, Bruno and other clients run through compatibility objects.
- **The same mental model.** Workspaces, collections and nested folders with inherited auth, headers, variables and scripts; environments, globals and `{{variables}}`, including dynamic ones such as `{{$guid}}`.
- **Export back any time.** Postman v2.1, Insomnia v4, or a full-fidelity Monkeytail JSON file.

## What else it does

- HTTP, GraphQL with introspection, WebSocket and server-sent events
- OAuth 2.0 with PKCE, OAuth 1.0, JWT, AWS Signature V4, Digest, API keys, Basic and Bearer
- A collection runner with iterations and CSV/JSON data files, exporting JSON or JUnit reports
- Visual assertions, saved examples, offline mocks and a local mock server
- A response viewer with pretty JSON, a tree, search, comparison, images, audio, video and hex
- Code generation in 13 languages, and cURL import and export
- Timing breakdowns, TLS details, HTTP/HTTPS/SOCKS5 proxies, client certificates and optional browser TLS profiles
- Themes, custom colours and fonts, in English, Spanish, French, Japanese, Korean and Simplified Chinese
- Sync through your own iCloud Drive, and an Apple Watch companion for favourite requests

More detail: [API tools](docs/APITools.md) · [Scripting](docs/Scripting.md) · [Browser profiles](docs/BrowserProfiles.md) · [Example workspaces](docs/examples)

## Build

Open `Monkeytail.xcodeproj` in Xcode and run the **Monkeytail** (iPhone and iPad), **MonkeytailMac** or **MonkeytailVision** scheme. Requires iOS 17, macOS 14 or visionOS 1. After editing `project.yml`, run `xcodegen generate`.

## Test

```sh
swift test
```

## License

[BSD 3-Clause](LICENSE)

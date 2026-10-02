<p align="center"><img src="docs/brand/monkeytail-banner.png" alt="Monkeytail — HTTP and cURL for iPhone, iPad, and Mac by Kitta Co" width="880"></p>

# Monkeytail

**A native request debugger for iPhone, iPad, and Mac.** Import a command, edit your request, and inspect the response. Built in SwiftUI with a compact iPhone editor and an adaptive desktop workspace.

Free. No in-app purchases. No account. No data collected by Kitta Co.

[Product](https://docs.kitta.co/monkeytail/) · [Privacy](https://docs.kitta.co/monkeytail/privacy/) · [Support](https://docs.kitta.co/monkeytail/support/) · [API tools](docs/APITools.md) · [Scripting](docs/Scripting.md) · [Browser profiles](docs/BrowserProfiles.md) · [Release setup](docs/XcodeCloud.md)

<p><img src="docs/screenshots/iphone-request.png" alt="Monkeytail iPhone request editor with inline headers" width="285"> <img src="docs/screenshots/iphone-response.png" alt="Monkeytail JSON response viewer on iPhone" width="285"></p>

See [verification results and device screenshots](docs/Verification.md). Importable [example workspaces](docs/examples) are included for Monkeytail, Postman, and Insomnia.

## Run

Open **`Monkeytail.xcodeproj`**. Select **Monkeytail** for iPhone/iPad or **MonkeytailMac** for the native macOS app, then Run. Requires iOS 17 or macOS 14; client certificate import on Mac requires macOS 15. Builds and verification use Xcode 27. Choose your signing team for physical devices and iCloud-enabled Mac builds. Mac Debug builds use separate sandbox entitlements for ad-hoc local testing; Release enables the shared iCloud container.

The generated Xcode project is checked in. If you change target settings in `project.yml`, regenerate it with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
```

The starter collection uses httpbin.org. Requests are only sent when you tap **Send** or use the Send keyboard shortcut. Replace `base_url` in the Playground environment to use your own server.

## Included

- Native request editor: methods, URL, enabled/disabled headers and query parameters, JSON/text/URL-encoded/multipart bodies and binary file uploads, inherited authentication, bearer/basic, API keys, OAuth 2.0 with PKCE and refresh, AWS SigV4, timeout, redirects.
- cURL import and export, including shell quoting, multiline commands, data, JSON, cookies, basic auth, and proxy selection. The importer parses text; it never invokes a shell.
- Collections and nested folders with inherited headers, authentication, variables, and scripts; add, rename, duplicate, delete, search, and automatic local persistence. Optional iCloud Drive sync uses the device’s existing session; no Monkeytail account.
- Named environments and `{{variable}}` substitution throughout requests; nested variables with missing-variable and cycle detection.
- Real HTTP transport, cancellation, response sharing, and per-hop DNS/connect/TLS/upload/server/download diagnostics with transport-reported headers and bounded sent bodies.
- Optional [browser TLS and HTTP/2 profiles](docs/BrowserProfiles.md) for Chrome, Firefox, and Safari, including iOS and Android presets. Runs locally using pinned curl-impersonate; certificate verification stays enabled.
- JSON pretty printing, minification in the core library, syntax colors, expandable tree, line search, copying, and request-body formatting.
- MIME-aware image previews with pinch zoom, native audio/video playback, and offset/ASCII Hex and Binary viewers. Unsupported media can be inspected as bytes or saved.
- Local JavaScript before-request and after-response hooks, console logs, assertions, tests, and environment updates.
- System networking or custom HTTP CONNECT, TLS-wrapped HTTPS CONNECT, and SOCKS5 proxies, with optional credentials and no direct fallback when a custom proxy fails.
- OpenAPI/Swagger JSON and YAML import with parameter hints, examples, and portable JSON Schema validation.
- GraphQL query/variables/operation editing, introspection, and searchable schema field suggestions.
- WebSocket and SSE timelines with text/JSON/binary inspection, filters, ping, cancellation, and reconnect.
- Device-local cookie jars per environment and exact-host PKCS#12 client identities. System transport diagnostics show certificate chain, validity, negotiated TLS/cipher identifiers, and protocol.
- Visual status/time/header/JSONPath/schema assertions, pass/fail results, and editable JavaScript checks.
- Swift URLSession, JavaScript fetch, Python requests, and Kotlin OkHttp code export with credential hiding enabled by default.
- Offline response mocks from current responses or snapshots, delays/status/errors, and a foreground loopback mock server.
- Postman v2/v2.1 collection and environment JSON import; Postman v2.1 collection export.
- Insomnia v4 JSON import/export. Current Insomnia can import this legacy format.
- Full-fidelity Monkeytail workspace JSON import/export, Files integration, and a system share sheet.
- Saved response snapshots with search, JSON/status/header comparison, and JSONPath extraction (`$`, keys, indices, wildcards). Snapshots remain local and retain at most 50 entries within 60 MB.
- Last 50 request definitions in history with status and timing; restore without automatically resending.
- Light/dark appearances, Dynamic Type, VoiceOver labels, hardware keyboard Send shortcut (⌘↵), and adaptive portrait/landscape layouts.

## Device layouts

The iPhone layout keeps the method and URL visible above a compact editor. **Send/Cancel** and **Request/Response** stay at the bottom, within thumb reach, and move above the keyboard while editing. Header and parameter names and values share one row with 44-point controls. Response tabs collapse while typing a search on a phone so matching lines stay visible above the keyboard. Optional help is collapsed, and request names can be edited directly in the navigation bar. cURL sharing is under the actions menu.

Layout follows the **available window size**:

| Available space | Layout |
| --- | --- |
| Narrow phone / folded window | Bottom Request/Response switch; collections via the back/sidebar button |
| Detail area at least 640 × 440 points | Request and response side by side |
| Short landscape phone window | Single pane to keep the editor usable |
| Window at least 1,100 points | Collections sidebar plus request and response panels |
| Accessibility text sizes | Single-pane editor to preserve readable text |

Selection and editor state survive width changes, rotation, iPad window resizing, and foldable size changes. iPhone Duo is tested in its installed simulator configuration; the layout makes no assumption about an undocumented hinge position or APIs for independent physical displays.

## Interchange scope

Monkeytail workspace JSON preserves all model fields, environments, and proxy settings. Imports append collections and environments and generate fresh IDs; native imports also apply their saved proxy settings. Scripts are disabled on every import until reviewed and enabled.

Postman export preserves nested folders and exports the **active environment** as collection variables. Postman imports preserve folder hierarchy and inherited headers, authentication, variables, and scripts. Raw, URL-encoded, multipart, file, and GraphQL JSON bodies are supported. Scripts are preserved; execution supports the APIs documented in [Scripting](docs/Scripting.md).

Insomnia supports the v4 JSON resource format and normalizes `{{ _.variable }}` references. Environments are imported as named flat dictionaries. Nested environment inheritance and dynamic template tags are not emulated. YAML/v5 workspaces should be converted to a supported JSON format in the source tool.

Third-party formats do not preserve every Monkeytail setting, such as request timeouts or global proxy selection. Unsupported authentication produces an import notice; unsupported cURL flags produce an explicit error. Imported file paths are metadata only: choose each file using Files or Photos before sending. Native workspace exports include file bytes; Postman/Insomnia/cURL exports reference filenames. Use Body → Export file to transfer the actual attachments alongside third-party exports. gRPC, collection runners, shared team accounts, and the complete Postman/Insomnia scripting runtimes are outside this version. OpenAPI import and JSON Schema validation have explicit supported subsets; see [API tools](docs/APITools.md).

Browser profiles round-trip through native JSON and `curl-impersonate --impersonate` commands. Postman and Insomnia exports carry `_monkeytail` metadata for reimport into Monkeytail; those apps do not apply browser profiles themselves.

## Data and networking

Workspace and history live in the app's Application Support directory and use platform file protection and the Mac app sandbox. Workspace credentials use a device-only, non-synchronizing Keychain entry; exports include saved values. There is no analytics or Kitta-operated backend. Optional iCloud Drive sync shares collections, environments, and scripts between your devices, merging each entity by its latest edit and retaining delete tombstones. Edits to different requests survive concurrent changes; the latest edit wins for the same entity. A protected local recovery copy is retained before applying remote changes. The app stays usable offline and sync checks while active and on foregrounding. Bearer/basic/proxy/API-key/OAuth/AWS credentials, cookie jars, client identities, inferred or marked secret fields, attachments, snapshots, and request history are excluded from sync. Fields can be marked local using their lock/options menu. Check bodies and scripts for embedded secrets before enabling sync. Imported/synced scripts require a per-device opt-in. Switching the device's iCloud session requires toggling sync off and on. Response bodies stay in memory until explicitly saved as snapshots or exported; audio/video previews use protected temporary files that are removed when their cached response is released. Files left by an interrupted session are cleaned on launch after one day. Saving explicitly exports the original bytes. Cookies are opt-in per request, with separate device-local jars for each environment. Sessions never use Safari cookies. OAuth opens the provider in an ephemeral browser session; it does not create a Monkeytail account. Client identities are stored only in the device-local Keychain. The mock server binds only to 127.0.0.1 and stops when the app enters the background. TLS trust verification stays enabled; install and trust a debugging CA in iOS Settings when required. ATS permits HTTP because this app is a general API/debugging client.

Responses are bounded at 20 MB; text/tree and byte previews are bounded at 1 MB. Images decode to a maximum 2,048-pixel preview; saving retains the original. Audio/video playback uses only the downloaded file, with external media references disabled. JSON formatting, tree preparation, and line splitting run off the main thread. Text and tree rows render lazily, line arrays are reused during search, and syntax highlighting uses one compiled expression with a length cap for long lines. The response cache retains up to 8 responses within 40 MB. Imports are bounded at 40 MB; uploads at 20 MB; iCloud metadata at 20 MB. JSONPath and JSON diffs operate on bodies up to 2 MB with node/change limits. JavaScript contexts have a three-second deadline, use an ephemeral WebKit data store, block network/DOM navigation, and expose no native file or app bridge. A timed-out context is discarded. Scripts are a convenience API, not a general Node.js runtime.

## Verification

Pure model, parser, collection, encoding, JSON, and proxy-configuration, multipart, sync merge/tombstone/secret, JSONPath, and response comparison tests:

```sh
swift test
```

Simulator integration and UI tests use local HTTP, TLS/HTTP2, CONNECT, and SOCKS5 fixtures, with no public API dependencies:

```sh
./Scripts/test.sh 'platform=iOS Simulator,name=iPhone Duo'
# Or pass another installed simulator destination, e.g.:
./Scripts/test.sh 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0'
```

The suite verifies transport, TLS ClientHello and HTTP/2 SETTINGS on the wire, certificate rejection, browser header overrides, redirects, credential removal across origins, cancellation, limits, both proxy protocols, script mutation/assertions/errors/timeouts/network blocking, Keychain persistence, snapshot eviction, multipart/binary uploads on both transports, per-hop diagnostics, and a send → inspect → import → edit → cURL export UI flow in portrait and landscape. UI tests use an isolated temporary workspace and do not change normal user collections.

## Project structure

```text
Sources/MonkeytailCore/  Codable models, request builder, HTTP transport, cURL,
                        collection codecs, JSON formatting/tree
Sources/MonkeytailCurl/  Small C bridge for the static browser transport
Vendor/                 Pinned curl-impersonate XCFramework and provenance
Monkeytail/Services/    Observable workspace/persistence and WebKit script runner
Monkeytail/Views/       Native adaptive SwiftUI interface
Tests/                 Core Swift package tests
MonkeytailMac/         Mac sandbox/iCloud entitlements and app metadata
MonkeytailMacTests/    Shared advanced hosted integration tests
MonkeytailTests/       Hosted simulator integration tests
MonkeytailUITests/     End-to-end device UI tests
Scripts/               Local verification, samples, icon packaging
ci_scripts/            Xcode Cloud hooks and local network fixtures
docs/                  Scripting, release metadata, branding, screenshots
```

Protocol references: [Apple proxy configuration](https://developer.apple.com/documentation/network/proxyconfiguration), [WebKit JavaScript execution](https://developer.apple.com/documentation/webkit/wkwebview/callasyncjavascript(_:arguments:in:in:completionhandler:)), [Postman schema](https://schema.postman.com/), [Insomnia import/export](https://developer.konghq.com/insomnia/import-export/).

## Ownership

Private source repository for Kitta Co (Kitta Ltd). Copyright © 2026 Kitta Ltd. All rights reserved. The public product, support, and privacy pages are hosted at [docs.kitta.co](https://docs.kitta.co/monkeytail/).

Third-party library notices are included in Settings → Open source licenses. See [vendor provenance](Vendor/README.md) for the pinned binaries and regeneration procedure.

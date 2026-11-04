<p align="center"><img src="docs/brand/monkeytail-banner.png" alt="Monkeytail — HTTP and cURL for iPhone, iPad, and Mac by Kitta Co" width="880"></p>

# Monkeytail

**A native request debugger for iPhone, iPad, Mac, and visionOS, with a compact Apple Watch companion.** Import a command, edit your request, and inspect the response. Built in SwiftUI with a compact iPhone editor and an adaptive desktop workspace.

Free. No in-app purchases. No account. No data collected by Kitta Co.

[Product](https://docs.kitta.co/monkeytail/) · [Privacy](https://docs.kitta.co/monkeytail/privacy/) · [Support](https://docs.kitta.co/monkeytail/support/) · [API tools](docs/APITools.md) · [Scripting](docs/Scripting.md) · [Browser profiles](docs/BrowserProfiles.md) · [Release setup](docs/Release.md)

<p><img src="docs/screenshots/iphone-request.png" alt="Monkeytail iPhone request editor with inline headers" width="285"> <img src="docs/screenshots/iphone-response.png" alt="Monkeytail JSON response viewer on iPhone" width="285"></p>

See [verification results and device screenshots](docs/Verification.md). Importable [example workspaces](docs/examples) are included for Monkeytail, Postman, and Insomnia.

## Run

Open **`Monkeytail.xcodeproj`**. Select **Monkeytail** for iPhone/iPad, **MonkeytailMac** for Mac, **MonkeytailVision** for visionOS, or **MonkeytailWatch** for the Watch companion. Requires iOS 17, macOS 14, visionOS 1, or watchOS 10; client certificate import on Mac requires macOS 15. Builds and verification use Xcode 27. Choose your signing team for physical devices and iCloud-enabled Mac builds. Mac Debug builds use separate sandbox entitlements for ad-hoc local testing; Release enables the shared iCloud container.

The generated Xcode project is checked in. If you change target settings in `project.yml`, regenerate it with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
```

The starter collection uses httpbin.org. Requests are only sent when you tap **Send** or use the Send keyboard shortcut. Replace `base_url` in the Playground environment to use your own server.

## Included

- Native request editor: methods, URL, `:name` path variables, enabled/disabled headers and query parameters with Postman-style bulk edit, JSON/text/URL-encoded/multipart bodies and binary file uploads, inherited authentication, bearer/basic/Digest, API keys, OAuth 1.0 signing, JWT Bearer (HS/RS/PS/ES 256–512, signed locally on every send, in a header or query parameter), OAuth 2.0 with PKCE and refresh, AWS SigV4, timeout, redirects.
- cURL import and export, including shell quoting, multiline commands, data, JSON, cookies, basic and `--digest` auth, and proxy selection. The importer parses text; it never invokes a shell.
- Collections and nested folders with inherited headers, authentication, variables, and scripts; add, rename, duplicate, delete, search, and automatic local persistence. Optional iCloud Drive sync uses the device’s existing session; no Monkeytail account.
- Named environments, workspace globals, and `{{variable}}` substitution throughout requests; nested variables with missing-variable and cycle detection, plus Postman dynamic variables such as `{{$guid}}`, `{{$timestamp}}`, and `{{$randomEmail}}`. Resolved values appear under the URL, and typing `{{` suggests variables.
- Collection and folder runner: iterations, delay, CSV/JSON data files, `pm.execution.setNextRequest`/`skipRequest`, live pass/fail results, and JSON or JUnit report export. Runs locally; no account or cloud runner.
- Real HTTP transport, cancellation, response sharing, and per-hop DNS/connect/TLS/upload/server/download diagnostics with transport-reported headers and bounded sent bodies.
- Optional [browser TLS and HTTP/2 profiles](docs/BrowserProfiles.md) for Chrome, Firefox, and Safari, including iOS and Android presets on iOS and Mac. visionOS uses System TLS; the pinned browser library has no visionOS slice. Runs locally using pinned curl-impersonate; certificate verification stays enabled.
- JSON pretty printing, minification in the core library, syntax colors, expandable tree, line search, copying, and request-body formatting.
- MIME-aware image previews with pinch zoom, native audio/video playback, and offset/ASCII Hex and Binary viewers. Unsupported media can be inspected as bytes or saved.
- Local JavaScript before-request and after-response hooks with a Postman-compatible `pm` subset: Chai-style `pm.expect`, `pm.response.to.*`, `pm.sendRequest`, environment/collection/global variables, cookies, built-in CryptoJS, lodash and moment subsets, and console logs. Scripts run on every send, including imported ones.
- System networking or custom HTTP CONNECT, TLS-wrapped HTTPS CONNECT, and SOCKS5 proxies, with optional credentials and no direct fallback when a custom proxy fails.
- OpenAPI/Swagger JSON and YAML import with parameter hints, examples, and portable JSON Schema validation.
- GraphQL query/variables/operation editing, introspection, and searchable schema field suggestions.
- WebSocket and SSE timelines with text/JSON/binary inspection, filters, ping, cancellation, and reconnect.
- Device-local cookie jars per environment, exact-host PKCS#12 client identities, and per-host trust for self-signed certificates (pinned by SHA-256 fingerprint instead of turning verification off). System transport diagnostics show certificate chain, validity, negotiated TLS/cipher identifiers, and protocol.
- Visual status/time/header/JSONPath/schema assertions, pass/fail results, and editable JavaScript checks.
- Code snippets for cURL, JavaScript fetch, Node.js axios, Python requests, Go, Java HttpClient, C# HttpClient, PHP cURL, Ruby Net::HTTP, Swift URLSession, Kotlin OkHttp, HTTPie, and PowerShell, with optional credential hiding.
- Saved response examples per request (Postman `response` examples), offline response mocks from examples, current responses or snapshots, delays/status/errors, and a foreground loopback mock server.
- Request tabs on Mac and iPad, restored on relaunch, Markdown documentation for requests, folders, and collections, and a sandboxed HTML response preview.
- Import from Postman (v1, v2/v2.1 collections, environments, globals, and full data dumps), Insomnia (v4 JSON/YAML and v5 YAML), Bruno (`.bru` folders and JSON exports), Hoppscotch, Thunder Client, HAR, VS Code REST Client/JetBrains `.http` files, OpenAPI, and cURL. Pick several files or a whole folder at once.
- **Evil Monk** importer: connect Postman (API key), a GitHub repository, or Hoppscotch (personal access token) and pull every collection, environment and global straight into Monkeytail. The token is used only for that import and never saved; Monkeytail still has no account.
- Postman v2.1 collection export and Insomnia v4 JSON export. Current Insomnia can import this legacy format.
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
| iPad detail area at least 640 × 440 points | Request and response side by side |
| Short landscape phone window | Single pane to keep the editor usable |
| Window at least 1,100 points | Collections sidebar plus request and response panels |
| Foldable half-open, fold across the screen (tabletop) | Response above the hinge; URL, Send, and request editor below it. Nothing crosses the fold |
| Accessibility text sizes | Single-pane editor to preserve readable text |

Selection and editor state survive width changes, rotation, iPad window resizing, and foldable size changes. On iOS 27.1 and later the tabletop layout follows `UIHingeInteraction` (partially open) and the system's `.division` reserved region, so the split sits exactly on the reported fold with 7 points of clearance on each side. If the hinge is flat or closed, or the fold isn't horizontal, the regular layouts apply.

## Apple Watch companion

Star a request in the actions menu on iPhone. Open **Apple Watch**, tap a favourite to copy it, then tap **Sync** when the paired app is installed. The Watch lists up to ten copies: open one and tap **Send** or **Cancel**, then inspect status, time, headers, or Pretty/Raw/Hex text. There is no request editor or automatic polling on Watch.

The selected environment and inherited headers/auth are resolved when copied. **Include credentials & body** is a saved option. New workspaces include them; existing preferences are preserved. Copies use local files by default, optional Keychain storage, and WatchConnectivity's latest application context. Editing a request or changing environments requires copying it again; Sync removes copies that are no longer favourites. The Watch makes its own HTTP request, so the server must be reachable from Watch. Responses stay in memory. Transfer between physical paired devices still needs hardware verification.

Watch supports System HTTP/GraphQL, verified HTTPS, and manual basic/bearer/API-key headers. Proxies, browser TLS presets, client identities, cookies, OAuth/JWT/AWS, scripts, mocks, WebSocket, and SSE remain in the full app. Unsupported configurations produce an error before copying. Timeout is at most 30 seconds, a copied body at most 32 KB, the transfer at most 60 KB, a response at most 256 KB, and a displayed body at most 16 KB.

The visionOS window shares the full workspace editor, response viewers, API tools, and optional iCloud container with iPhone and Mac. Select System TLS on visionOS; browser TLS presets are unavailable there. The system-only and Watch Swift packages link canonical sources through checked-in symlinks, avoiding the iOS/Mac curl binary on unsupported platforms.

Version 1.4 is available for iPhone/iPad with the Watch companion, Mac, and visionOS. Version 1.5 is waiting for App Review on all three platforms. See the [release record](docs/app-store/README.md) for builds and validation. Physical paired Watch transfer and live iCloud transfer remain unverified.

On Mac, request and response are stacked in a resizable split by default. Choose **Workspace actions → Workspace layout** to put them side by side; the split position is remembered for each layout. The sidebar stays open during resizing until you hide it. Settings opens in the native Settings window. Use ⌘F to find a request, ⇧⌘I for import/export, ⇧⌘E to export cURL, ⌘N for a new request, and ⌘Return to send or cancel.

## Interchange scope

Monkeytail workspace JSON preserves all model fields, environments, and proxy settings. Imports append collections and environments and generate fresh IDs; native imports also apply their saved proxy settings. Imported scripts run on send, as in Postman; review them in each Scripts tab, or turn off **Run scripts** to skip them.

Postman export preserves nested folders and exports the **active environment** as collection variables. Postman imports preserve folder hierarchy and inherited headers, authentication, variables, and scripts. Raw, URL-encoded, multipart, file, and GraphQL JSON bodies are supported. Scripts are preserved; execution supports the APIs documented in [Scripting](docs/Scripting.md).

Insomnia v4 JSON/YAML exports and v5 YAML collections import with their folder tree. The base environment becomes collection variables, sub-environments become environments, and folder environments, headers, auth, and scripts become folder defaults. `{{ _.variable }}` and `{{ _['variable'] }}` references are normalized. Template tags (such as response chaining) produce a notice and stay as text; gRPC requests are skipped.

Bruno collection folders (`bruno.json`, `collection.bru`, `folder.bru`, `environments/`) and JSON exports keep folders, defaults, secret environment variables, scripts, and assertions (converted to tests). Hoppscotch collections and environments convert `<<variable>>` references and keep every auth type. Thunder Client collections convert their declarative tests into scripts. HAR files group requests by host and keep recorded responses as saved examples. `.http`/`.rest` files keep `@variables`, `# @name`, bodies, and `> {% %}` response handlers. Imported scripts written for these clients run with compatibility objects; see [Scripting](docs/Scripting.md#other-clients).

Import → **Connect Postman, GitHub or Hoppscotch** opens the Evil Monk importer:

- **Postman:** paste an [API key](https://go.postman.co/settings/me/api-keys), choose the US or EU data region, and select workspaces. Every collection, environment, and the workspace globals are imported, using the [Postman API](https://learning.postman.com/docs/developer/postman-api/intro-api/). Environments are prefixed with their workspace name when several workspaces are imported.
- **GitHub:** enter `owner/repo`, `owner/repo@branch`, or a folder URL (`…/tree/branch/folder`). Every Postman, Insomnia Git Sync, Bruno, Thunder Client, Hoppscotch, `.http`, HAR, and OpenAPI file is imported, and each Bruno collection is decoded relative to its own `bruno.json`. Public repositories need no token; use a read-only fine-grained token for private ones. At most 1,000 files and 40 MB are imported.
- **Hoppscotch:** enter the server (default `https://api.hoppscotch.io`, or a self-hosted backend), a personal access token, and team collection or environment IDs, as the Hoppscotch CLI does. Hoppscotch's API does not list collections or expose personal workspaces; export those as JSON.

Insomnia Cloud Sync is end-to-end encrypted and has no export API, so use Insomnia Git Sync with the GitHub option, or export a file. Bruno and Thunder Client store collections as files or in Git. Tokens are sent only to the chosen service over an ephemeral session, without cookies or caching, and are discarded after the import.

Third-party formats do not preserve every Monkeytail setting, such as request timeouts or global proxy selection. Unsupported authentication produces an import notice; unsupported cURL flags produce an explicit error. Imported file paths are metadata only: choose each file using Files or Photos before sending. Native workspace exports include file bytes; Postman/Insomnia/cURL exports reference filenames. Use Body → Export file to transfer the actual attachments alongside third-party exports. gRPC, accounts and team workspaces, cloud monitors/mocks, and the complete scripting runtimes of other clients are outside this version; Monkeytail never requires a login. OpenAPI import and JSON Schema validation have explicit supported subsets; see [API tools](docs/APITools.md).

Browser profiles round-trip through native JSON and `curl-impersonate --impersonate` commands. Postman and Insomnia exports carry `_monkeytail` metadata for reimport into Monkeytail; those apps do not apply browser profiles themselves.

## Data and networking

Workspace and history live in the app's Application Support directory and use platform file protection and the Mac app sandbox. Workspace credentials and history use local files by default. **Use Keychain** is optional and applies to workspace credentials, cookies, client identities, and Watch copies. No Keychain lookup runs at startup with that option off. Older Keychain values remain untouched and can be restored by enabling the option; exports include saved values. There is no analytics or Kitta-operated backend. Optional iCloud Drive sync shares collections, environments, and scripts between your devices, merging each entity by its latest edit and retaining delete tombstones. Edits to different requests survive concurrent changes; the latest edit wins for the same entity. A protected local recovery copy is retained before applying remote changes. The app stays usable offline and sync checks while active and on foregrounding. **Include credentials** controls whether authentication and sensitive fields join iCloud sync. New workspaces include them; older workspaces retain their previous exclusion setting. Cookies, client identities, attachments, snapshots, and request history remain local. Field sensitivity marks apply when credential inclusion is off. Imported/synced scripts require a per-device opt-in. Switching the device's iCloud session requires toggling sync off and on. Response bodies stay in memory until explicitly saved as snapshots or exported; audio/video previews use protected temporary files that are removed when their cached response is released. Files left by an interrupted session are cleaned on launch after one day. Saving explicitly exports the original bytes. Cookies are opt-in per request, with separate device-local jars for each environment. Sessions never use Safari cookies. OAuth opens the provider in an ephemeral browser session; it does not create a Monkeytail account. Client identities remain device-local, in files or optional Keychain storage. The mock server binds only to 127.0.0.1 and stops when the app enters the background. TLS trust verification stays enabled; install and trust a debugging CA in iOS Settings when required. ATS permits HTTP because this app is a general API/debugging client.

Responses are bounded at 20 MB; text/tree and byte previews are bounded at 1 MB. Images decode to a maximum 2,048-pixel preview; saving retains the original. Audio/video playback uses only the downloaded file, with external media references disabled. JSON formatting, tree preparation, and line splitting run off the main thread. Text and tree rows render lazily, line arrays are reused during search, and syntax highlighting uses one compiled expression with a length cap for long lines. The response cache retains up to 8 responses within 40 MB. Imports are bounded at 40 MB; uploads at 20 MB; iCloud metadata at 20 MB. JSONPath and JSON diffs operate on bodies up to 2 MB with node/change limits. JavaScript contexts have a three-second deadline, use an ephemeral WebKit data store, and block direct network/DOM navigation. Their only native bridge is `pm.sendRequest`, limited to 10 HTTP(S) requests per script through the selected proxy; there is no file or app bridge. A timed-out context is discarded. Scripts are a convenience API, not a general Node.js runtime.

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
MonkeytailVision/      Native visionOS app and shared iCloud entitlements
MonkeytailWatch/       Compact favourite-request companion and WatchConnectivity
Packages/              System-only visionOS and bounded Watch core packages
MonkeytailTests/       Hosted simulator integration tests
MonkeytailUITests/     End-to-end device UI tests
Scripts/               Local verification and network fixtures, samples, icon packaging
docs/                  Scripting, release metadata, branding, screenshots
```

Protocol references: [Apple proxy configuration](https://developer.apple.com/documentation/network/proxyconfiguration), [WebKit JavaScript execution](https://developer.apple.com/documentation/webkit/wkwebview/callasyncjavascript(_:arguments:in:in:completionhandler:)), [Postman schema](https://schema.postman.com/), [Insomnia import/export](https://developer.konghq.com/insomnia/import-export/).

## License

Copyright © 2026 Kitta Ltd. Released under the [BSD 3-Clause License](LICENSE). The public product, support, and privacy pages are hosted at [docs.kitta.co](https://docs.kitta.co/monkeytail/).

Third-party components keep their own licenses; their notices are included in Settings → Licenses. See [vendor provenance](Vendor/README.md) for the pinned binaries and regeneration procedure.

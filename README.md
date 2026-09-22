<p align="center"><img src="docs/brand/monkeytail-banner.png" alt="Monkeytail — HTTP and cURL for iPhone by Kitta Co" width="880"></p>

# Monkeytail

**A native HTTP and cURL client for iPhone.** Import a command, edit your request, and inspect the response. Built in SwiftUI with an adaptive workspace for iPad and foldable windows.

Free. No in-app purchases. No account. No data collected by Kitta Co.

[Product](https://docs.kitta.co/monkeytail/) · [Privacy](https://docs.kitta.co/monkeytail/privacy/) · [Support](https://docs.kitta.co/monkeytail/support/) · [Scripting](docs/Scripting.md) · [Release setup](docs/XcodeCloud.md)

<p><img src="docs/screenshots/iphone-request.png" alt="Monkeytail iPhone request editor with inline headers" width="285"> <img src="docs/screenshots/iphone-response.png" alt="Monkeytail JSON response viewer on iPhone" width="285"></p>

See [verification results and device screenshots](docs/Verification.md). Importable [example workspaces](docs/examples) are included for Monkeytail, Postman, and Insomnia.

## Run

Open **`Monkeytail.xcodeproj`**, select the **Monkeytail** scheme and an iOS simulator, and press **Run**. For a physical device, choose your signing team under Signing & Capabilities. Requires Xcode 15 or newer and iOS 17 or newer. This project was built with Xcode 27.

The generated Xcode project is checked in. If you change target settings in `project.yml`, regenerate it with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
```

The starter collection uses httpbin.org. Requests are only sent when you tap **Send** or use the Send keyboard shortcut. Replace `base_url` in the Playground environment to use your own server.

## Included

- Native request editor: methods, URL, enabled/disabled headers and query parameters, JSON/text/URL-encoded bodies, bearer/basic authentication, timeout, redirects.
- cURL import and export, including shell quoting, multiline commands, data, JSON, cookies, basic auth, and proxy selection. The importer parses text; it never invokes a shell.
- Collections with add, rename, duplicate, delete, search, and automatic local persistence.
- Named environments and `{{variable}}` substitution throughout requests; nested variables with missing-variable and cycle detection.
- Real HTTP transport, request cancellation, response status/timing/size, response headers, and full response file sharing.
- JSON pretty printing, minification in the core library, syntax colors, expandable tree, line search, copying, and request-body formatting.
- Local JavaScript before-request and after-response hooks, console logs, assertions, tests, and environment updates.
- System networking or custom HTTP CONNECT, TLS-wrapped HTTPS CONNECT, and SOCKS5 proxies, with optional credentials and no direct fallback when a custom proxy fails.
- Postman v2/v2.1 collection and environment JSON import; Postman v2.1 collection export.
- Insomnia v4 JSON import/export. Current Insomnia can import this legacy format.
- Full-fidelity Monkeytail workspace JSON import/export, Files integration, and a system share sheet.
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

Postman export places collections in folders and exports the **active environment** as collection variables. Postman imports flatten nested folder paths into request names and inherit folder/collection authentication and scripts. Raw, URL-encoded, and GraphQL JSON bodies are supported. Scripts are preserved, but only the APIs in [Scripting](docs/Scripting.md) execute here.

Insomnia supports the v4 JSON resource format and normalizes `{{ _.variable }}` references. Environments are imported as named flat dictionaries. Nested environment inheritance and dynamic template tags are not emulated. YAML/v5 workspaces should be converted to a supported JSON format in the source tool.

Third-party formats do not preserve every Monkeytail setting, such as request timeouts or global proxy selection. Unsupported authentication produces an import notice; multipart/file bodies and unsupported cURL flags produce an explicit error. Full OAuth flows, client certificates, WebSockets, gRPC, binary uploads, multipart attachments, cloud sync, collection runners, and the complete Postman/Insomnia scripting runtimes are outside this version.

## Data and networking

Workspace and history live in the app's Application Support directory and use iOS file protection. They can contain credentials; exports include the saved values. There is no analytics or sync service. Response bodies stay in memory unless explicitly saved. Request cookies are explicit headers; sessions are ephemeral and do not share a cookie jar. TLS trust verification stays enabled; install and trust a debugging CA in iOS Settings when required. ATS permits HTTP because this app is a general API/debugging client.

Responses are bounded at 20 MB; the text/tree preview is bounded at 1 MB. JSON formatting, tree preparation, and line splitting run off the main thread. Text and tree rows render lazily, line arrays are reused during search, and syntax highlighting uses one compiled expression with a length cap for long lines. The response cache retains up to 8 responses within 40 MB. Imports are bounded at 10 MB. JavaScript contexts have a three-second deadline, use an ephemeral WebKit data store, block network/DOM navigation, and expose no native file or app bridge. A timed-out context is discarded. Scripts are a convenience API, not a general Node.js runtime.

## Verification

Pure model, parser, collection, encoding, JSON, and proxy-configuration tests:

```sh
swift test
```

Simulator integration and UI tests use a local HTTP server plus real CONNECT and SOCKS5 fixtures, with no public API dependencies:

```sh
./Scripts/test.sh 'platform=iOS Simulator,name=iPhone Duo'
# Or pass another installed simulator destination, e.g.:
./Scripts/test.sh 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0'
```

The suite verifies transport, redirects, credential removal across origins, cancellation, limits, both proxy protocols, script mutation/assertions/errors/timeouts/network blocking, persistence, and a send → inspect → import → edit → cURL export UI flow in portrait and landscape. UI tests use an isolated temporary workspace and do not change normal user collections.

## Project structure

```text
Sources/MonkeytailCore/  Codable models, request builder, HTTP transport, cURL,
                        collection codecs, JSON formatting/tree
Monkeytail/Services/    Observable workspace/persistence and WebKit script runner
Monkeytail/Views/       Native adaptive SwiftUI interface
Tests/                 Core Swift package tests
MonkeytailTests/       Hosted simulator integration tests
MonkeytailUITests/     End-to-end device UI tests
Scripts/               Local verification, samples, icon packaging
ci_scripts/            Xcode Cloud hooks and local network fixtures
docs/                  Scripting, release metadata, branding, screenshots
```

Protocol references: [Apple proxy configuration](https://developer.apple.com/documentation/network/proxyconfiguration), [WebKit JavaScript execution](https://developer.apple.com/documentation/webkit/wkwebview/callasyncjavascript(_:arguments:in:in:completionhandler:)), [Postman schema](https://schema.postman.com/), [Insomnia import/export](https://developer.konghq.com/insomnia/import-export/).

## Ownership

Private source repository for Kitta Co (Kitta Ltd). Copyright © 2026 Kitta Ltd. All rights reserved. The public product, support, and privacy pages are hosted at [docs.kitta.co](https://docs.kitta.co/monkeytail/).

# Verification — 22 September 2026

Built with Xcode 27.0 (27A266a), Swift 6.4, with an iOS 17 deployment target.

| Check | Result |
| --- | --- |
| Swift package unit tests | 24 passed |
| Hosted integration tests, iPhone Duo / iOS 27.1 | 10 passed |
| Send → search → JSON tree → import → edit → cURL export UI flow, iPhone SE (3rd generation) / iOS 18.0 | Passed |
| Same UI flow, iPhone 18 Pro / iOS 27.0 | Passed |
| Same UI flow, iPhone Duo / iOS 27.1 | Passed |
| Same UI flow, iPad Pro 13-inch (M5) / iPadOS 27.0 | Passed |
| Postman export against official v2.1 JSON Schema | Passed |
| Manual iPad landscape screenshot review | Passed |
| Response viewport regression and keyboard/resend checks, iPhone 18 Pro / iOS 27.0 | Passed |
| Response format switching and Raw resend regression, iPhone 17 Pro / iOS 26.2, iPad Pro 13-inch / iPadOS 27.0, and iPhone Duo / iOS 27.1 | Passed on all three |
| Full hosted suite after response layout fix, iPhone 18 Pro / iOS 27.0 | 10 integration + 3 UI tests passed |
| Release build for a generic iOS device after response layout fix | Passed (without signing) |
| Full suite with browser transport, iPhone 18 Pro / iOS 27.0 | 14 integration + 4 UI tests passed |
| Browser profile import → edit → send → export, iPhone 18 Pro / iOS 27.0, iPad Pro 13-inch / iPadOS 27.0, and iPhone Duo / iOS 27.1 | Passed on all three |
| Browser profile flow, iPhone SE (3rd generation) / iOS 18.0 | Passed at 375-point width |
| Browser TLS transport Release build for a generic iOS device | Passed (without signing); app bundle about 8.4 MB |
| Public HTTPS smoke check with Apple native trust, macOS | All five profiles returned verified HTTP 200 from example.com |
| Release simulator investigation, iPhone 18 Pro / iOS 27.0 | Real httpbin GET and imported JSON POST rendered in Pretty and Raw; blank body not reproduced |
| 422-byte compact JSON response in Release, iPhone 18 Pro / iOS 27.0 | Visible through Pretty/Raw/Tree, copy, background/foreground, Headers/Body, Request/Response, search, and resend |
| Full Release suite after atomic response publication and MIME viewers, iPhone 18 Pro / iOS 27.0 | 16 integration + 7 UI tests passed |
| MIME viewers and compact audio playback, iPhone SE / iOS 18.0 and iPad Pro 13-inch / iPadOS 27.0 | Passed on both, including visible Send controls |
| Final media viewer Release build, generic iOS device | Passed without signing |
| Final compact audio controls, media viewport bounds, and 1 MB UTF-8 preview boundary, iPhone 18 Pro / iOS 27.0 | Passed in Release; Send remains reachable for valid and invalid media |

Integration coverage includes real HTTP request encoding, HTTP CONNECT and SOCKS5 proxy routing, redirects and cross-origin credential stripping, cancellation, response size limits, persistence, sandbox network blocking, exceptions, infinite-loop timeout/recovery, and a full pre-hook → transport → post-hook flow that saves environment variables.

Browser transport tests capture real TLS ClientHello fields and HTTP/2 SETTINGS at a loopback TLS server. Every preset negotiates HTTP/2; Chrome and Safari assertions check their exact ordered SETTINGS and distinct cipher/extension lists. The fixture uses a temporary CA only through an internal test seam. The production path rejects that untrusted CA. Additional checks cover browser header overrides, disabling default browser headers, request bodies containing NUL, CONNECT/SOCKS routing, credential removal on redirects, the 20 MB response bound, prompt cancellation, persistence, backward-compatible decoding, and browser-profile round-trips through cURL and every supported collection format. The public HTTPS smoke check was separate from the deterministic CI suite.

The profile selector keeps its label visible and its menu hit area separate. Small-phone testing on iOS 18 caught a combined label/menu accessibility frame that could miss taps after returning from the response pane; the corrected control passes the full profile workflow, including returning to System transport.

Verification caught and corrected CRLF header validation, plus-sign query encoding, keyboard-obstructed import actions, loss of editor state when changing panes, WebKit startup consuming the execution timeout, and `crypto.randomUUID()` availability inside the isolated document.

The compact iPhone layout is checked at 375-point width on iPhone SE and at a larger phone size. The UI flow verifies header edits survive Request/Response switching, switching dismisses the keyboard, Send stays reachable, and cURL export contains the edited header. Landscape keeps short phone windows in one pane. JSON tree screenshots verify that rows stay aligned and scroll horizontally without wrapping into narrow columns. Testing also caught a newer-runtime segmented-control interaction issue and a search field that left too little room for matches on short windows; explicit pane buttons and collapsing response controls address those cases.

Response preparation runs off the main thread; text and tree views use lazy rows. Trees start with only the first two levels expanded. Syntax matching is compiled once and skipped for lines longer than 16 KB. These are implementation improvements; no device performance benchmark is claimed.

The response viewport regression reproduced a completely blank body after horizontally scrolling Raw and returning to Pretty: the text retained the old horizontal offset outside the visible pane. The viewer now starts at the top-left with fresh scroll state for each response, format, and search. It mounts rows only after the current preview is ready. Compact layouts keep both panes at the available width, preserve editor state, and disable interaction with the hidden pane. The regression targets the response scroll view explicitly and checks visible coordinates, not just the existence of response text. Local fixtures cover long JSON, keyboard dismissal, filtering, copying, tree switching, and repeated POST requests; no user API endpoints were called.

The subsequent iOS 27 failure was observed live in the user's displayed simulator: a successful 422-byte response remained on a preview spinner while the process was idle. The stored body was valid JSON. A sanitized replay preserves its exact structure and length; no real response values or credentials are included in tests. Preview preparation now belongs to request completion, and response metadata plus prepared content publish as one immutable value. Rendering no longer depends on a cancellable view task. The exact original lifecycle trigger was not established. A final manual HTTPS request to httpbin.org/json returned 200 and displayed its 429-byte body in Pretty and Raw on iOS 27. The Release replay verifies visible Pretty/Raw/Tree content, a populated file share sheet, and background/foreground recovery.

MIME previews decode images with ImageIO before offering Image mode. Audio and video use local protected response files and AVFoundation's `forbidAll` reference restriction. Synthetic PNG/WAV/MP4 fixtures, arbitrary bytes, and invalid image/audio payloads exercise the preview and fallback paths. Byte formatting tests preserve offsets, zero bytes, non-ASCII bytes, and partial rows. The media cache lifetime test verifies temporary files disappear when the prepared response is released.

No physical-device signing, App Store distribution, hardware hinge transitions, or independent display routing was tested. The foldable layout follows available window geometry; the installed Duo configuration was exercised without relying on device-specific or private APIs. HTTPS CONNECT uses Apple's TLS proxy configuration but is not covered by the plaintext CONNECT/SOCKS5 fixture.

Screenshots:

- [iPad workspace in landscape](screenshots/ipad-workspace.png)
- [iPad JSON tree](screenshots/ipad-response.png)
- [iPhone request editor](screenshots/iphone-request.png)
- [iPhone audio playback controls](screenshots/iphone-audio.png)
- [iPhone Hex viewer](screenshots/iphone-hex.png)
- [iPhone validated image preview](screenshots/iphone-image.png)
- [iPhone sanitized response replay](screenshots/iphone-replayed-response.png)
- [iPhone pretty JSON](screenshots/iphone-response.png)
- [iPhone compact Raw response, Release / iOS 27](screenshots/iphone-compact-release-response.png)
- [iPhone browser TLS profile](screenshots/iphone-browser-profile.png)
- [Small iPhone JSON tree](screenshots/iphone-se-response.png)
- [Duo response view](screenshots/duo-response.png)

Run `swift test` for core tests or `Scripts/test.sh` for the complete local fixture suite. See the project README for simulator destination arguments.


## Version 1.1 verification — September 30, 2026

- 34 Swift core tests passed, including multipart byte fidelity, safe unresolved file imports, native/Postman/Insomnia attachment metadata, sync merge/tombstones/secret isolation, legacy credential migration, JSONPath, and response diffs.
- The complete iOS 27 iPhone suite passed: 21 hosted integration tests and 9 UI tests. The new flows cover diagnostics, snapshots, extraction, multipart import, and optional sync controls.
- Release verification passed: 22 hosted integration tests, including device Keychain migration and snapshot eviction, plus the 2 new UI flows (snapshot comparison included). A final Release integration pass verified the persistence changes.
- Multipart and raw binary uploads matched fixture bytes on System and browser transports. Both reported redirect hops, sent headers, bounded bodies, and timings.
- Automatic workspace encoding/writes run on a serial background queue; superseded saves are skipped. Attachments are capped at 40 MB per workspace. Responses/uploads remain capped at 20 MB each. Snapshots retain at most 50 entries within 60 MB.
- Dedicated `iCloud.co.kitta.monkeytail` container registered and assigned to the production App ID. Sync remains off by default. Offline/no-session behavior preserves the local workspace. Live transfer between two signed-in iCloud devices has not been exercised in the simulator; merge behavior is covered independently.


## 1.2 Mac and API tools

- 48 core tests passed: nested inheritance, OAuth PKCE/refresh, official AWS S3 signing vectors, cookie scoping/public suffixes, OpenAPI YAML/local references, portable JSON Schema, GraphQL, SSE parsing, code redaction, mock cancellation, and advanced-credential sync exclusion.
- Six native Mac integration tests passed on October 2, 2026: OAuth refresh plus inherited scripts/assertions, scoped cookie redirects on both HTTP transports, offline/loopback mocks and snapshot reuse, WebSocket text/binary plus SSE, local cookie persistence, and valid/wrong-password PKCS#12 import with certificate validity and exact-host identity selection.
- The provisioned universal Mac Release archive succeeded with the production bundle ID, shared iCloud Documents container, app sandbox, network client/server, and user-selected file entitlements.
- Native Mac UI sent an HTTPS request to httpbin, displayed its JSON body, and showed a passing visual status assertion. The actual 2560 × 1600 screenshot is included under `docs/app-store/screenshots/mac`.
- Live iCloud transfer between a physical iPhone and Mac has not been independently observed. The shared record format, merge/secret rules, and production signing entitlements are verified.

- GitHub Actions independently passed all 48 core tests and six native Mac hosted integration tests at `6aafc12`. A local final Mac run had one WebKit startup timeout while simulators were heavily loaded; that test passed when rerun alone. No execution deadline was increased.
- Xcode Cloud archives for Mac build 17 and iOS build 18 succeeded; both were processed as valid for App Store submission.

- Xcode Cloud run 19 passed 28 hosted integration and all ten UI tests on iPhone 18 Pro / iOS 27.0, including OpenAPI import → visual assertions → offline mock, body lifecycle/format changes, and MIME previews. The certificate-import test emitted Apple's main-thread performance warning and passed.
- A fresh local iOS 27 Release UI run stalled before launching tests and was stopped; no local UI pass is claimed for that run. The iOS Release app build succeeded.


## 1.3 visionOS and Watch companion

- 48 core tests plus two Watch payload tests pass locally. Watch tests validate exact binary payload round trips, duplicate/ten-request limits, oversize payload/body rejection, URL restrictions, header CR/LF injection, and timeout limits.
- The native visionOS target shares the canonical core through a system-only package. The Watch target shares only the bounded companion transport/models and is embedded in iOS. The pinned browser framework remains on iOS/Mac.
- Dedicated UI tests send a loopback JSON request and assert visible response content on visionOS and a compact Watch. Hosted iOS tests cover private-field omission, explicit inclusion, private URL handling, and unsupported transports. Mac fixture tests cover Watch transport byte formatting, cross-origin credential removal, no-redirect behavior, oversize response rejection, and cancellation.
- Physical paired iPhone–Watch transfer and live iCloud transfer between Apple devices remain unverified. Payload preparation, validation, storage policy, and transport behavior are covered separately.

- GitHub run 37042258122 passed at `15a7d97`: all 50 core/payload tests and nine Mac hosted integration tests. A separate local Mac run passed all three Watch HTTP fixture tests. Final iOS and visionOS simulator test bundles compiled successfully, including the corrected visionOS icon stack dimensions.

- At `e7e7920`, GitHub run 37048779581 passed 50 core/payload tests and nine Mac integration tests. Xcode Cloud run 41 passed both native visionOS and 42 mm Watch UI checks: real loopback send, HTTP 200, readable JSON, and an immediately reachable compact Body sheet. The earlier nested Watch response navigation failed and was replaced; those failures are retained in Cloud history.
- A signed local visionOS simulator build was launched, sent the captured 422-byte body fixture, and displayed its JSON. The HTTP method is now readable on visionOS. The native Device Hub camera produced an unedited 3840 × 2160 screenshot for App Store Connect. Homem’s simulator and app were restarted after capture.
- Xcode Cloud signed archives 43 (visionOS), 44 (Mac), and 45 (iOS with embedded Watch) are processed and valid. All report `usesNonExemptEncryption: false`. Cloud iOS run 32 passed all 30 hosted and ten UI tests.
- The final Cloud iOS run 42 at `e7e7920` passed all 30 hosted and ten UI tests. Cloud run 46 passed visionOS and both 42 mm and 46 mm Watch checks; its native 416 × 496 response screenshot is used for the Watch store listing.
- iOS/Watch 1.3 (45), Mac 1.3 (44), and visionOS 1.3 (43) were submitted and verified Waiting for Review on October 3, 2026. The former pending 1.2 reviews were canceled and replaced. See [the release record](app-store/README.md).

## Credential options and layout follow-up — October 3, 2026

- Keychain storage is optional and off by default. The file backend does not query Keychain at launch. Legacy Keychain entries remain untouched until the user enables the option to recover them. Existing credential-sharing and code-hiding preferences are preserved.
- Four focused native Mac integration tests pass: workspace file/Keychain round trips, optional legacy recovery, cookie storage switching, and Watch-copy storage switching. The core and payload suite passes 51 tests, including credential-inclusive sync and subsequent exclusion.
- Final Debug simulator builds pass for iOS with its embedded Watch app and visionOS. The native Mac build and focused tests pass after the Settings layout changes. Release identity/privacy checks pass for all four platforms.
- Sidebar symbols use one fixed-width column and all titles start at the same position. Settings uses native grouped rows, right-aligned switches, a compact Mac sheet, and collapsed storage limits. Rebuilt Mac UI was inspected directly; normal launch showed no Keychain password prompt.
- [Aligned Mac sidebar](screenshots/mac-sidebar-aligned.png). [Compact Settings with Keychain off](screenshots/mac-optional-keychain.png).
- These follow-up source changes are newer than submitted builds 43–45. Those earlier review submissions were not replaced during this follow-up.

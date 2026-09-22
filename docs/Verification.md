# Verification — 22 September 2026

Built with Xcode 27.0 (27A266a), Swift 6.4, with an iOS 17 deployment target.

| Check | Result |
| --- | --- |
| Swift package unit tests | 23 passed |
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

Integration coverage includes real HTTP request encoding, HTTP CONNECT and SOCKS5 proxy routing, redirects and cross-origin credential stripping, cancellation, response size limits, persistence, sandbox network blocking, exceptions, infinite-loop timeout/recovery, and a full pre-hook → transport → post-hook flow that saves environment variables.

Browser transport tests capture real TLS ClientHello fields and HTTP/2 SETTINGS at a loopback TLS server. Every preset negotiates HTTP/2; Chrome and Safari assertions check their exact ordered SETTINGS and distinct cipher/extension lists. The fixture uses a temporary CA only through an internal test seam. The production path rejects that untrusted CA. Additional checks cover browser header overrides, disabling default browser headers, request bodies containing NUL, CONNECT/SOCKS routing, credential removal on redirects, the 20 MB response bound, prompt cancellation, persistence, backward-compatible decoding, and browser-profile round-trips through cURL and every supported collection format. The public HTTPS smoke check was separate from the deterministic CI suite.

The profile selector keeps its label visible and its menu hit area separate. Small-phone testing on iOS 18 caught a combined label/menu accessibility frame that could miss taps after returning from the response pane; the corrected control passes the full profile workflow, including returning to System transport.

Verification caught and corrected CRLF header validation, plus-sign query encoding, keyboard-obstructed import actions, loss of editor state when changing panes, WebKit startup consuming the execution timeout, and `crypto.randomUUID()` availability inside the isolated document.

The compact iPhone layout is checked at 375-point width on iPhone SE and at a larger phone size. The UI flow verifies header edits survive Request/Response switching, switching dismisses the keyboard, Send stays reachable, and cURL export contains the edited header. Landscape keeps short phone windows in one pane. JSON tree screenshots verify that rows stay aligned and scroll horizontally without wrapping into narrow columns. Testing also caught a newer-runtime segmented-control interaction issue and a search field that left too little room for matches on short windows; explicit pane buttons and collapsing response controls address those cases.

Response preparation runs off the main thread; text and tree views use lazy rows. Trees start with only the first two levels expanded. Syntax matching is compiled once and skipped for lines longer than 16 KB. These are implementation improvements; no device performance benchmark is claimed.

The response viewport regression reproduced a completely blank body after horizontally scrolling Raw and returning to Pretty: the text retained the old horizontal offset outside the visible pane. The viewer now starts at the top-left with fresh scroll state for each response, format, and search. It mounts rows only after the current preview is ready. Compact layouts keep both panes at the available width, preserve editor state, and disable interaction with the hidden pane. The regression targets the response scroll view explicitly and checks visible coordinates, not just the existence of response text. Local fixtures cover long JSON, keyboard dismissal, filtering, copying, tree switching, and repeated POST requests; no user API endpoints were called.

A subsequent report of a blank body on iOS 27 remains unreproduced on the current source. Manual testing used a Release build from the same app source as TestFlight build 10, without UI-test launch arguments, and real HTTPS GET/POST requests to httpbin.org. An additional Release UI regression uses a 422-byte single-line JSON fixture matching the reported response size and verifies on-screen text coordinates through the transitions above. Its screenshots show the Raw body immediately below the search field. This evidence does not establish that the reported device-specific failure is fixed; the installed TestFlight build and a reproducible request are still needed to match that report.

No physical-device signing, App Store distribution, hardware hinge transitions, or independent display routing was tested. The foldable layout follows available window geometry; the installed Duo configuration was exercised without relying on device-specific or private APIs. HTTPS CONNECT uses Apple's TLS proxy configuration but is not covered by the plaintext CONNECT/SOCKS5 fixture.

Screenshots:

- [iPad workspace in landscape](screenshots/ipad-workspace.png)
- [iPad JSON tree](screenshots/ipad-response.png)
- [iPhone request editor](screenshots/iphone-request.png)
- [iPhone pretty JSON](screenshots/iphone-response.png)
- [iPhone compact Raw response, Release / iOS 27](screenshots/iphone-compact-release-response.png)
- [iPhone browser TLS profile](screenshots/iphone-browser-profile.png)
- [Small iPhone JSON tree](screenshots/iphone-se-response.png)
- [Duo response view](screenshots/duo-response.png)

Run `swift test` for core tests or `Scripts/test.sh` for the complete local fixture suite. See the project README for simulator destination arguments.

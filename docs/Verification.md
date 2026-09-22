# Verification — 22 September 2026

Built with Xcode 27.0 (27A266a), Swift 6.4, with an iOS 17 deployment target.

| Check | Result |
| --- | --- |
| Swift package unit tests | 19 passed |
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

Integration coverage includes real HTTP request encoding, HTTP CONNECT and SOCKS5 proxy routing, redirects and cross-origin credential stripping, cancellation, response size limits, persistence, sandbox network blocking, exceptions, infinite-loop timeout/recovery, and a full pre-hook → transport → post-hook flow that saves environment variables.

Verification caught and corrected CRLF header validation, plus-sign query encoding, keyboard-obstructed import actions, loss of editor state when changing panes, WebKit startup consuming the execution timeout, and `crypto.randomUUID()` availability inside the isolated document.

The compact iPhone layout is checked at 375-point width on iPhone SE and at a larger phone size. The UI flow verifies header edits survive Request/Response switching, switching dismisses the keyboard, Send stays reachable, and cURL export contains the edited header. Landscape keeps short phone windows in one pane. JSON tree screenshots verify that rows stay aligned and scroll horizontally without wrapping into narrow columns. Testing also caught a newer-runtime segmented-control interaction issue and a search field that left too little room for matches on short windows; explicit pane buttons and collapsing response controls address those cases.

Response preparation runs off the main thread; text and tree views use lazy rows. Trees start with only the first two levels expanded. Syntax matching is compiled once and skipped for lines longer than 16 KB. These are implementation improvements; no device performance benchmark is claimed.

The response viewport regression reproduced a completely blank body after horizontally scrolling Raw and returning to Pretty: the text retained the old horizontal offset outside the visible pane. The viewer now starts at the top-left with fresh scroll state for each response, format, and search. It mounts rows only after the current preview is ready. Compact layouts keep both panes at the available width, preserve editor state, and disable interaction with the hidden pane. The regression targets the response scroll view explicitly and checks visible coordinates, not just the existence of response text. Local fixtures cover long JSON, keyboard dismissal, filtering, copying, tree switching, and repeated POST requests; no user API endpoints were called.

No physical-device signing, App Store distribution, hardware hinge transitions, or independent display routing was tested. The foldable layout follows available window geometry; the installed Duo configuration was exercised without relying on device-specific or private APIs. HTTPS CONNECT uses Apple's TLS proxy configuration but is not covered by the plaintext CONNECT/SOCKS5 fixture.

Screenshots:

- [iPad workspace in landscape](screenshots/ipad-workspace.png)
- [iPad JSON tree](screenshots/ipad-response.png)
- [iPhone request editor](screenshots/iphone-request.png)
- [iPhone pretty JSON](screenshots/iphone-response.png)
- [Small iPhone JSON tree](screenshots/iphone-se-response.png)
- [Duo response view](screenshots/duo-response.png)

Run `swift test` for core tests or `Scripts/test.sh` for the complete local fixture suite. See the project README for simulator destination arguments.

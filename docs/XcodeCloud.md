# Release and Xcode Cloud

- Apple Developer organization: Kitta Ltd (Kitta Co)
- Team: `7P8CLHDH5G`
- App: Monkeytail, version 1.0
- Bundle ID: `co.kitta.monkeytail`
- Repository: [iebb/Monkeytail](https://github.com/iebb/Monkeytail), private
- Branch: `main`; project: `Monkeytail.xcodeproj`; shared scheme: `Monkeytail`
- Price: free; no in-app purchases

The generated project is committed, so Cloud does not need XcodeGen. Regenerate with `xcodegen generate` after changing `project.yml`.

## Build hooks

`ci_post_clone.sh` validates the bundle ID, team, privacy manifest, encryption declaration, and opaque 1024px app icon. `ci_pre_xcodebuild.sh` starts HTTP, CONNECT, and SOCKS5 fixtures on the separate test worker. `ci_post_xcodebuild.sh` stops them after testing. The fixture is self-contained in `ci_scripts` so it is available in the testing environment.

The shared scheme runs hosted integration tests and UI tests without parallel execution. GitHub Actions separately runs the core Swift package tests. Tests use loopback servers and require no production credentials.

## Intended workflow

Build on changes to main and pull requests targeting main, cancel superseded runs, run required iPhone simulator tests, and archive for TestFlight and App Store distribution with automatic signing. Apple-side activation and the first build are tracked below once verified.

## Publication

Public URLs: [product](https://docs.kitta.co/monkeytail/), [privacy](https://docs.kitta.co/monkeytail/privacy/), [support](https://docs.kitta.co/monkeytail/support/).

The app includes no telemetry, advertising, tracking, account service, or cloud sync. Its App Store privacy answer is Data Not Collected. Requests go to user-selected servers and proxies. Standard OS HTTPS/TLS is used; the app declares no non-exempt encryption.

Apple references: [custom scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts), [environment variables](https://developer.apple.com/documentation/xcode/environment-variable-reference).

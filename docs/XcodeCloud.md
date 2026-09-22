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

## Active workflow

`Monkeytail CI` runs on changes to `main` and can be started manually for any branch. It cancels superseded push builds, runs required tests on iPhone 18 Pro with the latest release iOS simulator, and archives for App Store Connect with automatic signing. Both Xcode and macOS track the latest release. GitHub Actions runs core tests for pushes and pull requests to `main`.

- [App Store Connect app](https://appstoreconnect.apple.com/apps/6814706725/distribution): `6814706725`
- [Cloud workflow](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/503e6b3e-e4f0-497c-84de-827b8c8b88bd/workflows/31C47B5F-652E-4FB9-8998-248C9C0E2CB8)
- Connected September 22, 2026. [Build 4](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/503e6b3e-e4f0-497c-84de-827b8c8b88bd/builds/044ace29-c142-49a1-a0b2-4f8d65438dcd) at `5949fa9` passed required iOS tests and the App Store archive. The signed version is `1.0 (4)`. Test targets generate Info.plist files for Cloud signing.

## Publication

Public URLs: [product](https://docs.kitta.co/monkeytail/), [privacy](https://docs.kitta.co/monkeytail/privacy/), [support](https://docs.kitta.co/monkeytail/support/).

The app includes no telemetry, advertising, tracking, account service, or cloud sync. Its App Store privacy answer is Data Not Collected. Requests go to user-selected servers and proxies. System requests use Apple's networking stack; browser profiles bundle curl-impersonate and BoringSSL. Builds omit `ITSAppUsesNonExemptEncryption` so the actual encryption use is declared in App Store Connect. Select standard encryption algorithms outside Apple's operating system. Apple's questionnaire requires a French encryption approval document when France is included in distribution; resolve that requirement before resubmitting the browser-profile build. See [Apple's documentation requirements](https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption/).

Apple references: [custom scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts), [environment variables](https://developer.apple.com/documentation/xcode/environment-variable-reference).

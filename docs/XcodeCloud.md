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

`Monkeytail CI` runs on changes to `main` and can be started manually for any branch. It cancels superseded push builds and archives for App Store Connect with automatic signing, followed by TestFlight internal distribution. As observed for build 10, the Cloud workflow runs Archive only; hosted integration and UI tests are run locally. Both Xcode and macOS track the latest release. GitHub Actions runs core tests for pushes and pull requests to `main`.

- [App Store Connect app](https://appstoreconnect.apple.com/apps/6814706725/distribution): `6814706725`
- [Cloud workflow](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/503e6b3e-e4f0-497c-84de-827b8c8b88bd/workflows/31C47B5F-652E-4FB9-8998-248C9C0E2CB8)
- Connected September 22, 2026. [Build 4](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/503e6b3e-e4f0-497c-84de-827b8c8b88bd/builds/044ace29-c142-49a1-a0b2-4f8d65438dcd) at `5949fa9` passed required iOS tests and the App Store archive. The signed version is `1.0 (4)`. Test targets generate Info.plist files for Cloud signing.
- [Build 10](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/503e6b3e-e4f0-497c-84de-827b8c8b88bd/builds/fee9863c-3d6e-4750-8115-c320a6e591ec) at `d51b8ba` passed archive and TestFlight distribution on September 22, 2026. Version `1.0 (10)` was resubmitted for App Review at 16:54 JST with the response-body fix, browser profiles, and the exempt-encryption declaration. GitHub Actions passed for the same commit.

## Publication

Public URLs: [product](https://docs.kitta.co/monkeytail/), [privacy](https://docs.kitta.co/monkeytail/privacy/), [support](https://docs.kitta.co/monkeytail/support/).

The app includes no telemetry, advertising, tracking, account service, or cloud sync. Its App Store privacy answer is Data Not Collected. Requests go to user-selected servers and proxies. System requests use Apple's networking stack; browser profiles bundle curl-impersonate and BoringSSL. The developer classifies the app's standard HTTPS/TLS use as exempt encryption and has directed that `ITSAppUsesNonExemptEncryption` remain `false`. This declares no non-exempt encryption; it does not claim that HTTPS is unencrypted or disable certificate verification. See [Apple's definition of the declaration](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption).

Apple references: [custom scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts), [environment variables](https://developer.apple.com/documentation/xcode/environment-variable-reference).

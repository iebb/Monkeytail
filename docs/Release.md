# Release

- Apple Developer organization: Kitta Ltd (Kitta Co)
- Team: `7P8CLHDH5G`
- App: Monkeytail, version 1.6.3
- Bundle ID: `co.kitta.monkeytail`
- Repository: [iebb/Monkeytail](https://github.com/iebb/Monkeytail), public, BSD 3-Clause
- Branch: `main`; project: `Monkeytail.xcodeproj`; shared scheme: `Monkeytail`
- Price: free; no in-app purchases

For documentation-only pushes, use `[ci skip]` in the commit message ([GitHub guidance](https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-workflow-runs/skipping-workflow-runs)).

The generated project is committed, so CI does not need XcodeGen. Regenerate with `xcodegen generate` after changing `project.yml`.

## GitHub Actions build

Builds run in GitHub Actions (`.github/workflows/build.yml`); Xcode Cloud is no longer used and CI runs no tests. Run tests locally with `swift test` and `Scripts/test.sh`.

`Build` runs on pushes to `main` and can be started manually for any branch. It cancels superseded builds, runs `Scripts/verify_release.py`, then archives `Monkeytail` (iOS with the embedded Watch app), `MonkeytailMac`, and `MonkeytailVision` on the `xcode-27` runner with automatic signing. Pushes upload every archive to App Store Connect for TestFlight. Manual runs can turn off the upload and keep the exported packages as workflow artifacts instead.

The build number is the commit height (`git rev-list --count HEAD`), so each commit on `main` maps to one build. Re-running a workflow for the same commit reuses its build number, which App Store Connect rejects as a duplicate upload. Build 1003 of version 1.6.1 was uploaded before this scheme, so later builds need a new marketing version to be accepted.

Repository secrets:

- `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`: App Store Connect API key (Admin role, for cloud-managed signing) and the contents of its `.p8` file.
- `SIGNING_CERTIFICATE_P12`, `SIGNING_CERTIFICATE_PASSWORD` (optional): base64-encoded `.p12` with an Apple Development/Distribution identity. Use these if cloud-managed signing is not available.

Internal TestFlight testers receive uploaded builds when their group has automatic distribution enabled.

After the archives, `TestFlight` jobs wait for Apple to process each uploaded build, set What to Test from the commit message, add the build to the external `Public` group ([public link](https://testflight.apple.com/join/5D3rEVNe)), and submit it for beta review (`Scripts/testflight_submit.py`). Submission problems, such as a build already in review, become warnings and do not fail the run. A build that fails processing does. Set the `BETA_GROUP` repository variable to use a different group. The beta review contact and TestFlight description are configured in App Store Connect.

## Xcode Cloud history

Earlier releases were archived and tested in Xcode Cloud. Its hooks validated release metadata and started the local network fixtures, which now live in `Scripts/`. Mac run 63 passed all 13 native Mac tests on macOS 27 at `b783f3a`.

- [App Store Connect app](https://appstoreconnect.apple.com/apps/6814706725/distribution): `6814706725`
- [Cloud workflow](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/503e6b3e-e4f0-497c-84de-827b8c8b88bd/workflows/31C47B5F-652E-4FB9-8998-248C9C0E2CB8)
- Connected September 22, 2026. [Build 4](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/503e6b3e-e4f0-497c-84de-827b8c8b88bd/builds/044ace29-c142-49a1-a0b2-4f8d65438dcd) at `5949fa9` passed required iOS tests and the App Store archive. The signed version is `1.0 (4)`. Test targets generate Info.plist files for Cloud signing.
- [Build 10](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/503e6b3e-e4f0-497c-84de-827b8c8b88bd/builds/fee9863c-3d6e-4750-8115-c320a6e591ec) at `d51b8ba` passed archive and TestFlight distribution on September 22, 2026. Version `1.0 (10)` was resubmitted for App Review at 16:54 JST with the response-body fix, browser profiles, and the exempt-encryption declaration. GitHub Actions passed for the same commit.

- [Build 13](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/503e6b3e-e4f0-497c-84de-827b8c8b88bd/builds/fc74da85-c1c0-4d8d-915b-37bdff1ffa7e) at `ecbd69a` passed archive and TestFlight distribution on September 22, 2026. Version `1.0 (13)` is Waiting for Review under [submission 72bc0389-c4f2-4811-8370-aac6a1d4eea7](https://appstoreconnect.apple.com/apps/6814706725/distribution/reviewsubmissions/details/72bc0389-c4f2-4811-8370-aac6a1d4eea7). It includes the atomic preview fix and MIME-aware media/byte viewers. GitHub Actions and the local Release checks passed; the encryption declaration remains `false`.

## Publication

Public URLs: [product](https://docs.kitta.co/monkeytail/), [privacy](https://docs.kitta.co/monkeytail/privacy/), [support](https://docs.kitta.co/monkeytail/support/).

The app includes no telemetry, advertising, tracking, account service, or Kitta-operated backend. iCloud Drive sync is on by default, uses the existing Apple session, and stores data only in the user’s own iCloud container. Its App Store privacy answer is Data Not Collected. Requests go to user-selected servers and proxies. System requests use Apple's networking stack; browser profiles bundle curl-impersonate and BoringSSL. The developer classifies the app's standard HTTPS/TLS use as exempt encryption and has directed that `ITSAppUsesNonExemptEncryption` remain `false`. This declares no non-exempt encryption; it does not claim that HTTPS is unencrypted or disable certificate verification. See [Apple's definition of the declaration](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption).

Apple references: [custom scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts), [environment variables](https://developer.apple.com/documentation/xcode/environment-variable-reference).


## Native Mac release

Version 1.2 adds the `MonkeytailMac` scheme, sharing bundle ID `co.kitta.monkeytail` and iCloud container `iCloud.co.kitta.monkeytail` with iOS. The Mac release uses sandbox, user-selected file access, network client/server, and iCloud Documents entitlements. Debug ad-hoc builds omit iCloud signing entitlements; use a provisioned Release build for iCloud.

`Monkeytail Mac CI` archives the Mac scheme for App Store eligibility on pushes to `main`, using the latest Xcode and macOS release. Workflow ID: `757bc878-8cdd-42e4-baeb-d4ef08de99ee`. Local Mac integration tests cover OAuth refresh, cookies and redirects, identity import and certificate validity, mocks/snapshots, and WebSocket/SSE. No production credentials are used in tests.

## Version 1.2 workflows and submission

- `Monkeytail iOS Tests`: workflow `3cd3a64f-c5e7-46ff-808a-61f1084dc966`, required Test action using scheme settings, iPhone 18 Pro / iOS 27.0, clean build, latest Xcode/macOS. Runs on main pushes and supports manual runs.
- GitHub Actions [run 37034278033](https://github.com/iebb/Monkeytail/actions/runs/37034278033) passed core tests and all six native Mac integration tests at `6aafc12`.
- Cloud Mac archive 17 and iOS archive 18 succeeded at the same commit. App Store Connect processed both builds as valid with `usesNonExemptEncryption=false`.
- Mac version `1.2 (17)` was submitted on October 3, 2026 (Singapore time), under [review submission 2cbc5088-bc7b-48b1-8c7f-ebe0ce5ea0fe](https://appstoreconnect.apple.com/apps/6814706725/distribution/reviewsubmissions/details/2cbc5088-bc7b-48b1-8c7f-ebe0ce5ea0fe). The verified submission state was Waiting for Review.

- iOS version `1.2 (18)` was submitted under [review submission f63062a6-f0cb-45b8-8517-65dc67834c90](https://appstoreconnect.apple.com/apps/6814706725/distribution/reviewsubmissions/details/f63062a6-f0cb-45b8-8517-65dc67834c90). The verified submission state was Waiting for Review.
- Cloud test run 19 at `6aafc12` passed the 28 hosted integration and ten UI test cases on iPhone 18 Pro / iOS 27.0.


## 1.3 native visionOS and Watch

The `Monkeytail visionOS CI` workflow archives scheme `MonkeytailVision` for `ANY_VISIONOS_DEVICE`. `Monkeytail Vision and Watch Tests` runs both native UI schemes on Apple Vision Pro / visionOS 27 and Apple Watch Series 12 (42 mm and 46 mm) / watchOS 27. The iOS archive embeds `MonkeytailWatch`; the Watch companion is distributed with iOS, not as a separate App Store platform. The iPhone test scheme includes Watch transfer/redaction checks. All release targets declare `ITSAppUsesNonExemptEncryption=false` and collect no data.

The pending iOS/Mac 1.2 submissions were canceled and replaced with 1.3 to include the Watch companion and shared favourites. Signed Cloud archives 43 (visionOS), 44 (Mac), and 45 (iOS/Watch) are processed as valid and all three platforms are Waiting for Review. Review states and submission links are recorded in [the release log](app-store/README.md). Cloud run 42 passed all 40 iOS hosted/UI tests at `e7e7920`. Run 46 passed native visionOS and both 42 mm/46 mm Watch UI flows, producing the 46 mm Watch store screenshot. GitHub run 37048779581 passed all 50 core/payload and nine Mac integration tests.

# App Store release

Monkeytail is free with no in-app purchases. The publisher is Kitta Co (Apple organization: Kitta Ltd). The app record is [6814706725](https://appstoreconnect.apple.com/apps/6814706725/distribution).

Version **1.0 (13)** is live on the App Store. It was resubmitted on September 22, 2026 and entered **Waiting for Review**. [Submission 72bc0389-c4f2-4811-8370-aac6a1d4eea7](https://appstoreconnect.apple.com/apps/6814706725/distribution/reviewsubmissions/details/72bc0389-c4f2-4811-8370-aac6a1d4eea7). It replaces the withdrawn build 10 submission and includes atomic response/preview publication, MIME-aware image/audio/video previews, and Hex/Binary viewers. Xcode Cloud archived and distributed commit `ecbd69a`; GitHub Actions passed. The release is configured to become available automatically after approval. App Review uses the same Kitta Co contact as DNSimple.

`metadata.json` is the English listing copy. It describes the supported interchange formats and script subset without claiming complete compatibility with other clients. Contact details stay in App Store Connect rather than this repository.

Screenshots are unedited captures from the actual native app using a loopback API fixture with sample content. The iPhone 18 Pro Max images are 1320 × 2868 for the 6.9-inch slot; iPad Pro 13-inch images are 2064 × 2752. The automated send, JSON inspection, cURL import, header editing, sharing, and rotation flow passed on both devices.

No analytics or tracking SDKs are included. App Privacy: Data Not Collected. Privacy URL: https://docs.kitta.co/monkeytail/privacy/.

Version **1.1** adds optional iCloud Drive workspace sync, multipart/file uploads, transport diagnostics, and response snapshots/comparison/JSONPath. Release tests passed on iPhone iOS 27. Credentials use the local Keychain, and sync excludes secret values and file bytes by default. `ITSAppUsesNonExemptEncryption` remains false.

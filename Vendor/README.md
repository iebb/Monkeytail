# Browser transport dependency

`CurlImpersonate.xcframework` contains static libraries from the official [lexiforest/curl-impersonate v2.2.3 release](https://github.com/lexiforest/curl-impersonate/releases/tag/v2.2.3), published 16 September 2026. The library includes its BoringSSL and HTTP/2 dependencies. The Swift package links it through the small `MonkeytailCurl` C target.

Included slices:

- iOS device: arm64
- iOS Simulator: arm64 and x86_64
- macOS: arm64 and x86_64, for Swift package verification

The checked-in XCFramework is about 45 MB. Only the matching platform/architecture is linked into a build; the other slices are not shipped inside the app. Debug information is stripped; source code is not patched. No binaries are fetched at build time or at runtime.

## Regenerate

On macOS with Xcode installed:

```sh
python3 Scripts/vendor_curl.py
```

The script downloads five pinned release archives, verifies their SHA-256 digests, strips debug symbols, combines simulator/macOS architectures using `lipo`, and creates the XCFramework. The cache is under the system temporary directory. Digests are checked before extraction:

| Archive platform | SHA-256 |
| --- | --- |
| arm64-apple-ios | `638e2efa7e7eae76da88108961b281561d354b740b0ea091ffc093f3beaef0c6` |
| arm64-apple-ios-simulator | `3540593300b515c7a0bec9b2c8123d151f777b9451bc03e1c7a9512306998621` |
| x86_64-apple-ios-simulator | `d026e6f9ecba952a149458156d1a16f2c12a167041c41851c8b755127f484c21` |
| arm64-macos | `16a73c8dfc55cb8c2354f93f43525529d0df6cbfc484fb7a4357b3891f9dbb6a` |
| x86_64-macos | `32634096e31e879d0a193f87e4a4083e2eb44b9b9318eb5b32f85f495104a049` |

`Scripts/vendor_curl.py` is the executable source of truth for the pinned version and hashes. Upgrading it also requires reviewing the supported profiles and the wire-level integration tests.

## Licenses

All `LICENSE*` files in the upstream device archive are concatenated verbatim into [ThirdPartyNotices.txt](../Sources/MonkeytailCore/Resources/ThirdPartyNotices.txt), bundled as a Swift package resource and available in the app under **Settings → Open source licenses**. This covers curl-impersonate, curl, BoringSSL, and the bundled compression, DNS, HTTP/2, and HTTP/3 libraries. These components retain their own licenses; the application’s private repository license does not replace them.

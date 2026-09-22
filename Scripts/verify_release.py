#!/usr/bin/env python3
"""Validate the release identity, privacy declaration, and App Store icon."""
from pathlib import Path
import plistlib
import struct

root = Path(__file__).resolve().parent.parent
info = plistlib.loads((root / 'Monkeytail/Info.plist').read_bytes())
privacy = plistlib.loads((root / 'Monkeytail/PrivacyInfo.xcprivacy').read_bytes())
project = (root / 'Monkeytail.xcodeproj/project.pbxproj').read_text()
assert 'co.kitta.monkeytail' in project, 'Incorrect production bundle ID'
assert '7P8CLHDH5G' in project, 'Kitta signing team missing'
assert 'PrivacyInfo.xcprivacy' in project, 'Privacy manifest is not in the project'
# The browser transport bundles BoringSSL. Complete Apple's questionnaire for
# each uploaded build instead of carrying forward the URLSession-only exemption.
assert 'ITSAppUsesNonExemptEncryption' not in info, 'Resolve encryption requirements in App Store Connect for the bundled TLS library'
assert privacy['NSPrivacyTracking'] is False
assert privacy['NSPrivacyTrackingDomains'] == []
assert privacy['NSPrivacyCollectedDataTypes'] == []
icon = (root / 'Monkeytail/Assets.xcassets/AppIcon.appiconset/AppIcon.png').read_bytes()
assert icon[:8] == b'\x89PNG\r\n\x1a\n'
width, height, depth, colour = struct.unpack('>IIBB', icon[16:26])
assert (width, height) == (1024, 1024), 'App Store icon must be 1024 × 1024'
assert colour == 2, 'App Store icon must be RGB with no alpha channel'
print('Release identity, privacy manifest, encryption questionnaire requirement, and icon passed.')

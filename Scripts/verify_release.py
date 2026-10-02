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
# Developer classification: standard HTTPS/TLS use is exempt. This declaration
# means no non-exempt encryption; it does not disable HTTPS or certificate checks.
assert info['ITSAppUsesNonExemptEncryption'] is False
assert privacy['NSPrivacyTracking'] is False
assert privacy['NSPrivacyTrackingDomains'] == []
assert privacy['NSPrivacyCollectedDataTypes'] == []
icon = (root / 'Monkeytail/Assets.xcassets/AppIcon.appiconset/AppIcon.png').read_bytes()
assert icon[:8] == b'\x89PNG\r\n\x1a\n'
width, height, depth, colour = struct.unpack('>IIBB', icon[16:26])
assert (width, height) == (1024, 1024), 'App Store icon must be 1024 × 1024'
assert colour == 2, 'App Store icon must be RGB with no alpha channel'
mac_info = plistlib.loads((root / 'MonkeytailMac/Info.plist').read_bytes())
mac_entitlements = plistlib.loads((root / 'MonkeytailMac/Monkeytail.entitlements').read_bytes())
ios_entitlements = plistlib.loads((root / 'Monkeytail/Monkeytail.entitlements').read_bytes())
assert mac_info['ITSAppUsesNonExemptEncryption'] is False
assert mac_entitlements['com.apple.security.app-sandbox'] is True
assert mac_entitlements['com.apple.security.network.client'] is True
assert mac_entitlements['com.apple.security.network.server'] is True
for key in ['com.apple.developer.icloud-container-identifiers', 'com.apple.developer.ubiquity-container-identifiers']:
    assert mac_entitlements[key] == ios_entitlements[key], 'Platforms must share the production iCloud container'
assert 'MonkeytailMac' in project, 'Native Mac target missing'
for target in ['MonkeytailVision', 'MonkeytailWatch']:
    platform_info = plistlib.loads((root / target / 'Info.plist').read_bytes())
    assert platform_info['ITSAppUsesNonExemptEncryption'] is False
    assert target in project
watch_privacy = plistlib.loads((root / 'MonkeytailWatch/PrivacyInfo.xcprivacy').read_bytes())
assert watch_privacy['NSPrivacyCollectedDataTypes'] == [] and watch_privacy['NSPrivacyTracking'] is False
vision_entitlements = plistlib.loads((root / 'MonkeytailVision/Monkeytail.entitlements').read_bytes())
for key in ['com.apple.developer.icloud-container-identifiers', 'com.apple.developer.ubiquity-container-identifiers']:
    assert vision_entitlements[key] == ios_entitlements[key]
assert (root / 'Packages/MonkeytailSystemCore/Sources/MonkeytailSystemCore').resolve() == root / 'Sources/MonkeytailCore'
assert (root / 'Packages/MonkeytailWatchCore/Sources/MonkeytailWatchCore').resolve() == root / 'Sources/MonkeytailCompanion'
print('Four-platform identity, shared iCloud, Mac sandbox, privacy, encryption declarations, icon, and canonical shared sources passed.')

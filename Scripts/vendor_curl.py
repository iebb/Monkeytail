#!/usr/bin/env python3
"""Repackage verified upstream static archives; run on macOS with Xcode installed."""
import hashlib
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

VERSION = '2.2.3'
ARCHIVES = {
    'arm64-apple-ios': '638e2efa7e7eae76da88108961b281561d354b740b0ea091ffc093f3beaef0c6',
    'arm64-apple-ios-simulator': '3540593300b515c7a0bec9b2c8123d151f777b9451bc03e1c7a9512306998621',
    'x86_64-apple-ios-simulator': 'd026e6f9ecba952a149458156d1a16f2c12a167041c41851c8b755127f484c21',
    'arm64-macos': '16a73c8dfc55cb8c2354f93f43525529d0df6cbfc484fb7a4357b3891f9dbb6a',
    'x86_64-macos': '32634096e31e879d0a193f87e4a4083e2eb44b9b9318eb5b32f85f495104a049',
}
ROOT = Path(__file__).resolve().parent.parent
CACHE = Path(tempfile.gettempdir()) / f'monkeytail-curl-v{VERSION}'
CACHE.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='monkeytail-curl-package-') as work:
    work = Path(work)
    for platform, digest in ARCHIVES.items():
        name = f'libcurl-impersonate-v{VERSION}.{platform}.tar.gz'
        archive = CACHE / name
        if not archive.exists():
            url = f'https://github.com/lexiforest/curl-impersonate/releases/download/v{VERSION}/{name}'
            with urllib.request.urlopen(url, timeout=120) as response:
                archive.write_bytes(response.read())
        if hashlib.sha256(archive.read_bytes()).hexdigest() != digest:
            raise ValueError(f'Checksum mismatch: {name}')
        target = work / platform
        with tarfile.open(archive) as source:
            # Extract only regular static-library, header, and license files.
            for member in source.getmembers():
                if member.isfile() and (member.name == 'libcurl-impersonate.a' or member.name.startswith(('include/curl/', 'LICENSE'))):
                    if '..' in Path(member.name).parts or Path(member.name).is_absolute():
                        raise ValueError(f'Unsafe archive path: {member.name}')
                    dest = target / member.name
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    dest.write_bytes(source.extractfile(member).read())
        subprocess.run(['xcrun', 'strip', '-S', str(target / 'libcurl-impersonate.a')], check=True)
    headers = work / 'arm64-apple-ios/include'
    (headers / 'module.modulemap').write_text('module CurlImpersonate [system] {\n  header "curl/curl.h"\n  export *\n}\n')
    libraries = [work / 'arm64-apple-ios/libcurl-impersonate.a']
    for platform, arches in [('simulator', ['arm64-apple-ios-simulator', 'x86_64-apple-ios-simulator']), ('macos', ['arm64-macos', 'x86_64-macos'])]:
        output = work / platform / 'libcurl-impersonate.a'
        output.parent.mkdir()
        subprocess.run(['xcrun', 'lipo', '-create', *[str(work / arch / 'libcurl-impersonate.a') for arch in arches], '-output', str(output)], check=True)
        libraries.append(output)
    output = ROOT / 'Vendor/CurlImpersonate.xcframework'
    if output.exists(): shutil.rmtree(output)
    command = ['xcodebuild', '-create-xcframework']
    for library in libraries: command += ['-library', str(library), '-headers', str(headers)]
    subprocess.run(command + ['-output', str(output)], check=True)
    licenses = sorted((work / 'arm64-apple-ios').glob('LICENSE*'))
    notices = '\n\n'.join(f'{p.name}\n{"=" * 72}\n{p.read_text()}' for p in licenses)
    (ROOT / 'Sources/MonkeytailCore/Resources/ThirdPartyNotices.txt').write_text(notices)
print('Vendored curl-impersonate', VERSION)

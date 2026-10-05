#!/usr/bin/env python3
"""Negative checks execute the exact Python validators embedded in the release script.
These checks cover release-gate parsing and policy, not cryptographic signature forging.
Final macOS signature, ticket and Gatekeeper validation uses the full release script.
"""
import pathlib
import plistlib
import re
import stat
import sys
import subprocess
import tempfile
import zipfile
import warnings

project = pathlib.Path(__file__).resolve().parents[1]
source = (project / 'Scripts/verify-release.sh').read_text()
count = 0
positive_count = 0
negative_count = 0
bundle = plistlib.loads((project / 'Config/Info.plist').read_bytes())
version = bundle['CFBundleShortVersionString']
build = bundle['CFBundleVersion']
product_id = bundle['CFBundleIdentifier']
app_name = bundle['CFBundleName'] + '.app'
zip_name = 'Password.Generator-' + version + '.zip'

def program(marker):
    pattern = r'# BEGIN_RELEASE_' + re.escape(marker) + r'_VALIDATION\n.*?<<\x27PY\x27\n(.*?)\nPY'
    match = re.search(pattern, source, re.S)
    if match is None:
        raise AssertionError("Missing release validator: " + marker)
    return match.group(1)

def check(label, marker, args, succeeds):
    global count, positive_count, negative_count
    result = subprocess.run([sys.executable, '-', *map(str, args)], input=program(marker), text=True, capture_output=True)
    if (result.returncode == 0) != succeeds:
        raise AssertionError((label, result.returncode, result.stdout, result.stderr))
    count += 1
    if succeeds: positive_count += 1
    else: negative_count += 1
    print(('PASS positive: ' if succeeds else 'PASS rejects: ') + label)

with tempfile.TemporaryDirectory(prefix='password-generator-release-gate-') as temporary:
    base = pathlib.Path(temporary)
    app = base / app_name
    (app / 'Contents').mkdir(parents=True)
    metadata = {
        'CFBundleIdentifier': product_id,
        'CFBundleShortVersionString': version,
        'CFBundleVersion': build,
        'CFBundleExecutable': 'PasswordGeneratorApp',
    }
    info_path = app / 'Contents/Info.plist'
    info_path.write_bytes(plistlib.dumps(metadata))
    signature = '\n'.join([
        'Identifier=local.passwordgenerator.generator',
        'CodeDirectory v=20500 size=4077 flags=0x10000(runtime) hashes=116+7 location=embedded',
        'Authority=Developer ID Application: Michael Feinermann (2T6K9PGS55)',
        'Authority=Developer ID Certification Authority',
        'Authority=Apple Root CA',
        'TeamIdentifier=2T6K9PGS55',
    ])
    check('expected Developer ID identity and runtime', 'IDENTITY', [app, 'developer-id-notarized', signature], True)
    development_signature = '\n'.join([
        'Identifier=local.passwordgenerator.generator',
        'CodeDirectory v=20500 flags=0x10000(runtime) hashes=1',
        'Signature=adhoc',
        'TeamIdentifier=not set',
    ])
    check('explicit ad-hoc development signature', 'IDENTITY', [app, 'local-ad-hoc', development_signature], True)
    for label, modified in [
        ('wrong signing team', signature.replace('TeamIdentifier=2T6K9PGS55', 'TeamIdentifier=OTHERTEAM12')),
        ('wrong signing authority', signature.replace('Authority=Developer ID Application:', 'Authority=Apple Development:')),
        ('wrong authority team', signature.replace(' (2T6K9PGS55)', ' (OTHERTEAM12)')),
        ('missing Developer ID authority', '\n'.join(line for line in signature.splitlines() if not line.startswith('Authority='))),
        ('missing hardened runtime', signature.replace('flags=0x10000(runtime)', 'flags=0x0(none)')),
        ('missing signature flags', signature.replace('flags=0x10000(runtime)', '')),
        ('different signed product', signature.replace('Identifier=local.passwordgenerator.generator', 'Identifier=local.other.app')),
        ('duplicate identity', signature + '\nIdentifier=local.passwordgenerator.generator'),
        ('ad-hoc signature as a public release', 'Identifier=local.passwordgenerator.generator\nCodeDirectory v=20500 flags=0x10000(runtime) hashes=1\nSignature=adhoc\nTeamIdentifier=not set'),
    ]:
        check(label, 'IDENTITY', [app, 'developer-id-notarized', modified], False)
    for key in metadata:
        modified = dict(metadata)
        modified[key] = 'unexpected-value'
        info_path.write_bytes(plistlib.dumps(modified))
        check('wrong bundle ' + key, 'IDENTITY', [app, 'developer-id-notarized', signature], False)
    info_path.write_bytes(plistlib.dumps(metadata))
    manifest_fields = {
        'artifact': zip_name,
        'coverage': 'complete-signed-app-archive',
        'bundle-identifier': product_id,
        'bundle-version': version,
        'bundle-build': build,
        'architecture': 'arm64',
        'minimum-macos': '14.0',
        'signature-mode': 'developer-id-notarized',
        'sha256': 'a' * 64,
        'sha3-512': 'b' * 128,
        'skein-1024-1024': 'c' * 256,
    }
    manifest = base / 'integrity.txt'
    def save_manifest(fields):
        manifest.write_text('Password Generator Release Integrity Manifest v1\n' + '\n'.join(key + '=' + value for key, value in fields.items()) + '\n')
    save_manifest(manifest_fields)
    check('notarized public manifest', 'MANIFEST', [manifest, '0'], True)
    for mode in ['local-ad-hoc', 'developer-id', 'anything-else']:
        modified = dict(manifest_fields, **{'signature-mode': mode})
        save_manifest(modified)
        check('public manifest bypass with ' + mode, 'MANIFEST', [manifest, '0'], False)
    for mode in ['local-ad-hoc', 'developer-id']:
        save_manifest(dict(manifest_fields, **{'signature-mode': mode}))
        check('explicit unnotarized development opt-in for ' + mode, 'MANIFEST', [manifest, '1'], True)
    save_manifest(manifest_fields)
    manifest.write_text(manifest.read_text() + 'signature-mode=local-ad-hoc\n')
    check('duplicate manifest signature mode', 'MANIFEST', [manifest, '0'], False)
    save_manifest(dict(manifest_fields, **{'bundle-build': 'wrong-build'}))
    check('manifest build mismatch', 'MANIFEST', [manifest, '0'], False)
    save_manifest(dict(manifest_fields, **{'sha3-512': 'not-a-hash'}))
    check('invalid manifest digest', 'MANIFEST', [manifest, '0'], False)
    entitlements = {'com.apple.security.app-sandbox': True}
    def xml(fields): return plistlib.dumps(fields).decode()
    check('sandbox-only entitlements', 'ENTITLEMENTS', [xml(entitlements)], True)
    identity_entitlements = dict(entitlements, **{
        'com.apple.application-identifier': '2T6K9PGS55.local.passwordgenerator.generator',
        'com.apple.developer.team-identifier': '2T6K9PGS55',
    })
    check('allowed identity-only entitlement extension', 'ENTITLEMENTS', [xml(identity_entitlements)], True)
    check('disabled sandbox', 'ENTITLEMENTS', [xml({'com.apple.security.app-sandbox': False})], False)
    for capability in [
        'com.apple.security.network.client', 'com.apple.security.network.server',
        'com.apple.security.cs.allow-unsigned-executable-memory',
        'com.apple.security.cs.disable-library-validation',
        'com.apple.security.cs.allow-jit', 'com.apple.security.get-task-allow',
        'com.apple.security.files.user-selected.read-write',
    ]:
        check(capability, 'ENTITLEMENTS', [xml(dict(entitlements, **{capability: True}))], False)
    check('wrong identity entitlement team', 'ENTITLEMENTS', [xml(dict(identity_entitlements, **{'com.apple.developer.team-identifier': 'OTHERTEAM12'}))], False)
    check('wrong identity entitlement product', 'ENTITLEMENTS', [xml(dict(identity_entitlements, **{'com.apple.application-identifier': '2T6K9PGS55.local.other.app'}))], False)
    archive = base / 'archive.zip'
    def save_archive(names):
        with zipfile.ZipFile(archive, 'w') as output:
            for name in names: output.writestr(name, b'test')
    save_archive([app_name + '/', app_name + '/Contents/', app_name + '/Contents/Info.plist', '__MACOSX/', '__MACOSX/' + app_name + '/', '__MACOSX/._' + app_name, '__MACOSX/' + app_name + '/Contents/._Info.plist'])
    check('regular expected app and AppleDouble metadata', 'ARCHIVE', [archive], True)
    for name in ['../escape', '/absolute/path', app_name + '/../../escape', 'Other.app/Contents/Info.plist', '__MACOSX/Other.app/Contents/test', app_name + '/Contents\\escape', app_name + '/./Contents/Info.plist', app_name + '//Contents/Info.plist']:
        save_archive([name])
        check('unsafe archive path ' + name, 'ARCHIVE', [archive], False)
    with zipfile.ZipFile(archive, 'w') as output:
        link = zipfile.ZipInfo(app_name + '/Contents/link')
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        output.writestr(link, '../../outside')
    check('symlink payload', 'ARCHIVE', [archive], False)
    with zipfile.ZipFile(archive, 'w') as output:
        pipe = zipfile.ZipInfo(app_name + '/Contents/pipe')
        pipe.create_system = 3
        pipe.external_attr = (stat.S_IFIFO | 0o600) << 16
        output.writestr(pipe, b'')
    check('special-file payload', 'ARCHIVE', [archive], False)
    with warnings.catch_warnings():
        warnings.simplefilter('ignore', UserWarning)
        save_archive([app_name + '/Contents/Info.plist', app_name + '/Contents/Info.plist'])
    check('duplicate archive entry', 'ARCHIVE', [archive], False)
print(f'{count} release-gate checks passed: {positive_count} positive and {negative_count} negative checks.')

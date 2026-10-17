"""Prepare only runner-owned artifacts; never changes installed/release apps."""
import hashlib, json, pathlib, plistlib, shutil, subprocess, sys
derived, destination, fixtures, test_run = map(pathlib.Path, sys.argv[1:])
root = pathlib.Path.cwd().resolve()
assert derived == pathlib.Path('/tmp/exp-a11y-derived')
for value in [destination, fixtures, test_run]:
    assert value.resolve().is_relative_to(root / 'output/a11y'), 'Runner-owned output required'
source = derived / 'Build/Products/Debug/EXP [design].app'
assert source.is_dir()
assert not destination.exists(), 'Refuse overwriting a previous app fixture'
shutil.copytree(source, destination, symlinks=True)
# Thumbnail/helper integration is covered by release checks, not this isolated
# editor test. Removing them here prevents accidental registration of production
# extension IDs or Sanaa provider/bridge execution from a test copy.
for child in ['Contents/PlugIns', 'Contents/Helpers']:
    shutil.rmtree(destination / child, ignore_errors=True)
info = destination / 'Contents/Info.plist'
with info.open('rb') as file: data = plistlib.load(file)
bundle_id = 'design.tapps.exp.a11y-fixture.' + hashlib.sha256(str(destination).encode()).hexdigest()[:10]
data['CFBundleIdentifier'] = bundle_id
data['CFBundleDisplayName'] = 'EXP Accessibility Fixture'
for key in ['CFBundleDocumentTypes', 'UTExportedTypeDeclarations', 'UTImportedTypeDeclarations']:
    data.pop(key, None)  # Never takes over the owner's .design file association.
with info.open('wb') as file: plistlib.dump(data, file)
entitlements = fixtures.parent / 'fixture.entitlements.plist'
with entitlements.open('wb') as file:
    plistlib.dump({'com.apple.security.app-sandbox': True, 'com.apple.security.files.user-selected.read-write': True}, file)
# No outgoing network entitlement, Codex exception, or app-group/keychain sharing.
subprocess.run(['codesign', '--force', '--deep', '--sign', '-', '--entitlements', str(entitlements), str(destination)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(destination)], check=True)
files = list((derived / 'Build/Products').glob('*.xctestrun'))
assert len(files) == 1, 'Expected one accessibility test configuration'
with files[0].open('rb') as file: config = plistlib.load(file)
runner = destination.parent / 'EXPAccessibilityUITests-Runner.app'
shutil.copytree(derived / 'Build/Products/Debug/EXPAccessibilityUITests-Runner.app', runner, symlinks=True)
# CODE_SIGNING_ALLOWED=NO leaves Xcode's stock runner signature inconsistent
# with its generated Info.plist/test bundle. Sign only this disposable copy.
subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(runner)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(runner)], check=True)
def rewrite(value):
    if isinstance(value, dict):
        if 'TestBundlePath' in value:
            value.setdefault('EnvironmentVariables', {}).update({'EXP_A11Y_APP_PATH': str(destination), 'EXP_A11Y_FIXTURE_DIR': str(fixtures)})
            value['EnvironmentVariables']['EXP_A11Y_BUNDLE_ID'] = bundle_id
            value['UITargetAppPath'] = str(destination)
            value['UITargetAppBundleIdentifier'] = bundle_id
            value['TestHostPath'] = str(runner)
            value['PreferredScreenCaptureFormat'] = 'screenshot'
        for item in value.values(): rewrite(item)
    elif isinstance(value, list):
        for item in value: rewrite(item)
rewrite(config)
# __TESTROOT__ originally referred to Build/Products. Preserve that expansion even
# though this configured xctestrun lives alongside the report.
def paths(value):
    if isinstance(value, str): return value.replace('__TESTROOT__', str(derived / 'Build/Products'))
    if isinstance(value, list): return [paths(item) for item in value]
    if isinstance(value, dict): return {key: paths(item) for key, item in value.items()}
    return value
with test_run.open('wb') as file: plistlib.dump(paths(config), file)
(destination.parent / 'identity.json').write_text(json.dumps({'bundleID': bundle_id}))

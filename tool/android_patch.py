#!/usr/bin/env python3
"""Apply the Android configuration Kurayomi needs to a generated project.

Kept separate from bootstrap.sh so it can be unit-tested and re-run on its
own. Every change is idempotent.
"""
import pathlib
import re
import sys

# AGP 9 removed getDefaultProguardFile('proguard-android.txt'), which the
# released flutter_inappwebview_android still calls (fixed upstream, not yet
# in a stable release). AGP 9 also switches on the new DSL, which the current
# Flutter Gradle plugin cannot apply.
#
# So pin to the newest AGP 8.x line, which accepts both. The Gradle pin must
# stay at or above Flutter's own minimum (8.14 as of Flutter 3.47) or the
# Flutter Gradle plugin refuses to load.
AGP_PIN = '8.11.1'
GRADLE_PIN = '8.14.3'

PERMISSIONS = [
    'android.permission.INTERNET',
    'android.permission.WAKE_LOCK',
    'android.permission.ACCESS_NETWORK_STATE',
]

APPLICATION_ATTRS = [
    # Many sources and image CDNs are still plain http://
    ('usesCleartextTraffic', 'android:usesCleartextTraffic="true"'),
    # WebView challenge pages render incorrectly without it
    ('hardwareAccelerated', 'android:hardwareAccelerated="true"'),
]


def patch_manifest() -> None:
    path = pathlib.Path('android/app/src/main/AndroidManifest.xml')
    if not path.exists():
        sys.exit('error: AndroidManifest.xml not found — run flutter create first')

    s = path.read_text()
    changed = []

    block = ''.join(
        f'    <uses-permission android:name="{p}"/>\n'
        for p in PERMISSIONS if p not in s
    )
    if block:
        s = re.sub(r'(<manifest[^>]*>\s*\n)', r'\1' + block, s, count=1)
        changed.append('permissions')

    for marker, attr in APPLICATION_ATTRS:
        if marker not in s:
            s = s.replace('<application', f'<application\n        {attr}', 1)
            changed.append(marker)

    path.write_text(s)
    print('   manifest: ' + (', '.join(changed) if changed else 'already configured'))


def patch_min_sdk() -> None:
    for name in ('android/app/build.gradle.kts', 'android/app/build.gradle'):
        f = pathlib.Path(name)
        if not f.exists():
            continue
        s = f.read_text()
        m = re.search(r'minSdk\s*=?\s*(\d+)', s)
        if m and int(m.group(1)) < 21:
            f.write_text(re.sub(r'(minSdk\s*=?\s*)\d+', r'\g<1>21', s))
            print(f'   {name}: minSdk raised to 21 (media_kit requirement)')
        else:
            found = m.group(1) if m else 'inherited from Flutter'
            print(f'   {name}: minSdk OK ({found})')
        return


def patch_agp() -> None:
    settings = pathlib.Path('android/settings.gradle.kts')
    if not settings.exists():
        settings = pathlib.Path('android/settings.gradle')
    if not settings.exists():
        print('   settings.gradle not found, skipping AGP check')
        return

    s = settings.read_text()
    m = re.search(
        r'id\s*\(?["\']com\.android\.application["\']\)?\s+version\s+["\']([^"\']+)["\']',
        s,
    )
    if not m:
        print('   could not find the AGP version declaration, skipping')
        return

    current = m.group(1)
    major = int(current.split('.')[0])
    print(f'   AGP in template: {current}')

    if major < 9:
        print('   AGP is compatible, leaving it alone')
        return

    s = s.replace(f'version "{current}"', f'version "{AGP_PIN}"')
    s = s.replace(f"version '{current}'", f"version '{AGP_PIN}'")
    settings.write_text(s)
    print(f'   AGP pinned to {AGP_PIN} '
          f'(AGP 9 breaks flutter_inappwebview_android)')

    wrapper = pathlib.Path('android/gradle/wrapper/gradle-wrapper.properties')
    if wrapper.exists():
        w = wrapper.read_text()
        new = re.sub(r'gradle-[0-9.]+-(bin|all)\.zip',
                     f'gradle-{GRADLE_PIN}-bin.zip', w)
        if new != w:
            wrapper.write_text(new)
            print(f'   Gradle wrapper pinned to {GRADLE_PIN}')


def main() -> None:
    patch_manifest()
    patch_min_sdk()
    patch_agp()


if __name__ == '__main__':
    main()

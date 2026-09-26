#!/usr/bin/env bash
# Generates the android/ platform folder (which is not committed) and applies
# the few customisations Kuroyomi needs. Safe to run repeatedly.
set -euo pipefail

APP_ID="${APP_ID:-com.kuroyomi.app}"
APP_LABEL="${APP_LABEL:-Kuroyomi}"
MIN_SDK="${MIN_SDK:-23}"

cd "$(dirname "$0")/.."

if [ ! -d android ]; then
  echo "==> Generating android/ scaffolding"
  TMP_DIR="$(mktemp -d)"
  flutter create --platforms=android --org com.kuroyomi --project-name kuroyomi "$TMP_DIR/scaffold" >/dev/null
  cp -r "$TMP_DIR/scaffold/android" ./android
  rm -rf "$TMP_DIR"
else
  echo "==> Reusing existing android/ folder"
fi

echo "==> Patching android project (id=$APP_ID label=$APP_LABEL minSdk=$MIN_SDK)"
APP_ID="$APP_ID" APP_LABEL="$APP_LABEL" MIN_SDK="$MIN_SDK" python3 - <<'PYEOF'
import os
import re
import sys
import xml.etree.ElementTree as ET

app_id = os.environ["APP_ID"]
app_label = os.environ["APP_LABEL"]
min_sdk = os.environ["MIN_SDK"]

PERMISSIONS = ("android.permission.INTERNET", "android.permission.ACCESS_NETWORK_STATE")

# ----------------------------------------------------------- AndroidManifest
manifest_path = "android/app/src/main/AndroidManifest.xml"
manifest = open(manifest_path, encoding="utf-8").read()

# Insert permissions immediately after the opening <manifest ...> tag.
opening = re.search(r"<manifest\b[^>]*>", manifest)
if opening is None:
    sys.exit("could not find the <manifest> tag")

insert_at = opening.end()
additions = ""
for permission in PERMISSIONS:
    if permission not in manifest:
        additions += '\n    <uses-permission android:name="' + permission + '" />'
manifest = manifest[:insert_at] + additions + manifest[insert_at:]

# App name shown in the launcher.
manifest = re.sub(
    r'android:label="[^"]*"',
    lambda _: 'android:label="' + app_label + '"',
    manifest,
    count=1,
)

# Some sources still serve plain http images.
if "usesCleartextTraffic" not in manifest:
    manifest = manifest.replace(
        "<application",
        '<application\n        android:usesCleartextTraffic="true"',
        1,
    )

# Never write a manifest that would break the build.
try:
    ET.fromstring(manifest)
except ET.ParseError as error:
    print(manifest)
    sys.exit("patched manifest is not valid XML: %s" % error)

open(manifest_path, "w", encoding="utf-8").write(manifest)
print("    manifest patched and validated")
print("---------- AndroidManifest.xml ----------")
print(manifest)
print("-----------------------------------------")

# ------------------------------------------------------------ app build file
candidates = [p for p in ("android/app/build.gradle.kts", "android/app/build.gradle") if os.path.exists(p)]
if not candidates:
    sys.exit("could not find android/app/build.gradle[.kts]")

for path in candidates:
    gradle = open(path, encoding="utf-8").read()
    gradle = re.sub(r'applicationId\s*=\s*"[^"]*"', 'applicationId = "' + app_id + '"', gradle)
    gradle = re.sub(r'applicationId\s+"[^"]*"', 'applicationId "' + app_id + '"', gradle)
    gradle = re.sub(r"minSdk\s*=\s*[A-Za-z0-9_.]+", "minSdk = " + min_sdk, gradle)
    gradle = re.sub(r"minSdkVersion\s+[A-Za-z0-9_.]+", "minSdkVersion " + min_sdk, gradle)
    open(path, "w", encoding="utf-8").write(gradle)
    print("    gradle patched: %s" % path)
PYEOF

echo "==> Android project ready"

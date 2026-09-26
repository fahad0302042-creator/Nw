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
APP_ID="$APP_ID" APP_LABEL="$APP_LABEL" MIN_SDK="$MIN_SDK" python3 - <<'PY'
import os
import re
import glob

app_id = os.environ["APP_ID"]
app_label = os.environ["APP_LABEL"]
min_sdk = os.environ["MIN_SDK"]

# ----------------------------------------------------------- AndroidManifest
manifest_path = "android/app/src/main/AndroidManifest.xml"
with open(manifest_path) as fh:
    manifest = fh.read()

if "android.permission.INTERNET" not in manifest:
    manifest = manifest.replace(
        "<manifest",
        '<manifest',
        1,
    )
    # insert permissions right after the opening <manifest ...> tag
    manifest = re.sub(
        r"(<manifest[^>]*>)",
        r"\1\n    <uses-permission android:name=\"android.permission.INTERNET\" />"
        "\n    <uses-permission android:name=\"android.permission.ACCESS_NETWORK_STATE\" />",
        manifest,
        count=1,
    )

manifest = re.sub(r'android:label="[^"]*"', f'android:label="{app_label}"', manifest, count=1)

if "usesCleartextTraffic" not in manifest:
    manifest = manifest.replace(
        "<application",
        '<application\n        android:usesCleartextTraffic="true"',
        1,
    )

with open(manifest_path, "w") as fh:
    fh.write(manifest)
print(f"    manifest patched: {manifest_path}")

# ------------------------------------------------------------ app build file
candidates = [p for p in ("android/app/build.gradle.kts", "android/app/build.gradle") if os.path.exists(p)]
for path in candidates:
    with open(path) as fh:
        gradle = fh.read()

    # applicationId (kts uses `applicationId = "x"`, groovy uses `applicationId "x"`)
    gradle = re.sub(r'applicationId\s*=\s*"[^"]*"', f'applicationId = "{app_id}"', gradle)
    gradle = re.sub(r'applicationId\s+"[^"]*"', f'applicationId "{app_id}"', gradle)

    # minSdk: plugins such as video_player need a modern baseline
    gradle = re.sub(r'minSdk\s*=\s*[A-Za-z0-9_.]+', f'minSdk = {min_sdk}', gradle)
    gradle = re.sub(r'minSdkVersion\s+[A-Za-z0-9_.]+', f'minSdkVersion {min_sdk}', gradle)

    with open(path, "w") as fh:
        fh.write(gradle)
    print(f"    gradle patched: {path}")

if not candidates:
    raise SystemExit("could not find android/app/build.gradle[.kts]")
PY

echo "==> Android project ready"

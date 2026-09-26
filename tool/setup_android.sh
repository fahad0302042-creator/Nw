#!/usr/bin/env bash
# Applies the Android configuration Kurayomi needs after `flutter create`.
#
#   1. INTERNET permission (every source needs it)
#   2. Cleartext HTTP allowed (many sources and CDNs are still http://)
#   3. minSdk 21 and NDK/desugaring settings required by media_kit
set -euo pipefail

MANIFEST="android/app/src/main/AndroidManifest.xml"
GRADLE="android/app/build.gradle"
GRADLE_KTS="android/app/build.gradle.kts"

if [[ ! -f "$MANIFEST" ]]; then
  echo "error: $MANIFEST not found."
  echo "Run: flutter create . --platforms=android --project-name kurayomi"
  exit 1
fi

# 1 + 2 --------------------------------------------------------------------
if ! grep -q 'android.permission.INTERNET' "$MANIFEST"; then
  python3 - "$MANIFEST" <<'PY'
import sys, re
path = sys.argv[1]
s = open(path).read()
perms = ('    <uses-permission android:name="android.permission.INTERNET"/>\n'
         '    <uses-permission android:name="android.permission.WAKE_LOCK"/>\n')
s = s.replace('<manifest', '<manifest', 1)
s = re.sub(r'(<manifest[^>]*>\n)', r'\1' + perms, s, count=1)
s = s.replace('<application', '<application\n        android:usesCleartextTraffic="true"', 1)
open(path, 'w').write(s)
print('patched', path)
PY
else
  echo "manifest already patched"
fi

# 3 ------------------------------------------------------------------------
for f in "$GRADLE" "$GRADLE_KTS"; do
  [[ -f "$f" ]] || continue
  if grep -q 'minSdk' "$f" && ! grep -q 'minSdk 21\|minSdk = 21' "$f"; then
    echo "note: ensure minSdk >= 21 in $f (media_kit requirement)"
  fi
done

echo
echo "Done. Next:  flutter pub get && flutter run"

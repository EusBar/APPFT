#!/usr/bin/env bash
# Ajusta as pastas android/ e ios/ geradas por `flutter create`.
# Corre no CI depois de `flutter create`; é idempotente.
set -euo pipefail
cd "$(dirname "$0")/.."

# --- Android -----------------------------------------------------------------
manifest=android/app/src/main/AndroidManifest.xml
sed -i 's/android:label="fintrack"/android:label="FINTRACK"/' "$manifest"
grep -q 'USE_BIOMETRIC' "$manifest" || sed -i \
  's#<application#<uses-permission android:name="android.permission.USE_BIOMETRIC"/>\n    <application#' "$manifest"
# Sem cópias de segurança automáticas da base local (os dados ficam no aparelho).
grep -q 'android:allowBackup' "$manifest" || sed -i \
  's#<application#<application android:allowBackup="false" android:fullBackupContent="false"#' "$manifest"

gradle=android/app/build.gradle.kts
sed -i -E 's/minSdk = flutter\.minSdkVersion/minSdk = maxOf(flutter.minSdkVersion, 24)/' "$gradle"

# --- iOS ---------------------------------------------------------------------
plist=ios/Runner/Info.plist
if ! grep -q NSFaceIDUsageDescription "$plist"; then
  sed -i '0,/<dict>/s#<dict>#<dict>\n\t<key>NSFaceIDUsageDescription</key>\n\t<string>Desbloquear o FINTRACK com o rosto.</string>#' "$plist"
fi
perl -0pi -e 's#(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)#${1}FINTRACK${2}#' "$plist"

echo "Plataformas configuradas."

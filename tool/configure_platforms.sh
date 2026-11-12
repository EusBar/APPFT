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

# A biometria (biometric_storage) exige FlutterFragmentActivity.
main_activity=$(find android/app/src/main -name MainActivity.kt | head -1)
package=$(sed -n 's/^package \(.*\)$/\1/p' "$main_activity")
cat > "$main_activity" <<KT
package $package

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
KT

# Tema AppCompat (evita falhas da biometria em Android < 10).
for styles in android/app/src/main/res/values/styles.xml android/app/src/main/res/values-night/styles.xml; do
  sed -i -E 's#parent="@android:style/Theme\.[A-Za-z.]+"#parent="Theme.AppCompat.NoActionBar"#g' "$styles"
done

gradle=android/app/build.gradle.kts
sed -i -E 's/minSdk = flutter\.minSdkVersion/minSdk = maxOf(flutter.minSdkVersion, 24)/' "$gradle"
grep -q 'androidx.appcompat:appcompat' "$gradle" || cat >> "$gradle" <<'GRADLE'

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.1")
}
GRADLE

# --- iOS ---------------------------------------------------------------------
plist=ios/Runner/Info.plist
if ! grep -q NSFaceIDUsageDescription "$plist"; then
  sed -i '0,/<dict>/s#<dict>#<dict>\n\t<key>NSFaceIDUsageDescription</key>\n\t<string>Desbloquear o FINTRACK com o rosto.</string>#' "$plist"
fi
perl -0pi -e 's#(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)#${1}FINTRACK${2}#' "$plist"

echo "Plataformas configuradas."

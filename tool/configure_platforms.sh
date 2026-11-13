#!/usr/bin/env bash
# Ajusta as pastas android/ e ios/ geradas por `flutter create`.
# Corre no CI depois de `flutter create`; é idempotente.
set -euo pipefail
cd "$(dirname "$0")/.."

# --- Android -----------------------------------------------------------------
manifest=android/app/src/main/AndroidManifest.xml
sed -i 's/android:label="fintrack"/android:label="FINTRACK"/' "$manifest"
# Acesso à Internet (conta e sincronização). O modelo do Flutter só o declara
# nas versões de depuração, não na versão final.
grep -q 'android.permission.INTERNET' "$manifest" || sed -i \
  's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$manifest"
grep -q 'USE_BIOMETRIC' "$manifest" || sed -i \
  's#<application#<uses-permission android:name="android.permission.USE_BIOMETRIC"/>\n    <application#' "$manifest"
# Sem cópias de segurança automáticas da base local (os dados ficam no aparelho).
grep -q 'android:allowBackup' "$manifest" || sed -i \
  's#<application#<application android:allowBackup="false" android:fullBackupContent="false"#' "$manifest"

# Uma única janela: o modelo do Flutter usa taskAffinity="" e singleTop, o que
# abre tarefas separadas consoante a origem (instalador, ícone, partilha).
sed -i 's/ android:taskAffinity=""//; s/android:taskAffinity=""//' "$manifest"
sed -i 's/android:launchMode="singleTop"/android:launchMode="singleTask"/' "$manifest"
grep -n 'launchMode\|taskAffinity' "$manifest" || true

gradle=android/app/build.gradle.kts
sed -i -E 's/minSdk = flutter\.minSdkVersion/minSdk = maxOf(flutter.minSdkVersion, 24)/' "$gradle"

python3 tool/configure_android.py

# --- iOS ---------------------------------------------------------------------
plist=ios/Runner/Info.plist
if ! grep -q NSFaceIDUsageDescription "$plist"; then
  sed -i '0,/<dict>/s#<dict>#<dict>\n\t<key>NSFaceIDUsageDescription</key>\n\t<string>Desbloquear o FINTRACK com o rosto.</string>#' "$plist"
fi
perl -0pi -e 's#(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)#${1}FINTRACK${2}#' "$plist"

echo "Plataformas configuradas."

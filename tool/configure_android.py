#!/usr/bin/env python3
"""Requisitos Android dos lembretes (flutter_local_notifications):
compileSdk 37, desugaring e recetores para notificações agendadas.

Corre no CI depois de `flutter create`. Idempotente.
"""
import pathlib
import re

gradle = pathlib.Path("android/app/build.gradle.kts")
s = gradle.read_text()

s = re.sub(
    r"compileSdk = flutter\.compileSdkVersion",
    "compileSdk = maxOf(flutter.compileSdkVersion, 37)",
    s,
)
if "isCoreLibraryDesugaringEnabled" not in s:
    s, n = re.subn(r"compileOptions \{\n", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true\n", s, count=1)
    if n != 1:
        raise SystemExit("compileOptions não encontrado em build.gradle.kts")
if "desugar_jdk_libs" not in s:
    s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
# A verificação "lint" das bibliotecas encrava em algumas versões (erro
# interno do lint, não do código). Não é necessária para gerar o APK.
if "checkReleaseBuilds" not in s:
    s, n = re.subn(r"android \{\n", "android {\n    lint {\n        checkReleaseBuilds = false\n        abortOnError = false\n    }\n", s, count=1)
    if n != 1:
        raise SystemExit("bloco android não encontrado em build.gradle.kts")
gradle.write_text(s)

manifest = pathlib.Path("android/app/src/main/AndroidManifest.xml")
m = manifest.read_text()
if "RECEIVE_BOOT_COMPLETED" not in m:
    m = m.replace(
        "<application",
        '<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n    <application',
        1,
    )
if "ScheduledNotificationReceiver" not in m:
    receivers = """
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
            </intent-filter>
        </receiver>
    </application>"""
    if m.count("</application>") != 1:
        raise SystemExit("</application> inesperado")
    m = m.replace("</application>", receivers.lstrip("\n").replace("        <receiver", "        <receiver", 1), 1)
manifest.write_text(m)
print("Android configurado para lembretes.")

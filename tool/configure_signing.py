#!/usr/bin/env python3
"""Assinatura de release: se existir android/key.properties, o APK é assinado
com a chave fixa do FINTRACK; senão, com a chave de depuração (como antes).

Corre no CI depois de `flutter create`. Idempotente.
"""
import pathlib
import re

gradle = pathlib.Path("android/app/build.gradle.kts")
s = gradle.read_text()
if "ftKeystoreProps" not in s:
    header = '''
// FINTRACK: chave de assinatura fixa (lida de android/key.properties no CI).
val ftKeystoreProps = java.util.Properties()
val ftKeystoreFile = rootProject.file("key.properties")
if (ftKeystoreFile.exists()) {
    ftKeystoreFile.inputStream().use { ftKeystoreProps.load(it) }
}
'''
    # Depois do bloco plugins { ... } (tem de ser o primeiro bloco do ficheiro).
    m = re.search(r"^plugins \{.*?^\}\n", s, flags=re.S | re.M)
    if not m:
        raise SystemExit("bloco plugins não encontrado em build.gradle.kts")
    s = s[: m.end()] + header + s[m.end():]

    signing = '''    signingConfigs {
        create("release") {
            if (ftKeystoreFile.exists()) {
                storeFile = rootProject.file(ftKeystoreProps.getProperty("storeFile"))
                storePassword = ftKeystoreProps.getProperty("storePassword")
                keyAlias = ftKeystoreProps.getProperty("keyAlias")
                keyPassword = ftKeystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {'''
    if s.count("    buildTypes {") != 1:
        raise SystemExit("bloco buildTypes inesperado")
    s = s.replace("    buildTypes {", signing, 1)

    new, n = re.subn(
        r'signingConfig = signingConfigs\.getByName\("debug"\)',
        'signingConfig = if (ftKeystoreFile.exists()) signingConfigs.getByName("release") '
        'else signingConfigs.getByName("debug")',
        s,
    )
    if n != 1:
        raise SystemExit("signingConfig de release não encontrado")
    s = new
    gradle.write_text(s)
print("Assinatura configurada.")

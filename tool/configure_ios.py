"""Ajusta a pasta ios/ gerada por `flutter create` (portável: Linux e macOS)."""
import pathlib
import re

ios = pathlib.Path("ios")

# Info.plist: nome, textos de permissões (a Apple recusa apps sem eles).
plist = ios / "Runner" / "Info.plist"
text = plist.read_text()
keys = {
    "NSFaceIDUsageDescription": "Desbloquear o FINTRACK com o rosto.",
    "NSPhotoLibraryUsageDescription": "Escolher a fotografia do perfil.",
    "NSCameraUsageDescription": "Tirar a fotografia do perfil.",
    "ITSAppUsesNonExemptEncryption": None,  # booleano, tratado abaixo
}
for key, value in keys.items():
    if f"<key>{key}</key>" in text:
        continue
    if value is None:
        entry = f"\t<key>{key}</key>\n\t<false/>\n"
    else:
        entry = f"\t<key>{key}</key>\n\t<string>{value}</string>\n"
    text = text.replace("<dict>\n", "<dict>\n" + entry, 1)
text = re.sub(
    r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)",
    r"\1FINTRACK\2",
    text,
)
plist.write_text(text)

# Versão mínima do iOS: 15 (cifra, biometria e notificações atuais).
podfile = ios / "Podfile"
if podfile.exists():
    p = podfile.read_text()
    p = re.sub(r"^#?\s*platform :ios, '[\d.]+'", "platform :ios, '15.0'", p, flags=re.M)
    podfile.write_text(p)
pbx = ios / "Runner.xcodeproj" / "project.pbxproj"
pbx.write_text(re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [\d.]+;", "IPHONEOS_DEPLOYMENT_TARGET = 15.0;", pbx.read_text()))

print("iOS configurado.")

import 'dart:math';
import 'dart:typed_data';

import 'package:fintrack/profile/profile_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  testWidgets('fotografia de perfil fica um JPEG quadrado e leve', (tester) async {
    // Fotografia "real": 1200x800 com ruído (pior caso para compressão).
    final rnd = Random(7);
    final big = img.Image(width: 1200, height: 800);
    for (final p in big) {
      p
        ..r = rnd.nextInt(256)
        ..g = rnd.nextInt(256)
        ..b = rnd.nextInt(256);
    }
    final png = Uint8List.fromList(img.encodePng(big));
    final thumb = await tester.runAsync(() => squareThumbnail(png));
    final decoded = img.decodeJpg(thumb!)!;
    expect(decoded.width, 224);
    expect(decoded.height, 224);
    expect(thumb.length, lessThan(png.length ~/ 10));
  });
}

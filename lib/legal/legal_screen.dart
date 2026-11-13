import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../design/tokens.dart';

enum LegalDoc {
  privacy('assets/legal/privacidade.md', 'Política de privacidade'),
  terms('assets/legal/termos.md', 'Termos de utilização');

  const LegalDoc(this.asset, this.title);
  final String asset;
  final String title;
}

/// Mostra um documento legal (Markdown simples: títulos, listas, negrito).
/// O mesmo ficheiro é publicado no repositório para as lojas.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.doc});

  final LegalDoc doc;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(doc.title)),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(doc.asset),
        builder: (context, snap) {
          final text = snap.data;
          if (text == null) return const Center(child: CircularProgressIndicator());
          return SelectionArea(
            child: ListView(
              padding: const EdgeInsets.all(FtSpace.lg),
              children: [for (final line in text.split('\n')) _line(context, line)],
            ),
          );
        },
      ),
    );
  }

  /// "**negrito**" dentro de uma linha.
  static TextSpan _inline(String s, TextStyle? base) {
    final spans = <TextSpan>[];
    final parts = s.split('**');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      spans.add(TextSpan(
        text: parts[i],
        style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w700) : null,
      ));
    }
    return TextSpan(style: base, children: spans);
  }

  Widget _line(BuildContext context, String line) {
    final theme = Theme.of(context);
    if (line.trim().isEmpty) return const SizedBox(height: FtSpace.sm);
    if (line.startsWith('# ')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: FtSpace.sm),
        child: Text(line.substring(2), style: theme.textTheme.headlineSmall),
      );
    }
    if (line.startsWith('## ')) {
      return Padding(
        padding: const EdgeInsets.only(top: FtSpace.md, bottom: FtSpace.xs),
        child: Text(line.substring(3), style: theme.textTheme.titleMedium),
      );
    }
    if (line.startsWith('- ')) {
      return Padding(
        padding: const EdgeInsets.only(left: FtSpace.sm, bottom: FtSpace.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•  '),
            Expanded(child: Text.rich(_inline(line.substring(2), theme.textTheme.bodyMedium))),
          ],
        ),
      );
    }
    return Text.rich(_inline(line, theme.textTheme.bodyMedium));
  }
}

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart' show FilePicker, FileType;
import 'package:fintrack_core/fintrack_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../design/tokens.dart';
import '../security/session.dart';

/// Reduz uma fotografia a um quadrado de [size] px (corte central), em PNG.
/// A original nunca é guardada.
Future<Uint8List> squareThumbnail(Uint8List bytes, {int size = 256}) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  final side = image.width < image.height ? image.width : image.height;
  final src = Rect.fromLTWH(
    (image.width - side) / 2,
    (image.height - side) / 2,
    side.toDouble(),
    side.toDouble(),
  );
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    image,
    src,
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..filterQuality = FilterQuality.high,
  );
  final out = await recorder.endRecording().toImage(size, size);
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  out.dispose();
  return data!.buffer.asUint8List();
}

/// Avatar com a fotografia do perfil ou as iniciais.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.profile, this.radius = 18});

  final Profile? profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final photo = profile?.photo;
    final name = profile?.greetingName ?? '';
    final initials = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      backgroundImage: photo == null ? null : MemoryImage(photo),
      child: photo == null
          ? Text(initials, style: TextStyle(fontSize: radius * 0.8, fontWeight: FontWeight.w600))
          : null,
    );
  }
}

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final Profile? _initial = ref.read(sessionProvider).profile;
  late final _name = TextEditingController(text: _initial?.name ?? '');
  late final _nickname = TextEditingController(text: _initial?.nickname ?? '');
  late Uint8List? _photo = _initial?.photo;
  String? _nameError;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isEmpty) return;
      final bytes = await files.first.readAsBytes();
      final thumb = await squareThumbnail(bytes);
      setState(() {
        _photo = thumb;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = 'Não foi possível usar esta imagem.');
    }
  }

  Future<void> _save() async {
    final initial = _initial;
    if (initial == null) return;
    final name = NameRules.clean(_name.text);
    final nickname = _nickname.text.trim().isEmpty ? '' : NameRules.clean(_nickname.text, max: 20);
    setState(() {
      _nameError = name == null ? 'Escreva o seu nome.' : null;
      _error = nickname == null ? 'A alcunha tem no máximo 20 letras.' : null;
    });
    if (name == null || nickname == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).updateProfile(Profile(
            name: name,
            mainCurrency: initial.mainCurrency,
            nickname: nickname,
            photo: _photo,
          ));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível guardar.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = Profile(
      name: _name.text.isEmpty ? '?' : _name.text,
      mainCurrency: _initial?.mainCurrency ?? Currency.aoa,
      nickname: _nickname.text,
      photo: _photo,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FtSpace.lg),
          children: [
            Center(
              child: Stack(
                children: [
                  GestureDetector(onTap: _pickPhoto, child: ProfileAvatar(profile: preview, radius: 52)),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: IconButton.filled(
                      tooltip: 'Escolher fotografia',
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      onPressed: _pickPhoto,
                    ),
                  ),
                ],
              ),
            ),
            if (_photo != null)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _photo = null),
                  child: const Text('Remover fotografia'),
                ),
              ),
            const SizedBox(height: FtSpace.lg),
            TextField(
              key: const Key('profile-full-name'),
              controller: _name,
              maxLength: NameRules.maxLength,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Nome',
                errorText: _nameError,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: FtSpace.sm),
            TextField(
              key: const Key('profile-nickname'),
              controller: _nickname,
              maxLength: 20,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Alcunha (opcional)',
                helperText: 'Como quer ser tratado no Início. Vazio = primeiro nome.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: FtSpace.md),
            Text(
              'A fotografia é reduzida e guardada apenas neste telemóvel, na base de dados cifrada.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (_error != null) ...[
              const SizedBox(height: FtSpace.sm),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: FtSpace.lg),
            FilledButton(onPressed: _busy ? null : _save, child: const Text('Guardar perfil')),
          ],
        ),
      ),
    );
  }
}

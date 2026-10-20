import 'dart:typed_data';

import 'package:flutter/material.dart';

enum SongShareFormat { story, chat, video }

/// Spotify-inspired preview panel that hands off to Android's native chooser.
class SongShareStoryPage extends StatefulWidget {
  const SongShareStoryPage({
    super.key,
    required this.title,
    required this.artist,
    required this.preview,
    required this.onPreviewForTheme,
    required this.onShareStory,
    required this.onShareChat,
    required this.onShareVideo,
    required this.onLoadTargets,
    required this.onShareToTarget,
  });

  final String title;
  final String artist;
  final Uint8List preview;
  final Future<Uint8List> Function(String theme) onPreviewForTheme;
  final Future<void> Function(String theme) onShareStory;
  final Future<void> Function(String theme) onShareChat;
  final Future<void> Function(String theme) onShareVideo;
  final Future<List<Map<String, Object?>>> Function(String format)
  onLoadTargets;
  final Future<void> Function(
    String format,
    String theme,
    Map<String, Object?> target,
  )
  onShareToTarget;

  @override
  State<SongShareStoryPage> createState() => _SongShareStoryPageState();
}

class _SongShareStoryPageState extends State<SongShareStoryPage> {
  static const _themes = <(String, Color)>[
    ('ocean', Color(0xff83e8ff)),
    ('sunset', Color(0xffff6b7d)),
    ('violet', Color(0xffb69cff)),
  ];

  SongShareFormat _format = SongShareFormat.story;
  String _theme = 'ocean';
  late Uint8List _preview = widget.preview;
  bool _isSharing = false;
  bool _loadingPreview = false;
  bool _loadingTargets = true;
  List<Map<String, Object?>> _targets = const [];

  @override
  void initState() {
    super.initState();
    _loadTargets();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      height: size.height * .82,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xff202124),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 8),
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white38,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Compartir canción',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _isSharing
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.white70,
                    tooltip: 'Cerrar',
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: Image.memory(
                              _preview,
                              key: ValueKey('$_theme-${_preview.length}'),
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                          ),
                          if (_format == SongShareFormat.video)
                            Center(
                              child: Container(
                                width: 66,
                                height: 66,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: .58),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: .85),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 42,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          if (_loadingPreview)
                            const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      for (final format in SongShareFormat.values) ...[
                        if (format != SongShareFormat.story)
                          const SizedBox(width: 8),
                        Expanded(child: _formatButton(format)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final (theme, color) in _themes)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          child: _themeButton(theme, color),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Compartir con',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .72),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 76,
                    child: _loadingTargets
                        ? const Center(
                            child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _targets.length + 1,
                            separatorBuilder: (context, index) =>
                                const SizedBox(width: 18),
                            itemBuilder: (context, index) =>
                                index == _targets.length
                                ? _moreTarget()
                                : _targetButton(_targets[index]),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formatButton(SongShareFormat format) {
    final selected = _format == format;
    final (icon, label) = switch (format) {
      SongShareFormat.story => (Icons.photo_outlined, 'Historia'),
      SongShareFormat.chat => (Icons.link_rounded, 'Chat'),
      SongShareFormat.video => (Icons.movie_outlined, 'Vídeo'),
    };
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: _isSharing || _format == format
            ? null
            : () {
                setState(() => _format = format);
                _loadTargets();
              },
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 44,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.white.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? const Color(0xff16171a) : Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? const Color(0xff16171a) : Colors.white,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _themeButton(String theme, Color color) {
    final selected = _theme == theme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Tema $theme',
      child: GestureDetector(
        onTap: _isSharing || _loadingPreview || selected
            ? null
            : () => _selectTheme(theme),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: selected ? 48 : 42,
          height: selected ? 48 : 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: selected ? Colors.white : Colors.white30,
              width: selected ? 3 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: .35),
                      blurRadius: 12,
                    ),
                  ]
                : null,
          ),
          child: selected
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
              : null,
        ),
      ),
    );
  }

  Future<void> _selectTheme(String theme) async {
    setState(() {
      _theme = theme;
      _loadingPreview = true;
    });
    try {
      final preview = await widget.onPreviewForTheme(theme);
      if (mounted) setState(() => _preview = preview);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo actualizar la vista previa.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingPreview = false);
    }
  }

  String get _formatKey => switch (_format) {
    SongShareFormat.story => 'story',
    SongShareFormat.chat => 'chat',
    SongShareFormat.video => 'video',
  };

  Future<void> _loadTargets() async {
    setState(() => _loadingTargets = true);
    try {
      final targets = await widget.onLoadTargets(_formatKey);
      if (mounted) setState(() => _targets = targets);
    } catch (_) {
      if (mounted) setState(() => _targets = const []);
    } finally {
      if (mounted) setState(() => _loadingTargets = false);
    }
  }

  Widget _targetButton(Map<String, Object?> target) {
    final bytes = target['icon'];
    return InkWell(
      onTap: _isSharing ? null : () => _shareToTarget(target),
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 58,
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              padding: const EdgeInsets.all(7),
              child: bytes is Uint8List
                  ? Image.memory(bytes, fit: BoxFit.contain)
                  : const Icon(Icons.apps_rounded, color: Colors.white),
            ),
            const SizedBox(height: 5),
            Text(
              '${target['label'] ?? 'App'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moreTarget() => InkWell(
    onTap: _isSharing ? null : _shareSelectedFormat,
    borderRadius: BorderRadius.circular(14),
    child: const SizedBox(
      width: 58,
      child: Column(
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: Colors.white12,
            child: Icon(Icons.more_horiz_rounded, color: Colors.white),
          ),
          SizedBox(height: 5),
          Text('Más', style: TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    ),
  );

  Future<void> _shareToTarget(Map<String, Object?> target) async {
    setState(() => _isSharing = true);
    try {
      await widget.onShareToTarget(_formatKey, _theme, target);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSharing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo compartir con esta aplicación.'),
        ),
      );
    }
  }

  Future<void> _shareSelectedFormat() async {
    setState(() => _isSharing = true);
    try {
      switch (_format) {
        case SongShareFormat.story:
          await widget.onShareStory(_theme);
          break;
        case SongShareFormat.chat:
          await widget.onShareChat(_theme);
          break;
        case SongShareFormat.video:
          await widget.onShareVideo(_theme);
          break;
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSharing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo compartir la canción.')),
      );
    }
  }
}

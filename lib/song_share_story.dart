import 'dart:typed_data';

import 'package:flutter/material.dart';

enum SongShareFormat { story, chat, video }

/// Share session with a real card preview and three content formats.
class SongShareStoryPage extends StatefulWidget {
  const SongShareStoryPage({
    super.key,
    required this.title,
    required this.artist,
    required this.preview,
    required this.accentColor,
    required this.onShareStory,
    required this.onShareChat,
    required this.onShareVideo,
  });

  final String title;
  final String artist;
  final Uint8List preview;
  final Color accentColor;
  final Future<void> Function() onShareStory;
  final Future<void> Function() onShareChat;
  final Future<void> Function() onShareVideo;

  @override
  State<SongShareStoryPage> createState() => _SongShareStoryPageState();
}

class _SongShareStoryPageState extends State<SongShareStoryPage> {
  SongShareFormat _format = SongShareFormat.story;
  bool _isSharing = false;

  @override
  Widget build(BuildContext context) {
    final formatInfo = switch (_format) {
      SongShareFormat.story => (
        icon: Icons.photo_outlined,
        label: 'Compartir foto',
        description: 'Tarjeta vertical para estados e historias',
      ),
      SongShareFormat.chat => (
        icon: Icons.chat_bubble_outline_rounded,
        label: 'Compartir enlace',
        description: 'Enlace inteligente para enviar por chat',
      ),
      SongShareFormat.video => (
        icon: Icons.movie_creation_outlined,
        label: 'Compartir vídeo',
        description: 'Vídeo vertical con un fragmento de música',
      ),
    };

    return Scaffold(
      backgroundColor: const Color(0xff070f15),
      appBar: AppBar(
        title: const Text('Compartir canción'),
        backgroundColor: const Color(0xff070f15),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(26),
                      child: Semantics(
                        label:
                            'Vista previa de ${widget.title}, de ${widget.artist}',
                        image: true,
                        child: Image.memory(
                          widget.preview,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Formato',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      _formatButton(
                        SongShareFormat.story,
                        Icons.photo_outlined,
                        'Historia',
                      ),
                      const SizedBox(width: 8),
                      _formatButton(
                        SongShareFormat.chat,
                        Icons.chat_bubble_outline_rounded,
                        'Chat',
                      ),
                      const SizedBox(width: 8),
                      _formatButton(
                        SongShareFormat.video,
                        Icons.movie_creation_outlined,
                        'Vídeo',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    formatInfo.description,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _isSharing ? null : _shareSelectedFormat,
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.accentColor,
                        foregroundColor: Colors.white,
                      ),
                      icon: _isSharing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(formatInfo.icon),
                      label: Text(
                        _isSharing ? 'Preparando…' : formatInfo.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
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

  Widget _formatButton(SongShareFormat format, IconData icon, String label) {
    final selected = _format == format;
    return Expanded(
      child: GestureDetector(
        onTap: _isSharing ? null : () => setState(() => _format = format),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 42,
          decoration: BoxDecoration(
            color: selected
                ? widget.accentColor.withValues(alpha: .20)
                : Colors.white.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? widget.accentColor.withValues(alpha: .75)
                  : Colors.white.withValues(alpha: .10),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? widget.accentColor : Colors.white70,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareSelectedFormat() async {
    setState(() => _isSharing = true);
    try {
      switch (_format) {
        case SongShareFormat.story:
          await widget.onShareStory();
          break;
        case SongShareFormat.chat:
          await widget.onShareChat();
          break;
        case SongShareFormat.video:
          await widget.onShareVideo();
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

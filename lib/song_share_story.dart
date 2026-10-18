import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Standalone preview shown before sending a song as a visual story.
class SongShareStoryPage extends StatelessWidget {
  const SongShareStoryPage({
    super.key,
    required this.title,
    required this.artist,
    required this.artwork,
    required this.onShare,
    required this.onShareLink,
    required this.onShareStatusLink,
  });

  final String title;
  final String artist;
  final Uint8List artwork;
  final Future<void> Function() onShare;
  final Future<void> Function() onShareLink;
  final Future<void> Function() onShareStatusLink;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff070f15),
      appBar: AppBar(
        title: const Text('Compartir historia'),
        backgroundColor: const Color(0xff070f15),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 4 / 5,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(artwork, fit: BoxFit.cover),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0x33000000),
                                  Color(0x00101010),
                                  Color(0xee050b10),
                                ],
                                stops: [0, .36, 1],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(22),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _BrandPill(),
                                const Spacer(),
                                Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 25,
                                    height: 1.08,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xffd4dbe0),
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                const Row(
                                  children: [
                                    Icon(Icons.play_circle_fill_rounded,
                                        color: Color(0xff58d9ca), size: 28),
                                    SizedBox(width: 9),
                                    Text(
                                      'Compartida desde SoundNeed',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: () => _share(context, onShare),
                      icon: const Icon(Icons.movie_creation_outlined),
                      label: const Text('Compartir estado con música'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () => _share(context, onShareLink),
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      label: const Text('Compartir enlace en un chat'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () => _share(context, onShareStatusLink),
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('Publicar enlace clicable en Estado'),
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

  Future<void> _share(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo compartir la canción.')),
      );
    }
  }
}

class _BrandPill extends StatelessWidget {
  const _BrandPill();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xb8070f15),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.graphic_eq_rounded, color: Color(0xff58d9ca), size: 19),
              SizedBox(width: 7),
              Text('SOUNDNEED', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 12)),
            ],
          ),
        ),
      );
}

import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../music_player.dart';
import '../services/album_lookup_service.dart';
import '../services/youtube_audio_service.dart';

class DiscoveredAlbumPage extends StatefulWidget {
  const DiscoveredAlbumPage({
    super.key,
    required this.player,
    required this.songTitle,
    required this.artist,
  });

  final MusicPlayerController player;
  final String songTitle;
  final String artist;

  @override
  State<DiscoveredAlbumPage> createState() => _DiscoveredAlbumPageState();
}

class _DiscoveredAlbumPageState extends State<DiscoveredAlbumPage> {
  late Future<DiscoveredAlbum?> _albumFuture;
  String? _loadingTrack;

  @override
  void initState() {
    super.initState();
    _albumFuture = _findAlbum();
  }

  Future<DiscoveredAlbum?> _findAlbum() =>
      AlbumLookupService.instance.findAlbum(
        title: widget.songTitle,
        artist: widget.artist,
      );

  void _retry() => setState(() => _albumFuture = _findAlbum());

  Future<void> _playTrack(DiscoveredAlbumTrack track) async {
    final key = '${track.title}|${track.artist}';
    setState(() => _loadingTrack = key);
    try {
      final results = await YouTubeAudioService.instance.search(
        '${track.title} ${track.artist} audio',
      );
      if (!mounted) return;
      if (results.isEmpty) {
        _message('No encontramos esta canción para reproducir.');
        return;
      }
      final expected = _normalize(track.title);
      final result = results.cast<YouTubeSearchResult?>().firstWhere(
            (item) =>
                item != null && _normalize(item.title).contains(expected),
            orElse: () => null,
          ) ??
          results.first;
      final ok = await widget.player.playOnline(result);
      if (!ok && mounted) {
        _message(widget.player.playbackError ?? 'No se pudo reproducir la canción.');
      }
    } catch (error) {
      if (mounted) _message('No se pudo buscar la canción: $error');
    } finally {
      if (mounted) setState(() => _loadingTrack = null);
    }
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]*\)|\[[^]]*\]'), '')
      .replaceAll(RegExp(r'[^a-z0-9áéíóúüñ]'), '');

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          title: const Text('Álbum de la canción'),
        ),
        body: FutureBuilder<DiscoveredAlbum?>(
          future: _albumFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final album = snapshot.data;
            if (snapshot.hasError || album == null) {
              return _emptyState(
                'No encontramos el álbum',
                'Buscamos usando el título y el artista. Revisa la conexión o prueba más tarde.',
                Icons.album_outlined,
              );
            }
            return AnimatedBuilder(
              animation: widget.player,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(26),
                      child: SizedBox(
                        width: 240,
                        height: 240,
                        child: album.coverUrl.isEmpty
                            ? _coverPlaceholder()
                            : Image.network(
                                album.coverUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _coverPlaceholder(),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    album.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    album.artist,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    [
                      if (album.releaseDate.isNotEmpty) album.releaseDate,
                      '${album.tracks.length} ${album.tracks.length == 1 ? 'canción' : 'canciones'}',
                    ].join(' · '),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 24),
                  if (album.tracks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'Encontramos el álbum, pero no pudimos cargar sus canciones.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  else
                    ...album.tracks.indexed.map((entry) {
                      final track = entry.$2;
                      final key = '${track.title}|${track.artist}';
                      final isCurrent = widget.player.currentSong?.title == track.title &&
                          widget.player.currentSong?.artist == track.artist;
                      final isLoading = _loadingTrack == key;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Material(
                          color: isCurrent
                              ? Colors.white.withOpacity(.085)
                              : Colors.white.withOpacity(.035),
                          borderRadius: BorderRadius.circular(18),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            leading: SizedBox(
                              width: 34,
                              child: Center(
                                child: isLoading
                                    ? const SizedBox(
                                        width: 19,
                                        height: 19,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : Text(
                                        '${entry.$1 + 1}',
                                        style: TextStyle(
                                          color: isCurrent ? Colors.white : Colors.white54,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrent ? Colors.white : Colors.white.withOpacity(.92),
                                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                            trailing: Text(
                              _formatDuration(track.durationSeconds),
                              style: const TextStyle(color: Colors.white38, fontSize: 12),
                            ),
                            onTap: isLoading ? null : () => _playTrack(track),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 10),
                  const Text(
                    'Álbum encontrado por título y artista. Al elegir una canción, SoundNeed busca una versión reproducible.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
                  ),
                ],
              ),
            );
          },
        ),
      );

  Widget _emptyState(String title, String detail, IconData icon) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 58, color: Colors.white38),
              const SizedBox(height: 18),
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 18),
              FilledButton.icon(onPressed: _retry, icon: const Icon(Icons.refresh_rounded), label: const Text('Intentar de nuevo')),
            ],
          ),
        ),
      );

  Widget _coverPlaceholder() => Container(
        color: const Color(0xFF29243A),
        child: const Icon(Icons.album_rounded, size: 68, color: Colors.white54),
      );

  String _formatDuration(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

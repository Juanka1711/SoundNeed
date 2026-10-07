import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../music_player.dart';
import '../app_colors.dart';
import '../player_navigation.dart';
import '../playlist_artwork.dart';
import '../song_actions.dart';
import '../services/artwork_palette.dart';
import '../widgets/soundneed_empty_state.dart';
import '../widgets/audio_artwork_visualizer.dart';

class SongsSection extends StatefulWidget {
  final MusicPlayerController player;
  final List<Song> filteredSongs;
  final String searchText;
  final ArtworkPalette palette;

  const SongsSection({
    super.key,
    required this.player,
    required this.filteredSongs,
    required this.searchText,
    required this.palette,
  });

  @override
  State<SongsSection> createState() => _SongsSectionState();
}

class _SongsSectionState extends State<SongsSection> {
  int? _observedSongId;
  bool _observedPlaying = false;

  @override
  void initState() {
    super.initState();
    _observePlayback();
    widget.player.addListener(_onPlayerChanged);
  }

  @override
  void didUpdateWidget(covariant SongsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      oldWidget.player.removeListener(_onPlayerChanged);
      _observePlayback();
      widget.player.addListener(_onPlayerChanged);
    }
  }

  @override
  void dispose() {
    widget.player.removeListener(_onPlayerChanged);
    super.dispose();
  }

  void _observePlayback() {
    _observedSongId = widget.player.currentSong?.id;
    _observedPlaying = widget.player.isPlaying;
  }

  void _onPlayerChanged() {
    final songId = widget.player.currentSong?.id;
    final playing = widget.player.isPlaying;
    if (songId == _observedSongId && playing == _observedPlaying) return;
    _observedSongId = songId;
    _observedPlaying = playing;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.player.loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (widget.player.permissionDenied) {
      return _buildPermissionMessage();
    }

    if (widget.player.songs.isEmpty) {
      return _buildEmptyLibrary();
    }

    final songs = widget.filteredSongs;

    return RefreshIndicator(
      color: Colors.white,
      backgroundColor: AppColors.card,
      onRefresh: widget.player.loadSongs,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: songs.isEmpty ? 2 : songs.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _buildLibraryHeader(songs),
            );
          }
          if (songs.isEmpty) return _buildNoResults();
          final song = songs[index - 1];
          final isCurrent = widget.player.currentSong?.id == song.id;
          final isPlaying = isCurrent && widget.player.isPlaying;
          return _buildSongTile(context, song, isCurrent, isPlaying);
        },
      ),
    );
  }

  Widget _buildLibraryHeader(List<Song> songs) {
    final primary = widget.palette.primary;
    final secondary = widget.palette.secondary;
    final deep = widget.palette.dark;

    return Container(
      height: 154,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(primary, deep, .28)!,
            Color.lerp(secondary, deep, .72)!,
            AppColors.card,
          ],
        ),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: primary.withValues(alpha: .28)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 108,
            top: -40,
            child: IgnorePointer(
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      secondary.withValues(alpha: .20),
                      primary.withValues(alpha: .05),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 14,
            top: 14,
            bottom: 14,
            width: 126,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(19),
              child: PlaylistArtwork(
                player: widget.player,
                songs: songs,
                icon: Icons.library_music_rounded,
                accent: primary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 144, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.graphic_eq_rounded, size: 14, color: secondary),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'BIBLIOTECA MUSICAL',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .72),
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.05,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tu música',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${songs.length} ${songs.length == 1 ? 'canción' : 'canciones'}',
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: songs.isEmpty
                      ? null
                      : () => widget.player.playPlaylist(songs, shuffle: true),
                  icon: const Icon(Icons.shuffle_rounded, size: 16),
                  label: const Text('Mezclar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: secondary.withValues(alpha: .52)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    minimumSize: const Size(0, 34),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 7,
            bottom: 7,
            child: IconButton.filled(
              tooltip: 'Reproducir canciones',
              onPressed: songs.isEmpty
                  ? null
                  : () => widget.player.playPlaylist(songs),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF281A3D),
                fixedSize: const Size(44, 44),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 26),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongTile(
    BuildContext context,
    Song song,
    bool isCurrent,
    bool isPlaying,
  ) {
    final accent = isCurrent && widget.palette.isArtworkDerived
        ? Color.lerp(widget.palette.primary, Colors.white, .28)!
        : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
      child: Material(
        color: isCurrent
            ? widget.palette.primary.withValues(alpha: .16)
            : AppColors.card.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => selectSongOrOpenPlayer(context, widget.player, song),
          onLongPress: () => confirmDeleteSong(context, widget.player, song),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 5, 9),
            child: Row(
              children: [
                _buildArtwork(song, size: 62, isPlaying: isPlaying),
                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title.isEmpty ? song.displayName : song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isCurrent
                              ? FontWeight.w800
                              : FontWeight.w700,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              song.artist.isEmpty
                                  ? 'Artista desconocido'
                                  : song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .055),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.player.formatDuration(song.duration),
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Opciones de canción',
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: Colors.white70,
                  ),
                  onSelected: (value) {
                    if (value == 'delete') {
                      confirmDeleteSong(context, widget.player, song);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded),
                          SizedBox(width: 12),
                          Text('Eliminar del dispositivo'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArtwork(
    Song song, {
    double size = 76,
    bool isPlaying = false,
  }) {
    return FutureBuilder<Uint8List?>(
      future: widget.player.loadArtwork(song),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return _artworkWithVisualizer(
            Image.memory(
              snapshot.data!,
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
            size,
            isPlaying,
          );
        }

        return _artworkWithVisualizer(
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: widget.palette.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: widget.palette.primary.withValues(alpha: .26),
              ),
            ),
            child: Icon(
              Icons.music_note_rounded,
              size: 32,
              color: widget.palette.secondary,
            ),
          ),
          size,
          isPlaying,
        );
      },
    );
  }

  Widget _artworkWithVisualizer(
    Widget artwork,
    double size,
    bool isPlaying,
  ) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          fit: StackFit.expand,
          children: [
            artwork,
            if (isPlaying)
              AudioArtworkVisualizer(
                sessionIds: widget.player.audioPlayer.androidAudioSessionIdStream,
                initialSessionId: widget.player.audioPlayer.androidAudioSessionId,
                isPlaying: isPlaying,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResults() {
    return SoundNeedEmptyState(
      icon: Icons.search_off_rounded,
      title: 'No encontramos canciones',
      message: 'No hay resultados para “${widget.searchText}”.',
      accent: widget.palette.primary,
    );
  }

  Widget _buildEmptyLibrary() {
    return SoundNeedEmptyState(
      icon: Icons.library_music_rounded,
      title: 'Tu biblioteca está lista para sonar',
      message: 'Agrega archivos de música a tu dispositivo y actualiza la biblioteca.',
      accent: widget.palette.primary,
      action: FilledButton.icon(
        onPressed: widget.player.loadSongs,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Actualizar música'),
        style: FilledButton.styleFrom(
          backgroundColor: widget.palette.primary,
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
        ),
      ),
    );
  }

  Widget _buildPermissionMessage() {
    return SoundNeedEmptyState(
      icon: Icons.folder_shared_rounded,
      title: 'Necesitamos acceso a tu música',
      message: 'Concede permiso para que SoundNeed pueda mostrar los archivos de audio del dispositivo.',
      accent: widget.palette.primary,
      action: FilledButton.icon(
        onPressed: widget.player.loadSongs,
        icon: const Icon(Icons.lock_open_rounded),
        label: const Text('Conceder permiso'),
        style: FilledButton.styleFrom(
          backgroundColor: widget.palette.primary,
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
        ),
      ),
    );
  }
}

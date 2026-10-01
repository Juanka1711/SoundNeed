import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../music_player.dart';
import '../app_colors.dart';

class SongsSection extends StatelessWidget {
  final MusicPlayerController player;
  final List<Song> filteredSongs;
  final String searchText;

  const SongsSection({
    super.key,
    required this.player,
    required this.filteredSongs,
    required this.searchText,
  });

  @override
  Widget build(BuildContext context) {
    if (player.loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
        ),
      );
    }

    if (player.permissionDenied) {
      return _buildPermissionMessage();
    }

    if (player.songs.isEmpty) {
      return _buildEmptyLibrary();
    }

    if (filteredSongs.isEmpty) {
      return _buildNoResults();
    }

    return RefreshIndicator(
      color: Colors.white,
      backgroundColor: AppColors.card,
      onRefresh: player.loadSongs,
      child: ListView.builder(
        padding: const EdgeInsets.only(
          top: 4,
          bottom: 14,
        ),
        itemCount: filteredSongs.length,
        itemBuilder: (context, index) {
          final song = filteredSongs[index];

          final isCurrent = player.currentSong?.id == song.id;

          return _buildSongTile(
            song,
            isCurrent,
          );
        },
      ),
    );
  }

  Widget _buildSongTile(
    Song song,
    bool isCurrent,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 4,
      ),
      child: Material(
        color: isCurrent
            ? Colors.white.withOpacity(0.06)
            : Colors.transparent,
        borderRadius:
            BorderRadius.circular(16),
        child: InkWell(
          borderRadius:
              BorderRadius.circular(16),
          onTap: () =>
              player.playSong(song),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 7,
              vertical: 7,
            ),
            child: Row(
              children: [
                _buildArtwork(
                  song,
                  size: 76,
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title.isEmpty
                            ? song.displayName
                            : song.title,
                        maxLines: 2,
                        overflow:
                            TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: isCurrent
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        song.artist.isEmpty
                            ? 'Artista desconocido'
                            : song.artist,
                        maxLines: 1,
                        overflow:
                            TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color:
                              AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 6),

                Text(
                  player.formatDuration(
                    song.duration,
                  ),
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                  ),
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
  }) {
    return FutureBuilder<Uint8List?>(
      future: player.loadArtwork(song),
      builder: (context, snapshot) {
        if (snapshot.hasData &&
            snapshot.data != null) {
          return ClipRRect(
            borderRadius:
                BorderRadius.circular(13),
            child: Image.memory(
              snapshot.data!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          );
        }

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius:
                BorderRadius.circular(13),
            border: Border.all(
              color:
                  Colors.white.withOpacity(0.10),
            ),
          ),
          child: const Icon(
            Icons.music_note,
            size: 32,
            color: Colors.white54,
          ),
        );
      },
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 70,
              color:
                  Colors.white.withOpacity(0.25),
            ),
            const SizedBox(height: 18),
            const Text(
              'No encontramos canciones',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No hay resultados para "$searchText".',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyLibrary() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              Icons.music_off,
              size: 80,
              color:
                  Colors.white.withOpacity(0.25),
            ),
            const SizedBox(height: 20),
            const Text(
              'No hay música',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Agrega archivos de música a tu dispositivo y actualiza la biblioteca.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
              ),
              onPressed:
                  player.loadSongs,
              icon: const Icon(Icons.refresh),
              label:
                  const Text('Actualizar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 80,
              color:
                  Colors.white.withOpacity(0.25),
            ),
            const SizedBox(height: 20),
            const Text(
              'Permiso necesario',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'La aplicación necesita permiso para acceder a la música almacenada en el dispositivo.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
              ),
              onPressed:
                  player.loadSongs,
              icon:
                  const Icon(Icons.lock_open),
              label: const Text(
                'Conceder permiso',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

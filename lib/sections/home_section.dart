import 'package:flutter/material.dart';

import '../music_player.dart';
import '../app_colors.dart';
import '../services/youtube_audio_service.dart';
import '../services/music_player_service.dart';
import '../widgets/recommendation_sections.dart' show RecommendationSections, RecommendationSectionsState;

class HomeSection extends StatefulWidget {
  final MusicPlayerController player;
  final List<YouTubeSearchResult>? onlineResults;
  final String? onlineQuery;
  final bool isSearchingOnline;
  final VoidCallback? clearOnlineSearch;
  final List<Song>? localSearchResults;

  const HomeSection({
    super.key,
    required this.player,
    this.onlineResults,
    this.onlineQuery,
    this.isSearchingOnline = false,
    this.clearOnlineSearch,
    this.localSearchResults,
  });

  @override
  State<HomeSection> createState() =>
      _HomeSectionState();
}

class _HomeSectionState
    extends State<HomeSection> {
  final GlobalKey<
          RecommendationSectionsState>
      _recommendationKey =
      GlobalKey<RecommendationSectionsState>();

  @override
  Widget build(BuildContext context) {
    final player = widget.player;

    final showOnlineResults =
        widget.onlineResults != null ||
            widget.isSearchingOnline;

    final hasLocalSearch =
        widget.localSearchResults != null;

    final isSearchMode =
        hasLocalSearch ||
            showOnlineResults;

    return RefreshIndicator(
      color: Colors.white,
      backgroundColor: AppColors.card,
      onRefresh: () async {
        await player.loadSongs();

        await _recommendationKey
            .currentState
            ?.refresh();
      },
      child: ListView(
        padding:
            const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          32,
        ),
        keyboardDismissBehavior:
            ScrollViewKeyboardDismissBehavior
                .onDrag,
        children: [
          _buildHeader(),

          const SizedBox(height: 28),

          /// ====================================================
          /// BÚSQUEDA LOCAL
          /// ====================================================

          if (hasLocalSearch) ...[
            _buildLocalSearchResults(),

            const SizedBox(height: 32),
          ]

          /// ====================================================
          /// CONTENIDO NORMAL
          /// ====================================================
          else ...[
            if (!player.loading &&
                !player.permissionDenied)
              _buildStats(),

            const SizedBox(height: 30),

            if (player.loading)
              _buildLoading()
            else if (player.permissionDenied)
              _buildPermissionMessage()
            else if (player.songs.isEmpty)
              _buildEmptyLibrary(),

            /// ==================================================
            /// RECOMENDACIONES
            /// ==================================================

            if (!player.loading &&
                !player.permissionDenied &&
                player.songs.isNotEmpty) ...[
              const SizedBox(height: 38),

              RecommendationSections(
                key: _recommendationKey,
                player: player,
              ),
            ],
          ],

          /// ====================================================
          /// YOUTUBE
          /// ====================================================

          if (showOnlineResults) ...[
            const SizedBox(height: 32),
            _buildOnlineResults(),
          ],

          /// Evita que el último contenido
          /// quede pegado al borde inferior.
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader() {
    final songCount =
        widget.player.songs.length;

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        const Text(
          'Bienvenido',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$songCount canciones en tu biblioteca',
          style: const TextStyle(
            fontSize: 15,
            color:
                AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // LOCAL SEARCH
  // ============================================================

  Widget _buildLocalSearchResults() {
    final results =
        widget.localSearchResults ?? [];

    if (results.isEmpty) {
      return Container(
        padding:
            const EdgeInsets.symmetric(
          vertical: 40,
          horizontal: 20,
        ),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius:
              BorderRadius.circular(18),
          border: Border.all(
            color:
                Colors.white.withOpacity(
              0.08,
            ),
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color:
                  Colors.white.withOpacity(
                0.25,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Sin resultados locales',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'No encontramos canciones en tu biblioteca',
              style: TextStyle(
                color:
                    AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Resultados locales',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),
            Text(
              '${results.length}',
              style: const TextStyle(
                color:
                    AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        ...results.map(
          _buildSongTile,
        ),
      ],
    );
  }

  // ============================================================
  // ONLINE RESULTS
  // ============================================================

  Widget _buildOnlineResults() {
    if (widget.isSearchingOnline) {
      return const Padding(
        padding:
            EdgeInsets.symmetric(
          vertical: 40,
        ),
        child: Column(
          children: [
            CircularProgressIndicator(
              color: Colors.white,
            ),
            SizedBox(height: 18),
            Text(
              'Buscando en YouTube...',
              style: TextStyle(
                color:
                    AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    final results =
        widget.onlineResults ?? [];

    if (results.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Resultados de YouTube',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),
            Text(
              '${results.length}',
              style: const TextStyle(
                color:
                    AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        ...results.map(
          _buildOnlineSongTile,
        ),
      ],
    );
  }

  // ============================================================
  // STATS
  // ============================================================

  Widget _buildStats() {
    final player =
        widget.player;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Canciones',
            player.songs.length
                .toString(),
            Icons.music_note_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Artistas',
            _getUniqueArtists()
                .toString(),
            Icons.person_outline,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Álbumes',
            _getUniqueAlbums()
                .toString(),
            Icons.album_outlined,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
  ) {
    return Container(
      padding:
          const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(
          color:
              Colors.white.withOpacity(
            0.08,
            ),
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: Colors.white70,
            size: 24,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight:
                  FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color:
                  AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongTile(
    Song song,
  ) {
    final player =
        widget.player;

    final isCurrent =
        player.currentSong?.id ==
            song.id;

    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 8,
      ),
      child: Material(
        color: isCurrent
            ? Colors.white
                .withOpacity(0.06)
            : Colors.transparent,
        borderRadius:
            BorderRadius.circular(
          16,
        ),
        child: InkWell(
          borderRadius:
              BorderRadius.circular(
            16,
            ),
          onTap: () =>
              player.playSong(song),
          child: Padding(
            padding:
                const EdgeInsets.all(
              12,
            ),
            child: Row(
              children: [
                _buildArtwork(
                  song,
                  size: 56,
                ),

                const SizedBox(
                  width: 12,
                ),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Text(
                        song.title.isEmpty
                            ? song.displayName
                            : song.title,
                        maxLines: 1,
                        overflow:
                            TextOverflow
                                .ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight:
                              isCurrent
                                  ? FontWeight
                                      .w700
                                  : FontWeight
                                      .w600,
                          color:
                              Colors.white,
                        ),
                      ),
                      const SizedBox(
                        height: 4,
                      ),
                      Text(
                        song.artist.isEmpty
                            ? 'Artista desconocido'
                            : song.artist,
                        maxLines: 1,
                        overflow:
                            TextOverflow
                                .ellipsis,
                        style:
                            const TextStyle(
                          fontSize: 13,
                          color:
                              AppColors
                                  .textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                Text(
                  player.formatDuration(
                    song.duration,
                  ),
                  style:
                      const TextStyle(
                    color:
                        Colors.white38,
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

  // ============================================================
  // ARTWORK LOCAL
  // ============================================================

  Widget _buildArtwork(
    Song song, {
    double size = 56,
  }) {
    return FutureBuilder(
      future:
          widget.player.loadArtwork(
        song,
      ),
      builder:
          (context, snapshot) {
        if (snapshot.hasData &&
            snapshot.data != null) {
          return ClipRRect(
            borderRadius:
                BorderRadius.circular(
              12,
            ),
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
          decoration:
              BoxDecoration(
            color:
                Colors.white.withOpacity(
              0.06,
            ),
            borderRadius:
                BorderRadius.circular(
              12,
            ),
            border: Border.all(
              color:
                  Colors.white.withOpacity(
                0.10,
              ),
            ),
          ),
          child: const Icon(
            Icons.music_note,
            size: 24,
            color: Colors.white54,
          ),
        );
      },
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  int _getUniqueArtists() {
    final artists =
        widget.player.songs
            .map(
              (song) =>
                  song.artist,
            )
            .where(
              (artist) =>
                  artist
                      .trim()
                      .isNotEmpty,
            )
            .toSet();

    return artists.length;
  }

  int _getUniqueAlbums() {
    final albums =
        widget.player.songs
            .map(
              (song) =>
                  song.album,
            )
            .where(
              (album) =>
                  album
                      .trim()
                      .isNotEmpty,
            )
            .toSet();

    return albums.length;
  }

  // ============================================================
  // ONLINE SONG TILE
  // ============================================================

  Widget _buildOnlineSongTile(
    YouTubeSearchResult result,
  ) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 10,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius:
            BorderRadius.circular(
          16,
        ),
        child: InkWell(
          borderRadius:
              BorderRadius.circular(
            16,
            ),
          onTap: () async {
            final messenger =
                ScaffoldMessenger.of(
              context,
            );

            debugPrint(
              '[SoundNeed] YouTube seleccionado: '
              '${result.videoId}',
            );

            final ok =
                await widget.player
                    .playOnline(
              result,
              playlist:
                  widget.onlineResults,
            );

            if (!ok && mounted) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    'No se pudo reproducir: '
                    '${widget.player.playbackError ?? 'error desconocido'}',
                  ),
                ),
              );
            }
          },
          child: Padding(
            padding:
                const EdgeInsets.all(8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius:
                      BorderRadius.circular(
                    12,
                  ),
                  child: SizedBox(
                    width: 120,
                    height: 68,
                    child: result
                            .thumbnail
                            .isNotEmpty
                        ? Image.network(
                            result.thumbnail,
                            fit: BoxFit.cover,
                            errorBuilder:
                                (
                              context,
                              error,
                              stackTrace,
                            ) {
                              return _buildOnlinePlaceholder();
                            },
                          )
                        : _buildOnlinePlaceholder(),
                  ),
                ),

                const SizedBox(
                  width: 12,
                ),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Text(
                        result.title,
                        maxLines: 2,
                        overflow:
                            TextOverflow
                                .ellipsis,
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                          fontSize: 14,
                          fontWeight:
                              FontWeight.w600,
                        ),
                      ),

                      const SizedBox(
                        height: 5,
                      ),

                      Text(
                        result.artist.isEmpty
                            ? 'YouTube'
                            : result.artist,
                        maxLines: 1,
                        overflow:
                            TextOverflow
                                .ellipsis,
                        style:
                            const TextStyle(
                          color:
                              AppColors
                                  .textSecondary,
                          fontSize: 12,
                        ),
                      ),

                      if (result.duration >
                          0) ...[
                        const SizedBox(
                          height: 4,
                        ),
                        Text(
                          _formatOnlineDuration(
                            result.duration,
                          ),
                          style:
                              const TextStyle(
                            color:
                                Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(
                  width: 8,
                ),

                const Icon(
                  Icons
                      .play_circle_outline,
                  color:
                      Colors.white70,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOnlinePlaceholder() {
    return Container(
      color:
          Colors.white.withOpacity(
        0.06,
      ),
      child: const Icon(
        Icons.music_note,
        color: Colors.white38,
        size: 26,
      ),
    );
  }

  String _formatOnlineDuration(
    int seconds,
  ) {
    if (seconds <= 0) {
      return '';
    }

    final duration =
        Duration(seconds: seconds);

    final hours =
        duration.inHours;

    final minutes =
        duration.inMinutes
            .remainder(60);

    final secs =
        duration.inSeconds
            .remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:'
          '${secs.toString().padLeft(2, '0')}';
    }

    return '$minutes:'
        '${secs.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // LOADING
  // ============================================================

  Widget _buildLoading() {
    return const Padding(
      padding:
          EdgeInsets.symmetric(
        vertical: 80,
      ),
      child: Center(
        child:
            CircularProgressIndicator(
          color: Colors.white,
        ),
      ),
    );
  }

  // ============================================================
  // PERMISSION
  // ============================================================

  Widget _buildPermissionMessage() {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 60,
      ),
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline,
            size: 80,
            color:
                Colors.white.withOpacity(
              0.25,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Permiso necesario',
            style: TextStyle(
              fontSize: 22,
              fontWeight:
                  FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'La aplicación necesita permiso para acceder '
            'a la música almacenada en el dispositivo.',
            textAlign:
                TextAlign.center,
            style: TextStyle(
              color:
                  AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style:
                FilledButton.styleFrom(
              backgroundColor:
                  Colors.white,
              foregroundColor:
                  Colors.black,
            ),
            onPressed:
                widget.player.loadSongs,
            icon: const Icon(
              Icons.lock_open,
            ),
            label: const Text(
              'Conceder permiso',
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // EMPTY LIBRARY
  // ============================================================

  Widget _buildEmptyLibrary() {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 60,
      ),
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          Icon(
            Icons.music_off,
            size: 80,
            color:
                Colors.white.withOpacity(
              0.25,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No hay música',
            style: TextStyle(
              fontSize: 22,
              fontWeight:
                  FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Agrega archivos de música a tu dispositivo '
            'y actualiza la biblioteca.',
            textAlign:
                TextAlign.center,
            style: TextStyle(
              color:
                  AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style:
                FilledButton.styleFrom(
              backgroundColor:
                  Colors.white,
              foregroundColor:
                  Colors.black,
            ),
            onPressed:
                widget.player.loadSongs,
            icon: const Icon(
              Icons.refresh,
            ),
            label: const Text(
              'Actualizar',
            ),
          ),
        ],
      ),
    );
  }
}

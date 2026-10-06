import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../music_player.dart';
import '../services/music_player_service.dart';
import '../services/recommendation_service.dart';
import '../services/youtube_audio_service.dart';

/// ============================================================
/// RECOMMENDATION SECTIONS
/// ============================================================
///
/// Capa visual del sistema de recomendaciones.
///
/// El servicio RecommendationService decide QUÉ mostrar.
/// Este widget decide CÓMO mostrarlo.
///
/// Incluye:
/// - Tu mezcla
/// - Continúa escuchando
/// - Más de lo que te gusta
/// - Porque escuchaste...
/// - Descubrimiento
///
/// No contiene artistas, canciones ni géneros predefinidos.
/// Todo viene del aprendizaje local.
/// ============================================================

class RecommendationSections extends StatefulWidget {
  final MusicPlayerController player;

  const RecommendationSections({
    super.key,
    required this.player,
  });

  @override
  State<RecommendationSections> createState() =>
      RecommendationSectionsState();
}

class RecommendationSectionsState
    extends State<RecommendationSections> {
  final RecommendationService _recommendations =
      RecommendationService.instance;

  bool _loading = true;

  List<LearnedSong> _mix = [];
  List<LearnedSong> _continueListening = [];
  List<LearnedSong> _mostPlayed = [];
  List<LearnedSong> _discovery = [];

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
  }

  Future<void> refresh() async {
    await _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      await _recommendations.initialize();

      final results = await Future.wait([
        _recommendations.createMix(size: 12),
        _recommendations.getContinueListening(limit: 10),
        _recommendations.getMostPlayed(limit: 10),
        _recommendations.getDiscovery(limit: 10, searchNew: true),
      ]);

      if (!mounted) return;

      setState(() {
        _mix = results[0] as List<LearnedSong>;
        _continueListening = results[1] as List<LearnedSong>;
        _mostPlayed = results[2] as List<LearnedSong>;
        _discovery = results[3] as List<LearnedSong>;
        _loading = false;
      });
    } catch (e) {
      debugPrint(
        '[RecommendationSections] Error cargando recomendaciones: $e',
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _buildLoading();
    }

    final hasRecommendations =
        _mix.isNotEmpty ||
        _continueListening.isNotEmpty ||
        _mostPlayed.isNotEmpty ||
        _discovery.isNotEmpty;

    if (!hasRecommendations) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_mix.isNotEmpty) ...[
          _buildSection(
            title: 'Tu mezcla',
            subtitle: 'Creada a partir de lo que escuchas',
            songs: _mix,
            style: RecommendationSectionStyle.mix,
          ),
          const SizedBox(height: 34),
        ],

        if (_continueListening.isNotEmpty) ...[
          _buildSection(
            title: 'Continúa escuchando',
            subtitle: 'Retoma lo que estabas disfrutando',
            songs: _continueListening,
            style: RecommendationSectionStyle.standard,
          ),
          const SizedBox(height: 34),
        ],

        if (_mostPlayed.isNotEmpty) ...[
          _buildSection(
            title: 'Más de lo que te gusta',
            subtitle: 'Basado en tus reproducciones',
            songs: _mostPlayed,
            style: RecommendationSectionStyle.standard,
          ),
          const SizedBox(height: 34),
        ],

        if (_discovery.isNotEmpty) ...[
          _buildSection(
            title: 'Canciones no escuchadas',
            subtitle: 'Descubre música nueva basada en tus gustos',
            songs: _discovery,
            style: RecommendationSectionStyle.discovery,
          ),
        ],
      ],
    );
  }

  // ============================================================
  // SECTION
  // ============================================================

  Widget _buildSection({
    required String title,
    required String subtitle,
    required List<LearnedSong> songs,
    required RecommendationSectionStyle style,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              if (songs.length > 1)
                Text(
                  '${songs.length}',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        SizedBox(
          height: style == RecommendationSectionStyle.mix
              ? 236
              : 218,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(
              right: 8,
            ),
            itemCount: songs.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final song = songs[index];

              return _buildRecommendationCard(
                song: song,
                style: style,
                index: index,
              );
            },
          ),
        ),
      ],
    );
  }

  // ============================================================
  // CARD
  // ============================================================

  Widget _buildRecommendationCard({
    required LearnedSong song,
    required RecommendationSectionStyle style,
    required int index,
  }) {
    final width =
        style == RecommendationSectionStyle.mix
            ? 170.0
            : 158.0;

    final artworkSize =
        style == RecommendationSectionStyle.mix
            ? 170.0
            : 158.0;

    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _playRecommendation(song),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  _buildArtwork(
                    song,
                    size: artworkSize,
                    radius: 18,
                  ),

                  /// Número de posición.
                  if (style ==
                          RecommendationSectionStyle.mix &&
                      index < 3)
                    Positioned(
                      top: 9,
                      left: 9,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(
                            0.68,
                          ),
                          borderRadius:
                              BorderRadius.circular(9),
                        ),
                        child: Text(
                          '${index + 1}',
                          style:
                              const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight:
                                FontWeight.w800,
                          ),
                        ),
                      ),
                    ),

                  /// Botón de reproducción.
                  Positioned(
                    right: 9,
                    bottom: 9,
                    child: _buildPlayButton(song),
                  ),

                  /// Indicador de fuente.
                  if (song.source == 'youtube')
                    Positioned(
                      top: 9,
                      right: 9,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(
                            0.65,
                          ),
                          borderRadius:
                              BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.language,
                          size: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 10),

              Text(
                song.title.isEmpty
                    ? 'Sin título'
                    : song.title,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                song.artist.isEmpty
                    ? 'Artista desconocido'
                    : song.artist,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style: const TextStyle(
                  color:
                      AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ARTWORK
  // ============================================================

  Widget _buildArtwork(
    LearnedSong song, {
    required double size,
    required double radius,
  }) {
    /// Si es canción local, intentamos
    /// obtener su artwork real primero.
    final localSong = _findLocalSong(song);

    if (localSong != null) {
      return FutureBuilder(
        future: widget.player.loadArtwork(
          localSong,
        ),
        builder:
            (context, snapshot) {
          if (snapshot.hasData &&
              snapshot.data != null) {
            return ClipRRect(
              borderRadius:
                  BorderRadius.circular(
                radius,
              ),
              child: Image.memory(
                snapshot.data!,
                width: size,
                height: size,
                fit: BoxFit.cover,

              ),
            );
          }

          /// Si no tiene artwork local, intentar con thumbnail (YouTube)
          final thumbnail =
              song.thumbnail.trim();

          if (thumbnail.isNotEmpty) {
            return ClipRRect(
              borderRadius:
                  BorderRadius.circular(radius),
              child: Image.network(
                thumbnail,
                width: size,
                height: size,
                fit: BoxFit.cover,
                filterQuality:
                    FilterQuality.medium,
                errorBuilder:
                    (_, __, ___) {
                  return _buildArtworkPlaceholder(
                    size: size,
                    radius: radius,
                  );
                },
                loadingBuilder:
                    (
                      context,
                      child,
                      loadingProgress,
                    ) {
                  if (loadingProgress == null) {
                    return child;
                  }

                  return _buildArtworkPlaceholder(
                    size: size,
                    radius: radius,
                    loading: true,
                  );
                },
              ),
            );
          }

          return _buildArtworkPlaceholder(
            size: size,
            radius: radius,
          );
        },
      );
    }

    /// Si no es local, usar thumbnail (YouTube)
    final thumbnail =
        song.thumbnail.trim();

    if (thumbnail.isNotEmpty) {
      return ClipRRect(
        borderRadius:
            BorderRadius.circular(radius),
        child: Image.network(
          thumbnail,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality:
              FilterQuality.medium,
          errorBuilder:
              (_, __, ___) {
            return _buildArtworkPlaceholder(
              size: size,
              radius: radius,
            );
          },
          loadingBuilder:
              (
                context,
                child,
                loadingProgress,
              ) {
            if (loadingProgress == null) {
              return child;
            }

            return _buildArtworkPlaceholder(
              size: size,
              radius: radius,
              loading: true,
            );
          },
        ),
      );
    }

    return _buildArtworkPlaceholder(
      size: size,
      radius: radius,
    );
  }

  Widget _buildArtworkPlaceholder({
    required double size,
    required double radius,
    bool loading = false,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.10),
            Colors.white.withOpacity(0.025),
          ],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(
            0.08,
          ),
        ),
      ),
      child: Center(
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child:
                    CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white38,
                ),
              )
            : const Icon(
                Icons.music_note_rounded,
                color: Colors.white38,
                size: 30,
              ),
      ),
    );
  }

  // ============================================================
  // PLAY BUTTON
  // ============================================================

  Widget _buildPlayButton(
    LearnedSong song,
  ) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              0.35,
            ),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Icon(
        Icons.play_arrow_rounded,
        color: Colors.black,
        size: 25,
      ),
    );
  }

  // ============================================================
  // PLAY RECOMMENDATION
  // ============================================================

  Future<void> _playRecommendation(
    LearnedSong song,
  ) async {
    try {
      debugPrint('[RecommendationSections] Reproduciendo: ${song.title} (${song.source})');

      /// --------------------------------------------------------
      /// YOUTUBE - Validar videoId primero
      /// --------------------------------------------------------

      if (song.source == 'youtube' &&
          song.id.isNotEmpty) {
        // Validar videoId antes de intentar reproducir
        if (!_isValidYouTubeVideoId(song.id)) {
          debugPrint('[RecommendationSections] videoId inválido: ${song.id}');

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Esta canción tiene un ID inválido y no se puede reproducir.'),
              ),
            );
          }

          // Eliminar esta canción del historial
          await _recommendations.removeInvalidSong(song.id);

          return;
        }

        debugPrint('[RecommendationSections] Es canción YouTube, videoId: ${song.id}');

        final result =
            YouTubeSearchResult(
          videoId: song.id,
          title: song.title,
          artist: song.artist,
          duration:
              song.durationSeconds,
          thumbnail:
              song.thumbnail,
          url:
              'https://www.youtube.com/watch?v=${song.id}',
        );

        final ok =
            await widget.player.playOnline(
          result,
        );

        if (!ok && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
            SnackBar(
              content: Text(
                'No se pudo reproducir: '
                '${widget.player.playbackError ?? 'error desconocido'}',
              ),
            ),
          );
        }

        return;
      }

      /// --------------------------------------------------------
      /// CANCIÓN LOCAL
      /// --------------------------------------------------------

      final localSong =
          _findLocalSong(song);

      if (localSong != null) {
        debugPrint('[RecommendationSections] Es canción local');
        await widget.player.playSong(
          localSong,
        );

        return;
      }

      /// --------------------------------------------------------
      /// NO ENCONTRADA
      /// --------------------------------------------------------

      debugPrint('[RecommendationSections] Canción no encontrada, source: ${song.source}, id: ${song.id}');

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(
            content: Text(
              'Esta canción ya no está disponible.',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint(
        '[RecommendationSections] '
        'Error reproduciendo recomendación: $e',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo reproducir la canción.',
          ),
        ),
      );
    }
  }

  bool _isValidYouTubeVideoId(String videoId) {
    if (videoId.isEmpty) return false;
    if (videoId.length < 10 || videoId.length > 12) return false;
    final validPattern = RegExp(r'^[a-zA-Z0-9_-]+$');
    return validPattern.hasMatch(videoId);
  }

  Song? _findLocalSong(
    LearnedSong learned,
  ) {
    for (final song
        in widget.player.songs) {
      if (song.id.toString() ==
          learned.id) {
        return song;
      }

      // Para canciones de YouTube, también comparar por videoId
      if (song.isOnline && song.onlineVideoId == learned.id) {
        return song;
      }
    }

    return null;
  }

  // ============================================================
  // LOADING
  // ============================================================

  Widget _buildLoading() {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        _buildLoadingTitle(),

        const SizedBox(height: 16),

        SizedBox(
          height: 218,
          child: ListView.separated(
            scrollDirection:
                Axis.horizontal,
            physics:
                const NeverScrollableScrollPhysics(),
            itemCount: 3,
            separatorBuilder:
                (_, __) =>
                    const SizedBox(
              width: 14,
            ),
            itemBuilder:
                (_, __) {
              return _buildSkeletonCard();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingTitle() {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Container(
          width: 140,
          height: 23,
          decoration:
              BoxDecoration(
            color:
                Colors.white.withOpacity(
              0.07,
            ),
            borderRadius:
                BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 7),
        Container(
          width: 230,
          height: 13,
          decoration:
              BoxDecoration(
            color:
                Colors.white.withOpacity(
              0.045,
            ),
            borderRadius:
                BorderRadius.circular(6),
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonCard() {
    return SizedBox(
      width: 158,
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Container(
            width: 158,
            height: 158,
            decoration:
                BoxDecoration(
              color:
                  Colors.white.withOpacity(
                0.055,
              ),
              borderRadius:
                  BorderRadius.circular(
                18,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: 120,
            height: 14,
            decoration:
              BoxDecoration(
            color:
                Colors.white.withOpacity(
              0.055,
            ),
            borderRadius:
                BorderRadius.circular(5),
          ),
          ),
          const SizedBox(height: 7),
          Container(
            width: 90,
            height: 11,
            decoration:
              BoxDecoration(
            color:
                Colors.white.withOpacity(
              0.04,
            ),
            borderRadius:
                BorderRadius.circular(5),
          ),
          ),
        ],
      ),
    );
  }
}

enum RecommendationSectionStyle {
  mix,
  standard,
  discovery,
}

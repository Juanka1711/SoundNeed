import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'music_player.dart';
import 'full_player.dart';

// ============================================================
// COLORES BASE
// ============================================================

class AppColors {
  static const Color background = Color(0xFF0B0B12);
  static const Color surface = Color(0xFF151522);
  static const Color card = Color(0xFF1D1D2B);
  static const Color textSecondary = Color(0xFFA1A1AA);
}

// ============================================================
// MINI PLAYER
// ============================================================

class MiniPlayer extends StatefulWidget {
  final MusicPlayerController player;

  const MiniPlayer({
    super.key,
    required this.player,
  });

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  // ==========================================================
  // TEMA EXTRAÍDO DE LA PORTADA
  // ==========================================================

  Color _themeColor = Colors.white;
  Color _themeSecondary = Colors.white;
  Color _themeDark = const Color(0xFF151515);

  // Para evitar recalcular la portada constantemente.
  int? _lastSongId;

  // ==========================================================
  // MODO DEL ICONO DE REPRODUCCIÓN
  //
  // 0 = aleatorio
  // 1 = repetir todo
  // 2 = repetir una
  // ==========================================================

  int _playMode = 0;

  @override
  void initState() {
    super.initState();

    widget.player.addListener(_onPlayerChanged);

    _updateThemeFromArtwork(
      force: true,
    );
  }

  @override
  void dispose() {
    widget.player.removeListener(_onPlayerChanged);
    super.dispose();
  }

  // ==========================================================
  // CAMBIOS DEL PLAYER
  // ==========================================================

  void _onPlayerChanged() {
    if (!mounted) return;

    final song = widget.player.currentSong;

    if (song != null && song.id != _lastSongId) {
      _updateThemeFromArtwork(
        force: true,
      );
    }

    setState(() {});
  }

  // ==========================================================
  // EXTRAER TEMA DE LA PORTADA
  // ==========================================================

  Future<void> _updateThemeFromArtwork({
    bool force = false,
  }) async {
    final song = widget.player.currentSong;

    if (song == null) return;

    if (!force && song.id == _lastSongId) {
      return;
    }

    _lastSongId = song.id;

    try {
      final artwork = await widget.player.loadArtwork(song);

      if (artwork == null || artwork.isEmpty) {
        if (!mounted) return;

        setState(() {
          _themeColor = Colors.white;
          _themeSecondary = Colors.white70;
          _themeDark = AppColors.card;
        });

        return;
      }

      final colors = await _extractArtworkTheme(
        artwork,
      );

      if (!mounted) return;

      setState(() {
        _themeColor = colors.primary;
        _themeSecondary = colors.secondary;
        _themeDark = colors.dark;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _themeColor = Colors.white;
        _themeSecondary = Colors.white70;
        _themeDark = AppColors.card;
      });
    }
  }

  // ==========================================================
  // ANALIZAR TODA LA IMAGEN
  // ==========================================================

  Future<_ArtworkTheme> _extractArtworkTheme(
    Uint8List bytes,
  ) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 24,
      targetHeight: 24,
    );

    final frame = await codec.getNextFrame();

    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );

    codec.dispose();

    if (data == null || data.lengthInBytes < 4) {
      return _ArtworkTheme(
        primary: Colors.white,
        secondary: Colors.white70,
        dark: AppColors.card,
      );
    }

    final List<_ColorSample> samples = [];

    for (
      int offset = 0;
      offset + 3 < data.lengthInBytes;
      offset += 4
    ) {
      final r = data.getUint8(offset);
      final g = data.getUint8(offset + 1);
      final b = data.getUint8(offset + 2);
      final a = data.getUint8(offset + 3);

      if (a < 180) {
        continue;
      }

      final color = Color.fromARGB(
        255,
        r,
        g,
        b,
      );

      final hsl = HSLColor.fromColor(color);

      // Ignorar colores casi negros.
      if (hsl.lightness < 0.08) {
        continue;
      }

      // Ignorar colores completamente grises.
      if (hsl.saturation < 0.10 &&
          hsl.lightness > 0.20 &&
          hsl.lightness < 0.85) {
        continue;
      }

      // Preferimos colores con cierta saturación
      // y luminosidad intermedia.
      final saturationScore =
          hsl.saturation.clamp(0.0, 1.0);

      final lightnessScore =
          1.0 -
          ((hsl.lightness - 0.52).abs() / 0.52)
              .clamp(0.0, 1.0);

      final score =
          saturationScore * 0.65 +
          lightnessScore * 0.35;

      samples.add(
        _ColorSample(
          color: color,
          score: score,
        ),
      );
    }

    if (samples.isEmpty) {
      return _ArtworkTheme(
        primary: Colors.white,
        secondary: Colors.white70,
        dark: AppColors.card,
      );
    }

    // Ordenamos por relevancia visual.
    samples.sort(
      (a, b) => b.score.compareTo(a.score),
    );

    final primary =
        _prepareThemeColor(
      samples.first.color,
    );

    // Buscar un segundo color suficientemente diferente.
    Color secondary = primary;

    for (final sample in samples.skip(1)) {
      final candidate =
          _prepareThemeColor(sample.color);

      if (_colorDistance(
            primary,
            candidate,
          ) >
          0.18) {
        secondary = candidate;
        break;
      }
    }

    // Si no encontramos uno diferente,
    // usamos una variación del principal.
    if (secondary == primary) {
      final hsl = HSLColor.fromColor(
        primary,
      );

      secondary = hsl
          .withLightness(
            (hsl.lightness + 0.12)
                .clamp(0.0, 1.0),
          )
          .toColor();
    }

    // Fondo oscuro derivado del color principal.
    final darkHsl = HSLColor.fromColor(
      primary,
    );

    final dark = darkHsl
        .withLightness(0.07)
        .withSaturation(
          (darkHsl.saturation * 0.75)
              .clamp(0.0, 1.0),
        )
        .toColor();

    return _ArtworkTheme(
      primary: primary,
      secondary: secondary,
      dark: dark,
    );
  }

  // ==========================================================
  // PREPARAR COLOR PARA UI
  // ==========================================================

  Color _prepareThemeColor(Color color) {
    final hsl = HSLColor.fromColor(color);

    double saturation = hsl.saturation;

    if (saturation < 0.35) {
      saturation = 0.35;
    }

    if (saturation > 0.90) {
      saturation = 0.90;
    }

    double lightness = hsl.lightness;

    if (lightness < 0.30) {
      lightness = 0.48;
    }

    if (lightness > 0.78) {
      lightness = 0.62;
    }

    return hsl
        .withSaturation(saturation)
        .withLightness(lightness)
        .toColor();
  }

  // ==========================================================
  // DISTANCIA ENTRE COLORES
  // ==========================================================

  double _colorDistance(
    Color a,
    Color b,
  ) {
    final ahsl = HSLColor.fromColor(a);
    final bhsl = HSLColor.fromColor(b);

    final hueDistance =
        (ahsl.hue - bhsl.hue).abs() / 360.0;

    final saturationDistance =
        (ahsl.saturation -
                bhsl.saturation)
            .abs();

    final lightnessDistance =
        (ahsl.lightness -
                bhsl.lightness)
            .abs();

    return hueDistance * 0.5 +
        saturationDistance * 0.3 +
        lightnessDistance * 0.2;
  }

  // ==========================================================
  // CAMBIAR MODO DE REPRODUCCIÓN
  //
  // UN SOLO BOTÓN.
  //
  // 🔀 → 🔁 → 🔂 → 🔀
  // ==========================================================

  void _changePlayMode() {
    setState(() {
      _playMode++;

      if (_playMode > 2) {
        _playMode = 0;
      }
    });

    // ----------------------------------------------------------
    // ALEATORIO
    // ----------------------------------------------------------

    if (_playMode == 0) {
      if (!widget.player.shuffleEnabled) {
        widget.player.toggleShuffle();
      }
    }

    // ----------------------------------------------------------
    // REPETIR TODO
    // ----------------------------------------------------------

    else if (_playMode == 1) {
      if (widget.player.shuffleEnabled) {
        widget.player.toggleShuffle();
      }

      widget.player.toggleRepeat();
    }

    // ----------------------------------------------------------
    // REPETIR UNA
    // ----------------------------------------------------------
    //
    // El icono queda preparado para este modo.
    // La reproducción real de "repeat one" deberá manejarse
    // en MusicPlayerController.
    // ----------------------------------------------------------

    else if (_playMode == 2) {
      if (widget.player.shuffleEnabled) {
        widget.player.toggleShuffle();
      }

      // La lógica real de repeat-one se añadirá
      // en MusicPlayerController.
    }
  }

  // ==========================================================
  // ICONO DEL MODO
  // ==========================================================

  IconData get _playModeIcon {
    switch (_playMode) {
      case 1:
        return Icons.repeat;

      case 2:
        return Icons.repeat_one;

      default:
        return Icons.shuffle;
    }
  }

  // ==========================================================
  // MINI PLAYER
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final song = widget.player.currentSong;

    if (song == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        10,
        0,
        10,
        10,
      ),
      child: GestureDetector(
        // ======================================================
        // GESTOS
        //
        // IZQUIERDA  → SIGUIENTE
        // DERECHA    → ANTERIOR
        // ======================================================

        onHorizontalDragEnd: (details) {
          final velocity =
              details.primaryVelocity ?? 0;

          if (velocity < -250) {
            widget.player.nextSong();
          } else if (velocity > 250) {
            widget.player.previousSong();
          }
        },

        child: AnimatedContainer(
          duration: const Duration(
            milliseconds: 450,
          ),
          curve: Curves.easeOutCubic,

          // ====================================================
          // FORMA DE SEMICÍRCULO / CÁPSULA
          // ====================================================

          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(36),

            // ==================================================
            // FONDO DINÁMICO
            // ==================================================

            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                _themeDark,
                Color.lerp(
                  _themeDark,
                  _themeColor,
                  0.20,
                )!,
                Color.lerp(
                  _themeDark,
                  _themeSecondary,
                  0.12,
                )!,
              ],
            ),

            border: Border.all(
              color:
                  _themeColor.withOpacity(0.20),
              width: 1,
            ),

            // ==================================================
            // SOMBRA
            // ==================================================

            boxShadow: [
              BoxShadow(
                color:
                    _themeColor.withOpacity(0.16),
                blurRadius: 24,
                spreadRadius: -5,
                offset: const Offset(
                  0,
                  8,
                ),
              ),
              const BoxShadow(
                color: Colors.black54,
                blurRadius: 16,
                spreadRadius: -5,
                offset: Offset(
                  0,
                  7,
                ),
              ),
            ],
          ),

          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(36),

            child: Stack(
              children: [
                // ==============================================
                // BRILLO AMBIENTAL
                // ==============================================

                Positioned(
                  left: -35,
                  top: -35,
                  bottom: -35,
                  width: 130,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _themeColor
                          .withOpacity(0.08),
                    ),
                  ),
                ),

                // ==============================================
                // CONTENIDO
                // ==============================================

                Padding(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      // ========================================
                      // PORTADA
                      // ========================================

                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  FullPlayer(
                                player:
                                    widget.player,
                              ),
                            ),
                          );
                        },
                        child:
                            _buildArtwork(
                          song,
                          size: 58,
                        ),
                      ),

                      const SizedBox(
                        width: 12,
                      ),

                      // ========================================
                      // INFORMACIÓN
                      // ========================================

                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) =>
                                        FullPlayer(
                                  player:
                                      widget.player,
                                ),
                              ),
                            );
                          },
                          child: Column(
                            mainAxisAlignment:
                                MainAxisAlignment
                                    .center,
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              Text(
                                song.title.isEmpty
                                    ? song
                                        .displayName
                                    : song.title,
                                maxLines: 1,
                                overflow:
                                    TextOverflow
                                        .ellipsis,
                                style:
                                    const TextStyle(
                                  color:
                                      Colors.white,
                                  fontSize: 14,
                                  fontWeight:
                                      FontWeight.w700,
                                ),
                              ),
                              const SizedBox(
                                height: 3,
                              ),
                              Text(
                                song.artist
                                        .isEmpty
                                    ? 'Artista desconocido'
                                    : song.artist,
                                maxLines: 1,
                                overflow:
                                    TextOverflow
                                        .ellipsis,
                                style:
                                    TextStyle(
                                  color: Colors
                                      .white
                                      .withOpacity(
                                    0.60,
                                  ),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(
                        width: 4,
                      ),

                      // ========================================
                      // ÚNICO BOTÓN DE MODO
                      // ========================================

                      _buildModeButton(),

                      const SizedBox(
                        width: 3,
                      ),

                      // ========================================
                      // PLAY / PAUSE + PROGRESO
                      // ========================================

                      _buildProgressPlayButton(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // BOTÓN DEL MODO DE REPRODUCCIÓN
  // ==========================================================

  Widget _buildModeButton() {
    final active =
        _playMode != 0 ||
        widget.player.shuffleEnabled;

    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder:
            const CircleBorder(),
        onTap: _changePlayMode,
        child: SizedBox(
          width: 44,
          height: 44,
          child: AnimatedSwitcher(
            duration: const Duration(
              milliseconds: 180,
            ),
            transitionBuilder:
                (child, animation) {
              return ScaleTransition(
                scale: animation,
                child: child,
              );
            },
            child: Icon(
              _playModeIcon,
              key: ValueKey(
                _playMode,
              ),
              size: 21,
              color: active
                  ? _themeColor
                  : Colors.white60,
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // PLAY / PAUSE CON PROGRESO CIRCULAR
  // ==========================================================

  Widget _buildProgressPlayButton() {
    return StreamBuilder<Duration>(
      stream: widget
          .player
          .audioPlayer
          .positionStream,
      builder: (context, snapshot) {
        final position =
            snapshot.data ?? Duration.zero;

        final duration =
            widget.player.audioPlayer.duration ??
                Duration(
                  milliseconds:
                      widget.player.currentSong
                              ?.duration ??
                          0,
                );

        final total =
            duration.inMilliseconds;

        double progress = 0;

        if (total > 0) {
          progress =
              position.inMilliseconds /
                  total;

          progress =
              progress.clamp(
            0.0,
            1.0,
          );
        }

        return SizedBox(
          width: 50,
          height: 50,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ================================================
              // CÍRCULO BASE
              // ================================================

              SizedBox(
                width: 46,
                height: 46,
                child:
                    CircularProgressIndicator(
                  value: 1,
                  strokeWidth: 3,
                  color: Colors.white
                      .withOpacity(
                    0.10,
                  ),
                ),
              ),

              // ================================================
              // PROGRESO
              // ================================================

              SizedBox(
                width: 46,
                height: 46,
                child:
                    CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 3.5,
                  color: _themeColor,
                  strokeCap:
                      StrokeCap.round,
                ),
              ),

              // ================================================
              // BOTÓN
              // ================================================

              Material(
                color: Colors.transparent,
                shape:
                    const CircleBorder(),
                child: InkWell(
                  customBorder:
                      const CircleBorder(),
                  onTap: widget
                      .player
                      .togglePlayPause,
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: AnimatedSwitcher(
                      duration:
                          const Duration(
                        milliseconds: 150,
                      ),
                      transitionBuilder:
                          (
                        child,
                        animation,
                      ) {
                        return ScaleTransition(
                          scale: animation,
                          child: child,
                        );
                      },
                      child: Icon(
                        widget.player.isPlaying
                            ? Icons.pause_rounded
                            : Icons
                                .play_arrow_rounded,
                        key: ValueKey(
                          widget.player
                              .isPlaying,
                        ),
                        size: 25,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================================
  // PORTADA
  // ==========================================================

  Widget _buildArtwork(
    Song song, {
    double size = 58,
  }) {
    return FutureBuilder<Uint8List?>(
      future: widget.player.loadArtwork(song),
      builder: (context, snapshot) {
        if (snapshot.hasData &&
            snapshot.data != null) {
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: _themeColor
                      .withOpacity(0.25),
                  blurRadius: 12,
                  spreadRadius: -3,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius:
                  BorderRadius.circular(18),
              child: Image.memory(
                snapshot.data!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          );
        }

        return AnimatedContainer(
          duration:
              const Duration(
            milliseconds: 350,
          ),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: _themeColor
                .withOpacity(0.16),
            borderRadius:
                BorderRadius.circular(18),
            border: Border.all(
              color: _themeColor
                  .withOpacity(0.28),
            ),
          ),
          child: Icon(
            Icons.music_note_rounded,
            size: size * 0.42,
            color: _themeColor,
          ),
        );
      },
    );
  }
}

// ============================================================
// MODELO DEL TEMA DE LA PORTADA
// ============================================================

class _ArtworkTheme {
  final Color primary;
  final Color secondary;
  final Color dark;

  const _ArtworkTheme({
    required this.primary,
    required this.secondary,
    required this.dark,
  });
}

// ============================================================
// MUESTRA DE COLOR
// ============================================================

class _ColorSample {
  final Color color;
  final double score;

  const _ColorSample({
    required this.color,
    required this.score,
  });
}

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'music_player.dart';

// ============================================================
// COLORES BASE DE SOUNDNEED
// ============================================================

class AppColors {
  static const Color background = Color(0xFF0B0B12);
  static const Color surface = Color(0xFF151522);
  static const Color card = Color(0xFF1D1D2B);
  static const Color favorite = Color(0xFFF43F5E);
  static const Color textSecondary = Color(0xFFA1A1AA);
}

// ============================================================
// FULL PLAYER
// ============================================================

class FullPlayer extends StatefulWidget {
  final MusicPlayerController player;

  const FullPlayer({
    super.key,
    required this.player,
  });

  @override
  State<FullPlayer> createState() => _FullPlayerState();
}

class _FullPlayerState extends State<FullPlayer> {
  Color _themeColor = Colors.white;
  Color _themeSecondary = Colors.white70;
  Color _themeDark = AppColors.background;

  int? _lastSongId;

  // ==========================================================
  // MODO DE REPRODUCCIÓN
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

    _updateThemeFromArtwork();
  }

  @override
  void dispose() {
    widget.player.removeListener(_onPlayerChanged);
    super.dispose();
  }

  // ==========================================================
  // PLAYER CHANGE
  // ==========================================================

  void _onPlayerChanged() {
    if (!mounted) return;

    final song = widget.player.currentSong;

    if (song != null && song.id != _lastSongId) {
      _updateThemeFromArtwork();
    }

    setState(() {});
  }

  // ==========================================================
  // TEMA DESDE PORTADA
  // ==========================================================

  Future<void> _updateThemeFromArtwork() async {
    final song = widget.player.currentSong;

    if (song == null) return;

    if (song.id == _lastSongId) return;

    _lastSongId = song.id;

    try {
      final artwork =
          await widget.player.loadArtwork(song);

      if (artwork == null || artwork.isEmpty) {
        if (!mounted) return;

        setState(() {
          _themeColor = Colors.white;
          _themeSecondary = Colors.white70;
          _themeDark = AppColors.background;
        });

        return;
      }

      final colors =
          await _extractArtworkTheme(artwork);

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
        _themeDark = AppColors.background;
      });
    }
  }

  // ==========================================================
  // ANALIZAR PORTADA
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

    if (data == null) {
      return const _ArtworkTheme(
        primary: Colors.white,
        secondary: Colors.white70,
        dark: AppColors.background,
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

      if (a < 180) continue;

      final color = Color.fromARGB(
        255,
        r,
        g,
        b,
      );

      final hsl =
          HSLColor.fromColor(color);

      if (hsl.lightness < 0.08) {
        continue;
      }

      final saturation =
          hsl.saturation.clamp(0.0, 1.0);

      final lightnessScore =
          1 -
          ((hsl.lightness - 0.50).abs() /
                  0.50)
              .clamp(0.0, 1.0);

      final score =
          saturation * 0.65 +
          lightnessScore * 0.35;

      samples.add(
        _ColorSample(
          color: color,
          score: score,
        ),
      );
    }

    if (samples.isEmpty) {
      return const _ArtworkTheme(
        primary: Colors.white,
        secondary: Colors.white70,
        dark: AppColors.background,
      );
    }

    samples.sort(
      (a, b) =>
          b.score.compareTo(a.score),
    );

    final primary =
        _prepareThemeColor(
      samples.first.color,
    );

    Color secondary = primary;

    for (final sample
        in samples.skip(1)) {
      final candidate =
          _prepareThemeColor(
        sample.color,
      );

      if (_colorDistance(
            primary,
            candidate,
          ) >
          0.18) {
        secondary = candidate;
        break;
      }
    }

    if (secondary == primary) {
      final hsl =
          HSLColor.fromColor(primary);

      secondary = hsl
          .withLightness(
            (hsl.lightness + 0.12)
                .clamp(0.0, 1.0),
          )
          .toColor();
    }

    final darkHsl =
        HSLColor.fromColor(primary);

    final dark = darkHsl
        .withLightness(0.055)
        .withSaturation(
          (darkHsl.saturation * 0.70)
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
  // PREPARAR COLOR
  // ==========================================================

  Color _prepareThemeColor(Color color) {
    final hsl =
        HSLColor.fromColor(color);

    double saturation =
        hsl.saturation;

    if (saturation < 0.35) {
      saturation = 0.35;
    }

    if (saturation > 0.90) {
      saturation = 0.90;
    }

    double lightness =
        hsl.lightness;

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
    final ahsl =
        HSLColor.fromColor(a);

    final bhsl =
        HSLColor.fromColor(b);

    return
        ((ahsl.hue - bhsl.hue).abs() /
                360) *
            0.5 +
        (ahsl.saturation -
                    bhsl.saturation)
                .abs() *
            0.3 +
        (ahsl.lightness -
                    bhsl.lightness)
                .abs() *
            0.2;
  }

  // ==========================================================
  // CAMBIAR MODO
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

    if (_playMode == 0) {
      if (!widget.player.shuffleEnabled) {
        widget.player.toggleShuffle();
      }
    } else {
      if (widget.player.shuffleEnabled) {
        widget.player.toggleShuffle();
      }

      if (_playMode == 1) {
        widget.player.toggleRepeat();
      }
    }
  }

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
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final song =
        widget.player.currentSong;

    if (song == null) {
      return const Scaffold(
        body: Center(
          child: Text(
            'No hay canción en reproducción',
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _themeDark,

      body: AnimatedContainer(
        duration:
            const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,

        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _themeColor.withOpacity(0.16),
              _themeDark,
              Colors.black,
            ],
            stops: const [
              0.0,
              0.48,
              1.0,
            ],
          ),
        ),

        child: SafeArea(
          child: Column(
            children: [
              // =================================================
              // BARRA SUPERIOR
              // =================================================

              Padding(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed:
                          () => Navigator.pop(
                        context,
                      ),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 32,
                      ),
                    ),

                    const Expanded(
                      child: Text(
                        'Reproduciendo',
                        textAlign:
                            TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight:
                              FontWeight.w600,
                        ),
                      ),
                    ),

                    // =========================================
                    // CORAZÓN
                    // =========================================

                    IconButton(
                      tooltip: widget.player
                              .isFavorite(song)
                          ? 'Quitar de favoritos'
                          : 'Añadir a favoritos',
                      onPressed: () {
                        widget.player
                            .toggleFavorite(song);

                        setState(() {});
                      },
                      icon: Icon(
                        widget.player
                                .isFavorite(song)
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 25,
                        color: widget.player
                                .isFavorite(song)
                            ? AppColors.favorite
                            : Colors.white,
                      ),
                    ),

                    // =========================================
                    // TRES PUNTOS
                    // =========================================

                    IconButton(
                      tooltip: 'Más opciones',
                      onPressed:
                          _showMoreOptions,
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        size: 26,
                      ),
                    ),
                  ],
                ),
              ),

              // =================================================
              // PORTADA
              // =================================================

              Expanded(
                child: Center(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 12,
                    ),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: _buildArtwork(
                        song,
                      ),
                    ),
                  ),
                ),
              ),

              // =================================================
              // INFORMACIÓN
              // =================================================

              Padding(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 28,
                ),
                child: Column(
                  children: [
                    Text(
                      song.title.isEmpty
                          ? song.displayName
                          : song.title,
                      maxLines: 2,
                      overflow:
                          TextOverflow.ellipsis,
                      textAlign:
                          TextAlign.center,
                      style: const TextStyle(
                        fontSize: 25,
                        height: 1.15,
                        fontWeight:
                            FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 7),

                    Text(
                      song.artist.isEmpty
                          ? 'Artista desconocido'
                          : song.artist,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      textAlign:
                          TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white
                            .withOpacity(0.62),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // =================================================
              // PROGRESO
              // =================================================

              Padding(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 24,
                ),
                child:
                    StreamBuilder<Duration>(
                  stream: widget.player
                      .audioPlayer
                      .positionStream,
                  builder:
                      (context, snapshot) {
                    final position =
                        snapshot.data ??
                            Duration.zero;

                    final duration =
                        widget.player
                                .audioPlayer
                                .duration ??
                            Duration(
                              milliseconds:
                                  song.duration,
                            );

                    final max =
                        duration.inMilliseconds >
                                0
                            ? duration
                                .inMilliseconds
                            : 1;

                    final current =
                        position.inMilliseconds
                            .clamp(0, max);

                    return Column(
                      children: [
                        SliderTheme(
                          data:
                              SliderTheme.of(
                            context,
                          ).copyWith(
                            trackHeight: 4,
                            activeTrackColor:
                                _themeColor,
                            inactiveTrackColor:
                                Colors.white
                                    .withOpacity(
                              0.16,
                            ),
                            thumbColor:
                                Colors.white,
                            thumbShape:
                                const RoundSliderThumbShape(
                              enabledThumbRadius:
                                  6,
                            ),
                            overlayColor:
                                _themeColor
                                    .withOpacity(
                              0.15,
                            ),
                          ),
                          child: Slider(
                            value:
                                current.toDouble(),
                            min: 0,
                            max:
                                max.toDouble(),
                            onChanged:
                                (value) {
                              widget.player
                                  .seek(
                                Duration(
                                  milliseconds:
                                      value
                                          .toInt(),
                                ),
                              );
                            },
                          ),
                        ),

                        Padding(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal: 4,
                          ),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment
                                    .spaceBetween,
                            children: [
                              Text(
                                widget.player
                                    .formatDuration(
                                  current,
                                ),
                                style:
                                    TextStyle(
                                  fontSize: 11,
                                  color: Colors
                                      .white
                                      .withOpacity(
                                    0.55,
                                  ),
                                ),
                              ),
                              Text(
                                widget.player
                                    .formatDuration(
                                  max,
                                ),
                                style:
                                    TextStyle(
                                  fontSize: 11,
                                  color: Colors
                                      .white
                                      .withOpacity(
                                    0.55,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 14),

              // =================================================
              // CONTROLES
              // =================================================

              Padding(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 24,
                ),
                child: Row(
                  mainAxisAlignment:
                      MainAxisAlignment
                          .spaceBetween,
                  children: [
                    // ===========================================
                    // MODO
                    // ===========================================

                    _buildSmallControl(
                      icon: _playModeIcon,
                      color: _playMode == 0
                          ? Colors.white60
                          : _themeColor,
                      onTap:
                          _changePlayMode,
                    ),

                    // ===========================================
                    // ANTERIOR
                    // ===========================================

                    _buildMainControl(
                      icon:
                          Icons.skip_previous_rounded,
                      size: 42,
                      onTap: widget
                          .player
                          .previousSong,
                    ),

                    // ===========================================
                    // PLAY
                    // ===========================================

                    _buildPlayButton(),

                    // ===========================================
                    // SIGUIENTE
                    // ===========================================

                    _buildMainControl(
                      icon:
                          Icons.skip_next_rounded,
                      size: 42,
                      onTap:
                          widget.player.nextSong,
                    ),

                    // ===========================================
                    // REPETIR
                    // ===========================================

                    _buildSmallControl(
                      icon: Icons.repeat_rounded,
                      color: widget
                              .player
                              .repeatEnabled
                          ? _themeColor
                          : Colors.white60,
                      onTap:
                          widget.player
                              .toggleRepeat,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // BOTÓN PEQUEÑO
  // ==========================================================

  Widget _buildSmallControl({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder:
            const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            icon,
            size: 24,
            color: color,
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // CONTROL PRINCIPAL
  // ==========================================================

  Widget _buildMainControl({
    required IconData icon,
    required double size,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder:
            const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 58,
          height: 58,
          child: Icon(
            icon,
            size: size,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // PLAY CON PROGRESO CIRCULAR
  // ==========================================================

  Widget _buildPlayButton() {
    return StreamBuilder<Duration>(
      stream: widget.player.audioPlayer
          .positionStream,
      builder:
          (context, snapshot) {
        final position =
            snapshot.data ??
                Duration.zero;

        final duration =
            widget.player
                    .audioPlayer
                    .duration ??
                Duration(
                  milliseconds:
                      widget.player
                              .currentSong
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
          width: 82,
          height: 82,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ===============================================
              // CÍRCULO BASE
              // ===============================================

              SizedBox(
                width: 76,
                height: 76,
                child:
                    CircularProgressIndicator(
                  value: 1,
                  strokeWidth: 4,
                  color: Colors.white
                      .withOpacity(0.12),
                ),
              ),

              // ===============================================
              // PROGRESO
              // ===============================================

              SizedBox(
                width: 76,
                height: 76,
                child:
                    CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 4,
                  strokeCap:
                      StrokeCap.round,
                  color: _themeColor,
                ),
              ),

              // ===============================================
              // BOTÓN
              // ===============================================

              Container(
                width: 62,
                height: 62,
                decoration:
                    BoxDecoration(
                  color: _themeColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _themeColor
                          .withOpacity(0.30),
                      blurRadius: 18,
                      spreadRadius: -4,
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: widget
                      .player
                      .togglePlayPause,
                  icon: Icon(
                    widget.player.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 34,
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
    Song song,
  ) {
    return FutureBuilder<Uint8List?>(
      future:
          widget.player.loadArtwork(song),
      builder:
          (context, snapshot) {
        if (snapshot.hasData &&
            snapshot.data != null) {
          return AnimatedContainer(
            duration:
                const Duration(
              milliseconds: 450,
            ),
            curve:
                Curves.easeOutCubic,
            decoration:
                BoxDecoration(
              borderRadius:
                  BorderRadius.circular(
                28,
              ),
              boxShadow: [
                BoxShadow(
                  color: _themeColor
                      .withOpacity(0.25),
                  blurRadius: 35,
                  spreadRadius: -8,
                  offset:
                      const Offset(0, 12),
                ),
                const BoxShadow(
                  color: Colors.black54,
                  blurRadius: 30,
                  spreadRadius: -10,
                  offset:
                      Offset(0, 15),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius:
                  BorderRadius.circular(
                28,
              ),
              child: Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          );
        }

        return Container(
          decoration:
              BoxDecoration(
            color: _themeColor
                .withOpacity(0.15),
            borderRadius:
                BorderRadius.circular(
              28,
            ),
            border: Border.all(
              color: _themeColor
                  .withOpacity(0.25),
            ),
          ),
          child: Icon(
            Icons.music_note_rounded,
            size: 100,
            color: _themeColor,
          ),
        );
      },
    );
  }

  // ==========================================================
  // TRES PUNTOS
  // ==========================================================

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor:
          _themeDark,
      showDragHandle: true,
      shape:
          const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(
              18,
              8,
              18,
              24,
            ),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(
                    Icons.queue_music_rounded,
                    color: _themeColor,
                  ),
                  title: const Text(
                    'Añadir a la cola',
                  ),
                  onTap: () {
                    Navigator.pop(
                      context,
                    );
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.info_outline_rounded,
                    color: _themeColor,
                  ),
                  title: const Text(
                    'Información de la canción',
                  ),
                  onTap: () {
                    Navigator.pop(
                      context,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// TEMA DE PORTADA
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

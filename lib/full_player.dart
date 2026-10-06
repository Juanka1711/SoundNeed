import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'lyrics_service.dart';
import 'music_player.dart';
import 'mini_player.dart';
import 'playlist_actions.dart';

class FullPlayer extends StatefulWidget {
  final MusicPlayerController player;

  const FullPlayer({super.key, required this.player});

  @override
  State<FullPlayer> createState() => _FullPlayerState();
}

class _FullPlayerState extends State<FullPlayer>
    with SingleTickerProviderStateMixin {
  MusicPlayerController get player => widget.player;

  Color _themeColor = Colors.white;
  Color _themeSecondary = Colors.white70;
  Color _themeDark = const Color(0xFF080808);

  int? _lastSongId;
  double _dismissProgress = 0;
  bool _draggingToDismiss = false;
  final Map<int, LyricsData?> _lyricsBySongId = {};
  final Map<int, Future<LyricsData?>> _lyricsFutures = {};

  late final AnimationController _songAnimationController;
  late final Animation<double> _songScale;
  late final Animation<double> _songOpacity;
  late final Animation<double> _songWidth;

  @override
  void initState() {
    super.initState();

    _songAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );

    _songScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _songAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _songOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _songAnimationController, curve: Curves.easeOut),
    );

    _songWidth = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(
        parent: _songAnimationController,
        curve: Curves.easeOutBack,
      ),
    );

    player.addListener(_onPlayerChanged);

    _onPlayerChanged();
  }

  @override
  void dispose() {
    player.removeListener(_onPlayerChanged);
    _songAnimationController.dispose();
    super.dispose();
  }

  void _onPlayerChanged() {
    final song = player.currentSong;

    if (song == null) return;

    if (_lastSongId != song.id) {
      _lastSongId = song.id;

      _songAnimationController.forward(from: 0);

      _updateThemeFromArtwork(song);
      _loadLyrics(song);
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<LyricsData?> _loadLyrics(dynamic song) {
    final songId = song.id as int;
    final existing = _lyricsFutures[songId];
    if (existing != null) return existing;

    final title = song.title.toString().trim();
    final displayName = song.displayName.toString().trim();
    final missingTitle =
        title.isEmpty ||
        const {
          'sin título',
          'untitled',
          'unknown title',
        }.contains(title.toLowerCase());
    final future = LyricsService.instance.getLyrics(
      title: missingTitle && displayName.isNotEmpty ? displayName : title,
      artist: song.artist.toString(),
      alternateTitle: displayName,
      album: song.album.toString(),
      duration: song.duration is int && song.duration > 0
          ? Duration(milliseconds: song.duration as int)
          : player.audioPlayer.duration,
      isOnline: song.isOnline == true,
    );
    _lyricsFutures[songId] = future;
    future.then((lyrics) {
      _lyricsBySongId[songId] = lyrics;
      if (mounted && player.currentSong?.id == songId) setState(() {});
    });
    return future;
  }

  Future<void> _updateThemeFromArtwork(dynamic song) async {
    try {
      final bytes = await player.loadArtwork(song);

      if (bytes == null || bytes.isEmpty) return;

      final colors = await _extractArtworkTheme(bytes);

      if (!mounted) return;

      setState(() {
        _themeColor = colors.$1;
        _themeSecondary = colors.$2;
        _themeDark = colors.$3;
      });
    } catch (_) {}
  }

  Future<(Color, Color, Color)> _themeForLyricsSong(dynamic song) async {
    final bytes = await player.loadArtwork(song);
    if (bytes == null || bytes.isEmpty) {
      return (Colors.white, Colors.white70, const Color(0xFF080808));
    }
    return _extractArtworkTheme(bytes);
  }

  Future<(Color, Color, Color)> _extractArtworkTheme(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 24,
        targetHeight: 24,
      );

      final frame = await codec.getNextFrame();
      final image = frame.image;

      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );

      if (byteData == null) {
        return (Colors.white, Colors.white70, const Color(0xFF080808));
      }

      final pixels = byteData.buffer.asUint8List();

      final List<Color> candidates = [];

      for (int i = 0; i + 3 < pixels.length; i += 4) {
        final r = pixels[i];
        final g = pixels[i + 1];
        final b = pixels[i + 2];
        final a = pixels[i + 3];

        if (a < 100) continue;

        final color = Color.fromARGB(a, r, g, b);

        final hsl = HSLColor.fromColor(color);

        if (hsl.lightness < 0.10) continue;

        if (hsl.saturation < 0.12 && hsl.lightness > 0.90) {
          continue;
        }

        candidates.add(color);
      }

      if (candidates.isEmpty) {
        return (Colors.white, Colors.white70, const Color(0xFF080808));
      }

      Color primary = candidates.first;

      double bestScore = -double.infinity;

      for (final color in candidates) {
        final hsl = HSLColor.fromColor(color);

        double score = 0;

        score += hsl.saturation * 2.2;
        score += (1 - (hsl.lightness - 0.50).abs()) * 1.3;

        if (hsl.lightness < 0.16) {
          score -= 2;
        }

        if (hsl.lightness > 0.90) {
          score -= 0.8;
        }

        if (score > bestScore) {
          bestScore = score;
          primary = color;
        }
      }

      Color secondary = candidates.first;

      double secondaryScore = -double.infinity;

      for (final color in candidates) {
        final distance = _colorDistance(primary, color);

        final hsl = HSLColor.fromColor(color);

        double score = distance;
        score += hsl.saturation * 0.8;

        if (score > secondaryScore) {
          secondaryScore = score;
          secondary = color;
        }
      }

      final primaryHsl = HSLColor.fromColor(primary);

      final dark = primaryHsl
          .withLightness((primaryHsl.lightness * 0.20).clamp(0.035, 0.16))
          .toColor();

      return (primary, secondary, dark);
    } catch (_) {
      return (Colors.white, Colors.white70, const Color(0xFF080808));
    }
  }

  double _colorDistance(Color a, Color b) {
    final dr = a.red - b.red;
    final dg = a.green - b.green;
    final db = a.blue - b.blue;

    return (dr * dr + dg * dg + db * db).toDouble();
  }

  IconData get _playModeIcon {
    switch (player.playbackMode) {
      case MusicPlayerController.modeShuffle:
        return Icons.shuffle_rounded;

      case MusicPlayerController.modeRepeatOne:
        return Icons.repeat_one_rounded;

      case MusicPlayerController.modeRepeatAll:
        return Icons.repeat_rounded;

      default:
        return Icons.arrow_forward_rounded;
    }
  }

  String get _playModeLabel {
    switch (player.playbackMode) {
      case MusicPlayerController.modeShuffle:
        return 'Aleatorio';

      case MusicPlayerController.modeRepeatOne:
        return 'Repetir canción';

      case MusicPlayerController.modeRepeatAll:
        return 'Repetir todo';

      default:
        return 'Normal';
    }
  }

  @override
  Widget build(BuildContext context) {
    final song = player.currentSong;

    if (song == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'No hay ninguna canción',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
      );
    }

    final screenHeight = MediaQuery.sizeOf(context).height;
    return AnimatedSlide(
      offset: Offset(0, _dismissProgress),
      duration: _draggingToDismiss
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        color: _themeDark.withOpacity(1 - (_dismissProgress * 0.25)),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  children: [
                    _buildTopBar(song, screenHeight),

                    Expanded(child: _buildPlayerContent(context, song)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(dynamic song, double screenHeight) {
    final favorite = isSongLiked(player, song);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => setState(() => _draggingToDismiss = true),
      onVerticalDragUpdate: (details) {
        if (details.delta.dy > 0) {
          setState(() {
            _dismissProgress =
                (_dismissProgress + details.delta.dy / screenHeight).clamp(
                  0.0,
                  0.75,
                );
          });
        }
      },
      onVerticalDragEnd: (details) {
        final shouldDismiss =
            _dismissProgress > 0.18 || (details.primaryVelocity ?? 0) > 850;
        if (shouldDismiss) {
          Navigator.of(context).pop();
        } else {
          setState(() {
            _draggingToDismiss = false;
            _dismissProgress = 0;
          });
        }
      },
      onVerticalDragCancel: () => setState(() {
        _draggingToDismiss = false;
        _dismissProgress = 0;
      }),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: Row(
          children: [
            _glassButton(
              icon: favorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: favorite ? Colors.redAccent : Colors.white,
              onTap: () async {
                await toggleSongLiked(player, song);
                if (mounted) setState(() {});
              },
            ),

            const Spacer(),

            _glassButton(
              icon: Icons.more_horiz_rounded,
              onTap: () => _showMoreOptions(context, song),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerContent(BuildContext context, dynamic song) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 4),

          _buildArtwork(song),

          const SizedBox(height: 18),

          _buildDynamicSongInfo(song),

          const SizedBox(height: 14),

          _buildProgress(),

          const SizedBox(height: 6),

          _buildMainControls(),

          const SizedBox(height: 14),

          _buildSecondaryControls(),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildArtwork(dynamic song) {
    return FutureBuilder<Uint8List?>(
      future: player.loadArtwork(song),
      builder: (context, snapshot) {
        final bytes = snapshot.data;

        return LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = MediaQuery.of(context).size.width;

            final availableHeight = MediaQuery.sizeOf(context).height;
            final size = (screenWidth * 0.82)
                .clamp(180.0, 390.0)
                .clamp(0.0, availableHeight * 0.40)
                .toDouble();

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (_) =>
                  setState(() => _draggingToDismiss = true),
              onVerticalDragUpdate: (details) {
                if (details.delta.dy > 0) {
                  setState(() {
                    _dismissProgress =
                        (_dismissProgress +
                                details.delta.dy /
                                    MediaQuery.sizeOf(context).height)
                            .clamp(0.0, 0.75);
                  });
                }
              },
              onVerticalDragEnd: (details) {
                if (_dismissProgress > 0.18 ||
                    (details.primaryVelocity ?? 0) > 850) {
                  Navigator.of(context).pop();
                } else {
                  setState(() {
                    _draggingToDismiss = false;
                    _dismissProgress = 0;
                  });
                }
              },
              onVerticalDragCancel: () => setState(() {
                _draggingToDismiss = false;
                _dismissProgress = 0;
              }),
              child: Hero(
                tag: 'full_player_artwork_${song.id}',
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: _themeColor.withOpacity(0.24),
                        blurRadius: 45,
                        spreadRadius: 2,
                        offset: const Offset(0, 18),
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.55),
                        blurRadius: 30,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: bytes != null
                      ? Image.memory(
                          bytes,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        )
                      : Container(
                          color: Colors.white.withOpacity(0.05),
                          child: Icon(
                            Icons.music_note_rounded,
                            size: 72,
                            color: Colors.white.withOpacity(0.25),
                          ),
                        ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDynamicSongInfo(dynamic song) {
    final title = song.title.toString().trim();
    final artist = song.artist.toString().trim();

    return AnimatedBuilder(
      animation: _songAnimationController,
      builder: (context, child) {
        return Opacity(
          opacity: _songOpacity.value,
          child: Transform.scale(
            scale: _songScale.value,
            child: FractionallySizedBox(
              widthFactor: _songWidth.value,
              child: Container(
                constraints: const BoxConstraints(minHeight: 68),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  color: Colors.white.withOpacity(0.055),
                  border: Border.all(color: Colors.white.withOpacity(0.075)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 380),
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: animation,
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        title,
                        key: ValueKey('title_${song.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.35,
                        ),
                      ),
                    ),

                    const SizedBox(height: 3),

                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 420),
                      child: Text(
                        artist.isEmpty ? 'Artista desconocido' : artist,
                        key: ValueKey('artist_${song.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _themeSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgress() {
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: Duration.zero,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;

        final duration =
            player.audioPlayer.duration ?? const Duration(seconds: 1);

        final totalMs = duration.inMilliseconds;
        final currentMs = position.inMilliseconds;

        final value = totalMs <= 0
            ? 0.0
            : (currentMs / totalMs).clamp(0.0, 1.0);

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: _themeColor,
                inactiveTrackColor: Colors.white.withOpacity(0.12),
                thumbColor: _themeColor,
                overlayColor: _themeColor.withOpacity(0.12),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
              ),
              child: Slider(
                value: value,
                onChanged: (newValue) {
                  final target = Duration(
                    milliseconds: (duration.inMilliseconds * newValue).round(),
                  );

                  player.seek(target);
                },
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    player.formatDuration(position.inMilliseconds),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.52),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    player.formatDuration(duration.inMilliseconds),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.52),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMainControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _controlButton(
          icon: Icons.skip_previous_rounded,
          size: 29,
          onTap: player.previousSong,
        ),

        const SizedBox(width: 30),

        _buildPlayButton(),

        const SizedBox(width: 30),

        _controlButton(
          icon: Icons.skip_next_rounded,
          size: 29,
          onTap: player.nextSong,
        ),
      ],
    );
  }

  Widget _buildPlayButton() {
    return StreamBuilder<bool>(
      stream: player.audioPlayer.playingStream,
      initialData: player.isPlaying,
      builder: (context, snapshot) {
        final playing = snapshot.data ?? false;

        return AnimatedBuilder(
          animation: player,
          builder: (context, _) => Semantics(
            button: true,
            label: player.isDownloading
                ? 'Descargando canción'
                : (playing ? 'Pausar' : 'Reproducir'),
            child: SizedBox(
              width: 84,
              height: 84,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (player.isDownloading)
                    SizedBox(
                      width: 82,
                      height: 82,
                      child: CircularProgressIndicator(
                        value: player.downloadProgress,
                        strokeWidth: 3,
                        color: _themeColor,
                        backgroundColor: Colors.white.withOpacity(0.20),
                      ),
                    ),
                  Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: player.togglePlayPause,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _themeColor,
                          boxShadow: [
                            BoxShadow(
                              color: _themeColor.withOpacity(0.38),
                              blurRadius: 26,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(scale: animation, child: child),
                          child: Icon(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            key: ValueKey(playing),
                            color: Colors.black,
                            size: 39,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSecondaryControls() {
    return SizedBox(
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // COLA
          _smallActionButton(
            icon: Icons.queue_music_rounded,
            onTap: () => _showQueue(context),
          ),

          const SizedBox(width: 10),

          // LETRAS — ELEMENTO CENTRAL
          Flexible(child: _buildLyricsCapsule(player.currentSong)),

          const SizedBox(width: 10),

          // MODO DE REPRODUCCIÓN
          _smallModeButton(),
        ],
      ),
    );
  }

  Widget _smallModeButton() {
    return GestureDetector(
      onTap: () {
        player.cyclePlaybackMode();

        setState(() {});
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _themeColor.withOpacity(0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _themeColor.withOpacity(0.22)),
        ),
        child: Icon(_playModeIcon, size: 20, color: _themeColor),
      ),
    );
  }

  Widget _buildLyricsCapsule(dynamic song) {
    final lyrics = _lyricsBySongId[song.id];
    final hasLyrics = lyrics?.hasLyrics ?? false;
    return GestureDetector(
      onTap: () {
        _openLyrics(context, song);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOutCubic,
        width: hasLyrics ? double.infinity : null,
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(21),
          color: Colors.white.withOpacity(0.065),
          border: Border.all(color: Colors.white.withOpacity(0.09)),
          boxShadow: [
            BoxShadow(color: _themeColor.withOpacity(0.07), blurRadius: 18),
          ],
        ),
        child: Row(
          mainAxisSize: hasLyrics ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lyrics_rounded, size: 17, color: _themeColor),

            const SizedBox(width: 7),

            if (hasLyrics)
              Expanded(child: _buildLyricsPreview(song, lyrics!))
            else
              const Text(
                'Letras',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLyricsPreview(dynamic song, LyricsData lyrics) {
    if (!lyrics.hasSyncedLyrics) {
      final firstLine = lyrics.plainLyrics!
          .split(RegExp(r'\r?\n'))
          .firstWhere((line) => line.trim().isNotEmpty, orElse: () => 'Letras');
      return Text(
        firstLine.trim(),
        key: ValueKey('plain_preview_${song.id}'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: Duration.zero,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        var activeIndex = -1;
        for (var i = 0; i < lyrics.lines.length; i++) {
          if (lyrics.lines[i].timestamp > position) break;
          activeIndex = i;
        }
        final line = activeIndex >= 0
            ? lyrics.lines[activeIndex].text
            : 'Letras sincronizadas';

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.22),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Text(
            line,
            key: ValueKey('${song.id}_$activeIndex'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _themeColor.withOpacity(0.98),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }

  Widget _glassButton({
    required IconData icon,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white.withOpacity(0.055),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 25,
  }) {
    return IconButton(
      onPressed: onTap,
      splashRadius: 25,
      icon: Icon(icon, color: Colors.white, size: size),
    );
  }

  Widget _smallActionButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.055),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Icon(icon, color: Colors.white.withOpacity(0.88), size: 21),
        ),
      ),
    );
  }

  void _openLyrics(BuildContext context, dynamic song) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.60),
      enableDrag: true,
      builder: (_) {
        return _LyricsSheet(
          player: player,
          song: song,
          loadLyricsForSong: _loadLyrics,
          loadThemeForSong: _themeForLyricsSong,
          themeColor: _themeColor,
          themeDark: _themeDark,
        );
      },
    );
  }

  void _showQueue(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          decoration: BoxDecoration(
            color: _themeDark,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                const SizedBox(height: 22),

                Row(
                  children: [
                    Icon(Icons.queue_music_rounded, color: _themeColor),

                    const SizedBox(width: 10),

                    const Text(
                      'Cola de reproducción',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.055),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.music_note_rounded,
                        color: Colors.white54,
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: Text(
                          player.currentSong?.title.toString() ??
                              'Canción actual',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
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
      },
    );
  }

  void _showMoreOptions(BuildContext context, dynamic song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          decoration: BoxDecoration(
            color: _themeDark,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                const SizedBox(height: 20),

                _optionTile(
                  icon: Icons.download_rounded,
                  title: 'Descargar',
                  onTap: () {
                    Navigator.pop(context);
                    _downloadSong(song);
                  },
                ),

                _optionTile(
                  icon: Icons.playlist_add_rounded,
                  title: 'Agregar a playlist',
                  onTap: () {
                    Navigator.pop(context);

                    addSongToPlaylist(context, player, song);
                  },
                ),

                _optionTile(
                  icon: Icons.favorite_rounded,
                  title: isSongLiked(player, song)
                      ? 'Quitar de favoritos'
                      : 'Agregar a favoritos',
                  onTap: () async {
                    Navigator.pop(context);

                    await toggleSongLiked(player, song);
                    if (mounted) setState(() {});
                  },
                ),

                _optionTile(
                  icon: Icons.info_outline_rounded,
                  title: 'Información',
                  onTap: () {
                    Navigator.pop(context);

                    _showSongInfo(context, song);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _downloadSong(dynamic song) async {
    try {
      await player.downloadSong(song as Song);
    } catch (error) {
      debugPrint('[SoundNeed] No se pudo descargar la canción: $error');
    }
  }

  Widget _optionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.055),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: Colors.white, size: 21),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _showSongInfo(BuildContext context, dynamic song) {
    final duration = player.audioPlayer.duration;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          decoration: BoxDecoration(
            color: _themeDark,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 30),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  song.title.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 7),

                Text(
                  song.artist.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _themeSecondary, fontSize: 14),
                ),

                const SizedBox(height: 20),

                if (duration != null)
                  Text(
                    'Duración · ${player.formatDuration(duration.inMilliseconds)}',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LyricsSheet extends StatefulWidget {
  final MusicPlayerController player;
  final dynamic song;
  final Future<LyricsData?> Function(dynamic song) loadLyricsForSong;
  final Future<(Color, Color, Color)> Function(dynamic song) loadThemeForSong;
  final Color themeColor;
  final Color themeDark;

  const _LyricsSheet({
    required this.player,
    required this.song,
    required this.loadLyricsForSong,
    required this.loadThemeForSong,
    required this.themeColor,
    required this.themeDark,
  });

  @override
  State<_LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<_LyricsSheet> {
  int _lastActiveLine = -1;
  late dynamic _currentSong;
  late Future<LyricsData?> _lyricsFuture;
  late Color _themeColor;
  late Color _themeDark;
  int _songChangeToken = 0;

  @override
  void initState() {
    super.initState();
    _currentSong = widget.player.currentSong ?? widget.song;
    _lyricsFuture = widget.loadLyricsForSong(_currentSong);
    _themeColor = widget.themeColor;
    _themeDark = widget.themeDark;
    widget.player.addListener(_onPlayerChanged);
  }

  @override
  void dispose() {
    widget.player.removeListener(_onPlayerChanged);
    super.dispose();
  }

  void _onPlayerChanged() {
    final song = widget.player.currentSong;
    if (song == null ||
        (song.id == _currentSong.id && song.uri == _currentSong.uri)) {
      return;
    }

    final token = ++_songChangeToken;
    setState(() {
      _currentSong = song;
      _lyricsFuture = widget.loadLyricsForSong(song);
      _themeColor = Colors.white;
      _themeDark = const Color(0xFF080808);
      _lastActiveLine = -1;
    });
    _updateTheme(song, token);
  }

  Future<void> _updateTheme(dynamic song, int token) async {
    try {
      final colors = await widget.loadThemeForSong(song);
      if (!mounted || token != _songChangeToken) return;
      setState(() {
        _themeColor = colors.$1;
        _themeDark = colors.$3;
      });
    } catch (_) {}
  }

  int _activeLine(List<LyricLine> lines, Duration position) {
    var active = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].timestamp > position) break;
      active = i;
    }
    return active;
  }

  void _scrollToLine(int index, ScrollController controller) {
    if (index < 0 || index == _lastActiveLine) return;
    _lastActiveLine = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!controller.hasClients) return;
      final target = (index * 68.0 - 120).clamp(
        0.0,
        controller.position.maxScrollExtent,
      );
      controller.animateTo(
        target,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.94,
      minChildSize: 0.40,
      maxChildSize: 0.98,
      expand: false,
      builder: (context, controller) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: _themeDark,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),

              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              const SizedBox(height: 12),

              MiniPlayer(player: widget.player, openFullPlayerOnTap: false),

              const SizedBox(height: 8),

              Expanded(child: _buildLyricsBody(controller)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLyricsBody(ScrollController sheetController) {
    return FutureBuilder<LyricsData?>(
      future: _lyricsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(child: CircularProgressIndicator(color: _themeColor));
        }

        final lyrics = snapshot.data;
        if (lyrics == null || !lyrics.hasLyrics) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: Text(
                'No se encontraron letras para esta canción.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ),
          );
        }

        if (!lyrics.hasSyncedLyrics) {
          return SingleChildScrollView(
            key: ValueKey(
              'plain_lyrics_${_currentSong.id}_${_currentSong.uri}',
            ),
            controller: sheetController,
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 36),
            child: Text(
              lyrics.plainLyrics!.trim(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 17,
                height: 1.8,
              ),
            ),
          );
        }

        return StreamBuilder<Duration>(
          stream: widget.player.positionStream,
          initialData: Duration.zero,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final active = _activeLine(lyrics.lines, position);
            _scrollToLine(active, sheetController);
            return ListView.builder(
              key: ValueKey(
                'synced_lyrics_${_currentSong.id}_${_currentSong.uri}',
              ),
              controller: sheetController,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 52),
              itemExtent: 68,
              itemCount: lyrics.lines.length,
              itemBuilder: (context, index) {
                final isActive = index == active;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: isActive
                        ? _themeColor.withOpacity(0.10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    scale: isActive ? 1.035 : 1,
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      style: TextStyle(
                        color: isActive ? _themeColor : Colors.white38,
                        fontSize: isActive ? 20 : 16,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w500,
                        height: 1.35,
                      ),
                      child: Center(
                        child: Text(
                          lyrics.lines[index].text,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

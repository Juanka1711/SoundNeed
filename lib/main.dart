import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'music_player.dart';
import 'music_ui.dart';
import 'services/audio_handler.dart';
import 'services/youtube_audio_service.dart';
import 'services/song_share_service.dart';
import 'services/playlist_share_service.dart';
import 'playlist_manager.dart';
import 'playlist_sharing.dart';
import 'full_player.dart';

late final SoundNeedAudioHandler soundNeedAudioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  soundNeedAudioHandler = await AudioService.init<SoundNeedAudioHandler>(
    builder: SoundNeedAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.music_player.channel.audio',
      androidNotificationChannelName: 'SoundNeed',
      androidNotificationChannelDescription:
          'Controles de reproducción de SoundNeed',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
    ),
  );

  runApp(MusicPlayerApp(audioHandler: soundNeedAudioHandler));
}

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key, required this.audioHandler});

  final SoundNeedAudioHandler audioHandler;

  // ============================================================
  // COLORES DE SOUNDNEED
  // ============================================================

  static const Color background = Color(0xFF0B0B12);
  static const Color surface = Color(0xFF151522);
  static const Color card = Color(0xFF1D1D2B);
  static const Color primary = Color(0xFF8B5CF6);
  static const Color secondary = Color(0xFFEC4899);
  static const Color favorite = Color(0xFFF43F5E);
  static const Color textSecondary = Color(0xFFA1A1AA);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SoundNeed',
      theme: ThemeData(
        brightness: Brightness.dark,
        // Shared type scale: headings feel more intentional while song and
        // supporting copy stay easy to scan across every section.
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.15,
            height: 1.08,
          ),
          displayMedium: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -.9,
            height: 1.1,
          ),
          displaySmall: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -.7,
            height: 1.12,
          ),
          headlineLarge: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -.65,
            height: 1.14,
          ),
          headlineMedium: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w700,
            letterSpacing: -.45,
            height: 1.18,
          ),
          headlineSmall: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -.3,
            height: 1.2,
          ),
          titleLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -.2,
            height: 1.25,
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -.1,
            height: 1.3,
          ),
          titleSmall: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: .05,
            height: 1.3,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            letterSpacing: .05,
            height: 1.5,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            letterSpacing: .08,
            height: 1.45,
          ),
          bodySmall: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            letterSpacing: .12,
            height: 1.4,
          ),
          labelLarge: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: .12,
            height: 1.2,
          ),
          labelMedium: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: .18,
            height: 1.2,
          ),
          labelSmall: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: .2,
            height: 1.2,
          ),
        ).apply(displayColor: Colors.white, bodyColor: Colors.white),
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: primary,
          secondary: secondary,
          surface: surface,
        ),
        useMaterial3: true,

        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -.35,
            height: 1.2,
          ),
        ),

        listTileTheme: const ListTileThemeData(
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -.12,
            height: 1.25,
          ),
          subtitleTextStyle: TextStyle(
            color: textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w400,
            letterSpacing: .08,
            height: 1.35,
          ),
        ),

        cardTheme: const CardThemeData(
          color: card,
          elevation: 0,
        ),

        dialogTheme: DialogThemeData(
          backgroundColor: surface,
          surfaceTintColor: Colors.transparent,
          elevation: 18,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: BorderSide(color: Colors.white10),
          ),
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -.45,
            height: 1.18,
          ),
          contentTextStyle: const TextStyle(
            color: textSecondary,
            fontSize: 14,
            letterSpacing: .08,
            height: 1.48,
          ),
        ),

        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: surface,
          modalBackgroundColor: surface,
          surfaceTintColor: Colors.transparent,
          elevation: 20,
          showDragHandle: true,
          dragHandleColor: Colors.white38,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            side: BorderSide(color: Colors.white10),
          ),
        ),

        popupMenuTheme: PopupMenuThemeData(
          color: surface,
          surfaceTintColor: Colors.transparent,
          elevation: 14,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Colors.white12),
          ),
          textStyle: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: .05,
            height: 1.25,
          ),
        ),

        dividerTheme: DividerThemeData(
          color: Colors.white.withValues(alpha: .08),
          thickness: 1,
          space: 1,
        ),

        sliderTheme: SliderThemeData(
          activeTrackColor: primary,
          thumbColor: secondary,
          inactiveTrackColor: Colors.white12,
          overlayColor: primary.withOpacity(0.15),
        ),

        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: primary,
        ),

        snackBarTheme: SnackBarThemeData(
          backgroundColor: card,
          contentTextStyle: const TextStyle(
            color: Colors.white,
          ),
          actionTextColor: secondary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface,
          hintStyle: const TextStyle(
            color: textSecondary,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: primary,
              width: 1.5,
            ),
          ),
        ),

        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
      home: SoundNeedHome(audioHandler: audioHandler),
    );
  }
}

class SoundNeedHome extends StatefulWidget {
  const SoundNeedHome({super.key, required this.audioHandler});

  final SoundNeedAudioHandler audioHandler;

  @override
  State<SoundNeedHome> createState() => _SoundNeedHomeState();
}

class _SoundNeedHomeState extends State<SoundNeedHome> {
  static const EventChannel _sharedSongEvents =
      EventChannel('soundneed/shared_song');
  late final MusicPlayerController _player;
  late final Future<void> _playerInitialization;
  StreamSubscription<dynamic>? _sharedSongSubscription;

  @override
  void initState() {
    super.initState();
    _player = MusicPlayerController(audioHandler: widget.audioHandler);
    _playerInitialization = _player.initialize();
    _sharedSongSubscription = _sharedSongEvents.receiveBroadcastStream().listen(
      (dynamic link) => unawaited(_openSharedSong(link.toString())),
      onError: (Object error) {
        debugPrint('[SoundNeed] No se pudo recibir el enlace compartido: $error');
      },
    );
  }

  Future<void> _openSharedSong(String link) async {
    await _playerInitialization;
    if (!mounted) return;
    var uri = Uri.tryParse(link);
    if (uri == null) return;
    if (uri.scheme == 'https' &&
        uri.host == 'soundneed-shares.breinermuleth64.workers.dev' &&
        uri.pathSegments.length == 2) {
      if (uri.pathSegments.first == 's') {
        try {
          uri = await SongShareService.resolveSongLink(uri);
        } catch (error) {
          debugPrint('[SoundNeed] No se pudo resolver la canción compartida: $error');
          uri = null;
        }
        if (!mounted || uri == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text('No se pudo abrir esta canción compartida.'),
              ),
            );
          }
          return;
        }
      } else if (uri.pathSegments.first == 'p') {
        uri = Uri(
          scheme: 'soundneed',
          host: 'playlist',
          queryParameters: {'shareId': uri.pathSegments.last},
        );
      }
    }
    if (uri.scheme != 'soundneed') return;
    if (uri.host == 'playlist') {
      await _openSharedPlaylist(uri);
      return;
    }
    if (uri.host != 'track') return;

    var title = uri.queryParameters['title']?.trim() ?? '';
    var artist = uri.queryParameters['artist']?.trim() ?? '';
    final pathVideoId = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    final videoId = (uri.queryParameters['videoId'] ?? pathVideoId).trim();
    var opened = false;

    if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) {
      if (title.isEmpty || artist.isEmpty) {
        final metadata = await YouTubeAudioService.instance.getVideoMetadata(videoId);
        title = metadata['title']?.trim().isNotEmpty == true
            ? metadata['title']!.trim()
            : 'Canción compartida';
        artist = metadata['artist']?.trim().isNotEmpty == true
            ? metadata['artist']!.trim()
            : 'SoundNeed';
      }
      final sharedResult = YouTubeSearchResult(
        videoId: videoId,
        title: title.isEmpty ? 'Canción compartida' : title,
        artist: artist.isEmpty ? 'SoundNeed' : artist,
        duration: 0,
        thumbnail: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
        url: 'https://www.youtube.com/watch?v=$videoId',
      );
      opened = await _player.playOnline(sharedResult);
    } else {
      final normalizedTitle = _sharedTrackKey(title);
      Song? localSong;
      for (final candidate in _player.songs) {
        final candidateTitle = candidate.title.isEmpty
            ? candidate.displayName
            : candidate.title;
        final sameTitle = _sharedTrackKey(candidateTitle) == normalizedTitle;
        final sameArtist = artist.isEmpty ||
            _sharedTrackKey(candidate.artist) == _sharedTrackKey(artist);
        if (sameTitle && sameArtist) {
          localSong = candidate;
          break;
        }
      }
      if (localSong != null) {
        await _player.playSong(localSong);
        opened = _player.currentSong?.id == localSong.id;
      }
    }

    if (!mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('SoundNeed no encontró esa canción en este dispositivo.'),
        ),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => FullPlayer(player: _player)),
    );
  }

  Future<void> _openSharedPlaylist(Uri uri) async {
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    ));
    var loadingDialogOpen = true;
    try {
      await PlaylistManager.instance.initialize();
      var encodedPlaylist = uri.queryParameters['p'] ?? '';
      final shareId = uri.queryParameters['shareId'];
      if (encodedPlaylist.isEmpty && shareId != null) {
        encodedPlaylist =
            await PlaylistShareService.resolvePlaylistId(shareId) ?? '';
      }
      if (encodedPlaylist.isEmpty) {
        throw const FormatException('No encontramos esta playlist compartida.');
      }
      final shared = decodeSharedPlaylist(encodedPlaylist);
      final name = shared['n']?.toString().trim().isNotEmpty == true
          ? shared['n'].toString().trim()
          : 'Playlist compartida';
      final entries = (shared['s'] as List).toList(growable: false);
      final resolved = List<Song?>.filled(entries.length, null);
      var nextIndex = 0;

      Future<void> resolveBatch() async {
        while (true) {
          final index = nextIndex++;
          if (index >= entries.length) return;
          final value = entries[index];
          if (value is! List || value.length < 3) continue;
          final videoId = value[0]?.toString() ?? '';
          final title = value[1]?.toString().trim() ?? '';
          final artist = value[2]?.toString().trim() ?? '';
          final durationMs = value.length > 3 && value[3] is num
              ? (value[3] as num).round()
              : 0;
          if (title.isEmpty) continue;

          if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) {
            resolved[index] = Song.fromYouTube(
              YouTubeSearchResult(
                videoId: videoId,
                title: title,
                artist: artist,
                duration: (durationMs / 1000).round(),
                thumbnail: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
                url: 'https://www.youtube.com/watch?v=$videoId',
              ),
            );
            continue;
          }

          final titleKey = _sharedTrackKey(title);
          final artistKey = _sharedTrackKey(artist);
          Song? localSong;
          for (final candidate in _player.songs) {
            final candidateTitle = _sharedTrackKey(
              candidate.title.isEmpty ? candidate.displayName : candidate.title,
            );
            if (candidateTitle == titleKey &&
                (artistKey.isEmpty ||
                    _sharedTrackKey(candidate.artist) == artistKey)) {
              localSong = candidate;
              break;
            }
          }
          if (localSong != null) {
            resolved[index] = localSong;
            continue;
          }

          try {
            final results = await YouTubeAudioService.instance.search(
              '$title $artist',
            );
            YouTubeSearchResult? best;
            var bestScore = 0.0;
            for (final candidate in results) {
              final candidateTitle = _sharedTrackKey(candidate.title);
              if (candidateTitle.isEmpty) continue;
              final titleMatches = candidateTitle == titleKey ||
                  candidateTitle.contains(titleKey) ||
                  titleKey.contains(candidateTitle);
              final artistMatches = artistKey.isEmpty ||
                  _sharedTrackKey(candidate.artist).contains(artistKey) ||
                  candidateTitle.contains(artistKey);
              final score = (titleMatches ? 0.75 : 0.0) +
                  (artistMatches ? 0.25 : 0.0);
              if (score > bestScore) {
                best = candidate;
                bestScore = score;
              }
            }
            if (best != null && bestScore >= 0.75) {
              resolved[index] = Song.fromYouTube(best);
            }
          } catch (_) {
            // Keep processing the remaining playlist if one lookup fails.
          }
        }
      }

      await Future.wait(
        List.generate(
          entries.length < 4 ? entries.length : 4,
          (_) => resolveBatch(),
        ),
      );
      if (mounted && loadingDialogOpen) {
        Navigator.of(context).pop();
        loadingDialogOpen = false;
      }
      if (!mounted) return;

      final songs = <Song>[];
      final seen = <String>{};
      for (final song in resolved.whereType<Song>()) {
        if (seen.add(songKey(song))) songs.add(song);
      }
      final missingCount = entries.length - songs.length;
      if (songs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('No se encontraron canciones de esa playlist.'),
          ),
        );
        return;
      }

      final manager = PlaylistManager.instance;
      var destinationId = 'new';
      final shouldSave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text(name),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${songs.length} canciones listas para guardar'
                  '${missingCount > 0 ? '\n$missingCount no se pudieron encontrar' : ''}.',
                ),
                if (manager.playlists.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text('Guardar en'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: destinationId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'new',
                        child: Text('Crear playlist nueva'),
                      ),
                      ...manager.playlists.map(
                        (playlist) => DropdownMenuItem(
                          value: playlist.id,
                          child: Text(
                            playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => destinationId = value);
                      }
                    },
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Ahora no'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.playlist_add_rounded),
                label: const Text('Guardar'),
              ),
            ],
          ),
        ),
      );
      if (shouldSave != true || !mounted) return;

      final saved = await manager.saveSharedPlaylist(
        name,
        songs,
        targetPlaylistId: destinationId == 'new' ? null : destinationId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Canciones guardadas en “${saved.name}”.'),
        ),
      );
    } catch (error) {
      if (mounted && loadingDialogOpen) {
        Navigator.of(context).pop();
        loadingDialogOpen = false;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('El enlace de la playlist no es válido.'),
          ),
        );
      }
      debugPrint('[SoundNeed] No se pudo importar la playlist: $error');
    }
  }

  String _sharedTrackKey(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]*\)|\[[^]]*\]'), '')
      .replaceAll(RegExp(r'[^a-z0-9áéíóúüñ]'), '');

  @override
  void dispose() {
    _sharedSongSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MusicHomePage(player: _player);
  }
}

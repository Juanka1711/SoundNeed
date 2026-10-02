import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'services/youtube_audio_service.dart';
import 'services/recommendation_service.dart';

class Song {
  final int id;
  final String title;
  final String displayName;
  final String artist;
  final String album;
  final int? albumId;
  final int duration;
  final String mimeType;
  final int size;
  final String uri;
  final String artworkUri;
  final bool isMusic;

  Song({
    required this.id,
    required this.title,
    required this.displayName,
    required this.artist,
    required this.album,
    required this.albumId,
    required this.duration,
    required this.mimeType,
    required this.size,
    required this.uri,
    required this.artworkUri,
    required this.isMusic,
  });

  factory Song.fromMap(Map<dynamic, dynamic> map) {
    return Song(
      id: (map['id'] as num?)?.toInt() ?? 0,
      title: map['title']?.toString() ?? 'Sin título',
      displayName: map['displayName']?.toString() ?? '',
      artist: map['artist']?.toString() ?? 'Artista desconocido',
      album: map['album']?.toString() ?? 'Álbum desconocido',
      albumId: (map['albumId'] as num?)?.toInt(),
      duration: (map['duration'] as num?)?.toInt() ?? 0,
      mimeType: map['mimeType']?.toString() ?? '',
      size: (map['size'] as num?)?.toInt() ?? 0,
      uri: map['uri']?.toString() ?? '',
      artworkUri: map['artworkUri']?.toString() ?? '',
      isMusic: map['isMusic'] == true,
    );
  }

  /// Convierte un resultado de YouTube en una Song.
  /// La URL real del audio se obtiene al reproducir.
  factory Song.fromYouTube(YouTubeSearchResult result) {
    return Song(
      id: result.videoId.hashCode & 0x7fffffff,
      title: result.title,
      displayName: result.title,
      artist: result.artist.isEmpty ? 'YouTube' : result.artist,
      album: 'YouTube',
      albumId: null,
      duration: result.duration * 1000,
      mimeType: 'youtube',
      size: 0,
      uri: result.url,
      artworkUri: result.thumbnail,
      isMusic: true,
    );
  }

  bool get isOnline => mimeType == 'youtube';

  String get onlineVideoId =>
      Uri.tryParse(uri)?.queryParameters['v'] ?? '';
}

class MusicPlayerController extends ChangeNotifier {
  static const MethodChannel _channel = MethodChannel('music_player/media');

  final AudioPlayer _audioPlayer = AudioPlayer();

  late SharedPreferences _preferences;

  List<Song> _songs = [];
  List<Song> _hiddenSongs = [];
  List<Song> _queue = [];

  Song? _currentSong;

  final Set<int> _favoriteIds = {};

  bool _loading = true;
  bool _permissionDenied = false;
  bool _isPlaying = false;

  bool _shuffleEnabled = false;
  bool _repeatEnabled = false;

  int _queueIndex = -1;

  final Map<int, Uint8List?> _artworkCache = {};
  final Map<int, Uint8List?> _onlineArtworkCache = {};

  bool _loadingOnline = false;
  int _playToken = 0;

  /// Mensaje del último error de reproducción (null si todo fue bien).
  String? playbackError;

  /// Timer para actualizar progreso en RecommendationService.
  Timer? _progressUpdateTimer;

  // Getters
  List<Song> get songs => _songs;
  List<Song> get hiddenSongs => _hiddenSongs;
  List<Song> get queue => _queue;
  Song? get currentSong => _currentSong;
  bool get loading => _loading;
  bool get permissionDenied => _permissionDenied;
  bool get isPlaying => _isPlaying;
  bool get shuffleEnabled => _shuffleEnabled;
  bool get repeatEnabled => _repeatEnabled;
  bool get loadingOnline => _loadingOnline;
  int get queueIndex => _queueIndex;
  AudioPlayer get audioPlayer => _audioPlayer;

  MusicPlayerController() {
    _audioPlayer.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      notifyListeners();
    });

    _audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _handleSongCompleted();
      }
    });
  }

  // ============================================================
  // INICIALIZACION
  // ============================================================
  Future<void> initialize() async {
    await _requestNotificationPermission();

    _preferences = await SharedPreferences.getInstance();

    final savedFavorites = _preferences.getStringList(
      'favorite_song_ids',
    );

    if (savedFavorites != null) {
      _favoriteIds.addAll(
        savedFavorites.map((id) => int.tryParse(id)).whereType<int>(),
      );
    }

    // Inicializar servicio de recomendaciones
    await RecommendationService.instance.initialize();

    await loadSongs();
  }

  // ============================================================
  // PERMISOS
  // ============================================================

  Future<bool> _checkPermission() async {
    try {
      final bool? hasPermission = await _channel.invokeMethod<bool>(
        'hasPermission',
      );

      return hasPermission ?? false;
    } catch (e) {
      debugPrint('Error comprobando permiso: $e');
      return false;
    }
  }

  Future<bool> _requestPermission() async {
    try {
      final bool? granted = await _channel.invokeMethod<bool>(
        'requestPermission',
      );

      return granted ?? false;
    } catch (e) {
      debugPrint('Error solicitando permiso: $e');
      return false;
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      await _channel.invokeMethod(
        'requestNotificationPermission',
      );
    } catch (e) {
      debugPrint(
        'Error solicitando permiso de notificaciones: $e',
      );
    }
  }

  // ============================================================
  // CANCIONES
  // ============================================================

  Future<void> loadSongs() async {
    _loading = true;
    _permissionDenied = false;
    notifyListeners();

    try {
      bool permission = await _checkPermission();

      if (!permission) {
        permission = await _requestPermission();
      }

      if (!permission) {
        _loading = false;
        _permissionDenied = true;
        notifyListeners();

        return;
      }

      final List<dynamic>? result =
          await _channel.invokeMethod<List<dynamic>>('getSongs');

      final List<Song> songs = [];

      if (result != null) {
        for (final item in result) {
          if (item is Map) {
            songs.add(Song.fromMap(item));
          }
        }
      }

      _songs = songs.where((song) => song.isMusic).toList();
      _hiddenSongs = songs.where((song) => !song.isMusic).toList();
      _loading = false;
      _permissionDenied = false;
      notifyListeners();

      // Registrar canciones locales en el servicio de recomendaciones
      final localSongsData = _songs.map((song) => {
        'id': song.id,
        'title': song.title,
        'artist': song.artist,
        'artworkUri': song.artworkUri,
        'duration': song.duration,
      }).toList();

      await RecommendationService.instance.registerLocalSongs(localSongsData);

      if (_queue.isEmpty && _songs.isNotEmpty) {
        _queue = List<Song>.from(_songs);
        _queueIndex = -1;
      }
    } catch (e) {
      debugPrint('Error cargando canciones: $e');

      _loading = false;
      notifyListeners();
    }
  }

  // ============================================================
  // FAVORITOS
  // ============================================================

  bool isFavorite(Song song) {
    return _favoriteIds.contains(song.id);
  }

  Future<void> toggleFavorite(Song song) async {
    if (_favoriteIds.contains(song.id)) {
      _favoriteIds.remove(song.id);
      await RecommendationService.instance.setFavorite(
        songId: song.id.toString(),
        favorite: false,
      );
    } else {
      _favoriteIds.add(song.id);
      await RecommendationService.instance.setFavorite(
        songId: song.id.toString(),
        favorite: true,
      );
    }

    await _saveFavorites();
    notifyListeners();
  }

  Future<void> _saveFavorites() async {
    await _preferences.setStringList(
      'favorite_song_ids',
      _favoriteIds.map((id) => id.toString()).toList(),
    );
  }

  // ============================================================
  // COLA
  // ============================================================

  void _createQueueFromSong(Song song) {
    final index = _songs.indexWhere((item) => item.id == song.id);

    if (index == -1) return;

    _queue = List<Song>.from(_songs);
    _queueIndex = index;
  }

  Future<void> playSong(
    Song song, {
    bool createQueue = true,
  }) async {
    playbackError = null;
    final token = ++_playToken;

    // Detener escucha anterior si hay una canción diferente
    if (_currentSong != null && _currentSong!.id != song.id) {
      await _stopCurrentListening();
    }

    try {
      if (createQueue && !song.isOnline) {
        _createQueueFromSong(song);
      }

      final Uri sourceUri;

      if (song.isOnline) {
        // Mostramos la canción en el mini player mientras se obtiene el audio.
        _currentSong = song;
        _loadingOnline = true;
        _isPlaying = false;
        notifyListeners();

        final audioUrl = await YouTubeAudioService.instance.getAudioUrl(
          song.onlineVideoId,
        );

        // Si el usuario eligió otra canción mientras obtenía la URL, descartamos esta.
        if (token != _playToken) {
          return;
        }

        if (audioUrl == null || audioUrl.isEmpty) {
          playbackError =
              YouTubeAudioService.instance.lastError ??
                  'No se pudo obtener el audio de YouTube';
          debugPrint('[SoundNeed] $playbackError');
          return;
        }

        sourceUri = Uri.parse(audioUrl);
      } else {
        sourceUri = Uri.parse(song.uri);
      }

      // Validar que la URI es válida antes de usarla
      if (!sourceUri.hasScheme || !sourceUri.hasAuthority) {
        playbackError = 'URL de audio inválida: ${sourceUri.toString()}';
        debugPrint('[SoundNeed] $playbackError');
        return;
      }

      final mediaItem = MediaItem(
        id: song.id.toString(),
        title: song.title.isEmpty
            ? song.displayName
            : song.title,
        artist: song.artist,
        album: song.album,
        duration: song.duration > 0
            ? Duration(milliseconds: song.duration)
            : null,
        artUri: song.isOnline && song.artworkUri.isNotEmpty
            ? Uri.tryParse(song.artworkUri)
            : null,
        playable: true,
      );

      // ============================================================
      // MANEJO ROBUSTO DE ERRORES EN REPRODUCCIÓN
      // ============================================================
      try {
        await _audioPlayer.setAudioSource(
          AudioSource.uri(
            sourceUri,
            tag: mediaItem,
          ),
        ).timeout(
          const Duration(seconds: 45),
          onTimeout: () {
            throw TimeoutException(
              'Timeout al preparar el audio (45s)',
            );
          },
        );
      } on TimeoutException catch (e) {
        playbackError = 'Timeout: No se pudo cargar el audio a tiempo. '
            'Inténtalo de nuevo o verifica tu conexión.';
        debugPrint('[SoundNeed] Timeout en setAudioSource: $e');
        return;
      } on PlayerException catch (e) {
        // Errores específicos de just_audio/MediaCodec
        final errorMsg = e.message?.toLowerCase() ?? '';
        if (errorMsg.contains('codec') ||
            errorMsg.contains('format') ||
            errorMsg.contains('decode')) {
          playbackError = 'Error de códec/decodificación: ${e.message}. '
              'El formato de audio no es compatible con tu dispositivo.';
        } else {
          playbackError = 'Error del reproductor: ${e.message}. '
              'Este formato puede no ser compatible.';
        }
        debugPrint('[SoundNeed] PlayerException: ${e.message}');
        return;
      } on PlatformException catch (e) {
        // Errores del lado nativo (Android MediaCodec)
        playbackError = 'Error del sistema: ${e.message}. '
            'Posible incompatibilidad de formato en tu dispositivo.';
        debugPrint('[SoundNeed] PlatformException: ${e.code} ${e.message}');
        return;
      } catch (e) {
        playbackError = 'Error al preparar el audio: $e. '
            'El stream seleccionado puede no ser compatible.';
        debugPrint('[SoundNeed] Error en setAudioSource: $e');
        return;
      }

      _currentSong = song;
      _isPlaying = true;
      notifyListeners();

      // ============================================================
      // RECOMMENDATION SERVICE - INICIAR ESCUCHA
      // ============================================================
      await RecommendationService.instance.startListening(
        id: song.isOnline ? song.onlineVideoId : song.id.toString(),
        title: song.title.isEmpty ? song.displayName : song.title,
        artist: song.artist,
        thumbnail: song.artworkUri.isNotEmpty ? song.artworkUri : null,
        source: song.isOnline ? 'youtube' : 'local',
        durationSeconds: (song.duration / 1000).round(),
      );

      // Iniciar timer para actualizar progreso
      _startProgressUpdateTimer();

      try {
        await _audioPlayer.play().timeout(
          const Duration(seconds: 45),
          onTimeout: () {
            throw TimeoutException('Timeout al iniciar reproducción (45s)');
          },
        );
      } on TimeoutException catch (e) {
        playbackError = 'Timeout al iniciar la reproducción. '
            'Verifica tu conexión e inténtalo de nuevo.';
        debugPrint('[SoundNeed] Timeout en play: $e');
        _isPlaying = false;
        notifyListeners();
        return;
      } catch (e) {
        playbackError = 'Error al reproducir: $e';
        debugPrint('[SoundNeed] Error en play: $e');
        _isPlaying = false;
        notifyListeners();
        return;
      }
    } catch (e) {
      playbackError = 'Error inesperado: $e';
      debugPrint('[SoundNeed] Error general en playSong: $e');
    } finally {
      if (_loadingOnline && token == _playToken) {
        _loadingOnline = false;
        notifyListeners();
      }
    }
  }

  /// Reproduce un resultado de YouTube. Si pasas [playlist], esos
  /// resultados forman la cola (siguiente / anterior funcionan).
  /// Devuelve false si falló (ver [playbackError]).
  Future<bool> playOnline(
    YouTubeSearchResult result, {
    List<YouTubeSearchResult>? playlist,
  }) async {
    final source = (playlist == null || playlist.isEmpty)
        ? <YouTubeSearchResult>[result]
        : playlist;

    final song = Song.fromYouTube(result);

    _queue = source.map(Song.fromYouTube).toList();

    var index = _queue.indexWhere((s) => s.id == song.id);

    if (index == -1) {
      _queue.insert(0, song);
      index = 0;
    }

    _queueIndex = index;

    await playSong(_queue[_queueIndex], createQueue: false);

    return playbackError == null;
  }

  // ============================================================
  // PLAY / PAUSE
  // ============================================================

  Future<void> togglePlayPause() async {
    if (_currentSong == null) {
      if (_songs.isNotEmpty) {
        await playSong(_songs.first);
      }

      return;
    }

    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
      _progressUpdateTimer?.cancel();
    } else {
      await _audioPlayer.play();
      _startProgressUpdateTimer();
    }
  }

  // ============================================================
  // SIGUIENTE
  // ============================================================

  Future<void> nextSong() async {
    await _stopCurrentListening();

    if (_songs.isEmpty && _queue.isEmpty) return;

    if (_queue.isEmpty) {
      _queue = List<Song>.from(_songs);
    }

    Song? nextSong;

    if (_shuffleEnabled) {
      nextSong = _getRandomSong();
    } else {
      if (_queueIndex < 0) {
        _queueIndex = 0;
      } else {
        _queueIndex++;
      }

      if (_queueIndex >= _queue.length) {
        if (_repeatEnabled) {
          _queueIndex = 0;
        } else {
          _queueIndex = _queue.length - 1;

          await _audioPlayer.pause();
          await _audioPlayer.seek(Duration.zero);

          return;
        }
      }

      nextSong = _queue[_queueIndex];
    }

    if (nextSong != null) {
      await playSong(nextSong, createQueue: false);
    }
  }

  // ============================================================
  // ANTERIOR
  // ============================================================

  Future<void> previousSong() async {
    await _stopCurrentListening();

    if (_songs.isEmpty && _queue.isEmpty) return;

    if (_queue.isEmpty) {
      _queue = List<Song>.from(_songs);
    }

    if (_audioPlayer.position.inSeconds > 3) {
      await _audioPlayer.seek(Duration.zero);
      return;
    }

    if (_shuffleEnabled) {
      final previousSong = _getRandomSong();

      if (previousSong != null) {
        await playSong(previousSong, createQueue: false);
      }

      return;
    }

    _queueIndex--;

    if (_queueIndex < 0) {
      if (_repeatEnabled) {
        _queueIndex = _queue.length - 1;
      } else {
        _queueIndex = 0;
      }
    }

    await playSong(
      _queue[_queueIndex],
      createQueue: false,
    );
  }

  // ============================================================
  // CANCIÓN TERMINADA
  // ============================================================

  Future<void> _handleSongCompleted() async {
    await _stopCurrentListening();

    if (_shuffleEnabled) {
      final nextSong = _getRandomSong();

      if (nextSong != null) {
        await playSong(
          nextSong,
          createQueue: false,
        );
      }

      return;
    }

    if (_queue.isEmpty) return;

    final nextIndex = _queueIndex + 1;

    if (nextIndex >= _queue.length) {
      if (_repeatEnabled) {
        _queueIndex = 0;

        await playSong(
          _queue[_queueIndex],
          createQueue: false,
        );
      } else {
        _isPlaying = false;
        notifyListeners();
      }

      return;
    }

    _queueIndex = nextIndex;

    await playSong(
      _queue[_queueIndex],
      createQueue: false,
    );
  }

  // ============================================================
  // ALEATORIO
  // ============================================================

  Song? _getRandomSong() {
    final pool = _queue.isNotEmpty ? _queue : _songs;

    if (pool.isEmpty) {
      return null;
    }

    final currentId = _currentSong?.id;

    final available = pool
        .where((song) => song.id != currentId)
        .toList();

    if (available.isEmpty) {
      return pool.first;
    }

    available.shuffle();

    return available.first;
  }

  void toggleShuffle() {
    _shuffleEnabled = !_shuffleEnabled;
    notifyListeners();
  }

  // ============================================================
  // REPETICIÓN
  // ============================================================

  void toggleRepeat() {
    _repeatEnabled = !_repeatEnabled;
    notifyListeners();
  }

  // ============================================================
  // SEEK
  // ============================================================

  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);

    // Si se hace seek al inicio, contarlo como replay
    if (position.inSeconds < 3 && _currentSong != null) {
      await RecommendationService.instance.registerReplay(
        songId: _currentSong!.id.toString(),
      );
    }
  }

  // ============================================================
  // PORTADAS
  // ============================================================

  Future<Uint8List?> loadOnlineArtwork(Song song) async {
    if (_onlineArtworkCache.containsKey(song.id)) {
      return _onlineArtworkCache[song.id];
    }

    if (song.artworkUri.isEmpty) {
      return null;
    }

    try {
      final response = await http
          .get(Uri.parse(song.artworkUri))
          .timeout(const Duration(seconds: 10));

      final Uint8List? bytes =
          response.statusCode == 200 ? response.bodyBytes : null;

      _onlineArtworkCache[song.id] = bytes;

      return bytes;
    } catch (e) {
      debugPrint('Error descargando portada online: $e');

      _onlineArtworkCache[song.id] = null;

      return null;
    }
  }

  Future<Uint8List?> loadArtwork(Song song) async {
    if (song.isOnline) {
      return loadOnlineArtwork(song);
    }

    final albumId = song.albumId;

    // Intentar obtener por albumId primero
    if (albumId != null && albumId > 0) {
      if (_artworkCache.containsKey(albumId)) {
        return _artworkCache[albumId];
      }

      try {
        final Uint8List? artwork =
            await _channel.invokeMethod<Uint8List>(
          'getArtwork',
          {'albumId': albumId},
        );

        _artworkCache[albumId] = artwork;

        if (artwork != null) {
          return artwork;
        }
      } catch (e) {
        debugPrint('Error obteniendo portada por albumId: $e');
      }
    }

    // Fallback: intentar obtener por URI de la canción
    final cacheKey = song.id;
    if (_artworkCache.containsKey(cacheKey)) {
      return _artworkCache[cacheKey];
    }

    try {
      final Uint8List? artwork =
          await _channel.invokeMethod<Uint8List>(
        'getArtwork',
        {'uri': song.uri},
      );

      _artworkCache[cacheKey] = artwork;

      return artwork;
    } catch (e) {
      debugPrint('Error obteniendo portada por URI: $e');

      _artworkCache[cacheKey] = null;

      return null;
    }
  }

  // ============================================================
  // UTILIDADES
  // ============================================================

  String formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);

    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void setQueueIndex(int index) {
    _queueIndex = index;
  }

  // ============================================================
  // RECOMMENDATION SERVICE - TIMER DE PROGRESO
  // ============================================================

  void _startProgressUpdateTimer() {
    _progressUpdateTimer?.cancel();

    _progressUpdateTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (_currentSong != null && _audioPlayer.playing) {
          final position = _audioPlayer.position.inSeconds;
          final duration = _audioPlayer.duration?.inSeconds;

          RecommendationService.instance.updateProgress(
            positionSeconds: position,
            durationSeconds: duration,
          );
        }
      },
    );
  }

  Future<void> _stopCurrentListening() async {
    if (_currentSong != null) {
      _progressUpdateTimer?.cancel();

      final position = _audioPlayer.position.inSeconds;
      final duration = _audioPlayer.duration?.inSeconds;

      await RecommendationService.instance.stopListening(
        positionSeconds: position,
        durationSeconds: duration,
      );
    }
  }

  @override
  void dispose() {
    _progressUpdateTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'services/youtube_audio_service.dart';
import 'services/audio_handler.dart';
import 'services/recommendation_service.dart';
import 'services/equalizer_service.dart';

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
  final String folderPath;
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
    this.folderPath = '',
    required this.isMusic,
  });

  factory Song.fromMap(Map<dynamic, dynamic> map) {
    final title = map['title']?.toString() ?? 'Sin título';
    final displayName = map['displayName']?.toString() ?? '';
    return Song(
      id: (map['id'] as num?)?.toInt() ?? 0,
      title: title,
      displayName: displayName,
      artist: _resolvedArtist(
        map['artist']?.toString() ?? '',
        title,
        displayName,
      ),
      album: map['album']?.toString() ?? 'Álbum desconocido',
      albumId: (map['albumId'] as num?)?.toInt(),
      duration: (map['duration'] as num?)?.toInt() ?? 0,
      mimeType: map['mimeType']?.toString() ?? '',
      size: (map['size'] as num?)?.toInt() ?? 0,
      uri: map['uri']?.toString() ?? '',
      artworkUri: map['artworkUri']?.toString() ?? '',
      folderPath: map['folderPath']?.toString() ?? '',
      isMusic: map['isMusic'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'displayName': displayName,
    'artist': artist,
    'album': album,
    'albumId': albumId,
    'duration': duration,
    'mimeType': mimeType,
    'size': size,
    'uri': uri,
    'artworkUri': artworkUri,
    'folderPath': folderPath,
    'isMusic': isMusic,
  };

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
  bool get isPodcast => mimeType == 'podcast';

  String get onlineVideoId => Uri.tryParse(uri)?.queryParameters['v'] ?? '';
}

String _resolvedArtist(String artist, String title, String displayName) {
  final normalized = artist.trim().toLowerCase();
  const missingValues = {
    '',
    '<unknown>',
    'unknown',
    'unknown artist',
    'artista desconocido',
    'youtube',
  };
  if (!missingValues.contains(normalized)) return artist.trim();

  var source = title.trim();
  if (source.isEmpty || source == 'Sin título') {
    source = displayName.trim().replaceFirst(RegExp(r'\.[^.]+$'), '');
  }
  for (final separator in [' - ', ' – ', ' — ', ' | ', ' • ']) {
    final index = source.indexOf(separator);
    if (index <= 0) continue;
    final candidate = source.substring(0, index).trim();
    final remaining = source.substring(index + separator.length).trim();
    if (candidate.isEmpty || remaining.isEmpty) continue;
    return candidate.replaceAll(RegExp(r'\s*_\s*'), ' & ').trim();
  }
  return 'Artista desconocido';
}

class MusicPlayerController extends ChangeNotifier {
  static const int modeNormal = 0;
  static const int modeShuffle = 1;
  static const int modeRepeatAll = 2;
  static const int modeRepeatOne = 3;
  static const MethodChannel _channel = MethodChannel('music_player/media');
  static const EventChannel _networkChannel = EventChannel('soundneed/network');
  static const EventChannel _downloadProgressChannel = EventChannel(
    'soundneed/download_progress',
  );

  final SoundNeedAudioHandler _audioHandler;
  late final AudioPlayer _audioPlayer;

  late SharedPreferences _preferences;

  List<Song> _songs = [];
  List<Song> _hiddenSongs = [];
  List<Song> _queue = [];

  Song? _currentSong;
  Song? _loadedSong;

  final Set<int> _favoriteIds = {};

  bool _loading = true;
  bool _permissionDenied = false;
  bool _isPlaying = false;

  int _playbackMode = modeNormal;
  bool _autoContinueEnabled = true;
  bool _rememberPlaybackEnabled = true;
  bool _newMusicNotificationsEnabled = false;
  bool _preferencesReady = false;
  bool _loadingAutoContinue = false;
  DateTime? _sleepTimerDeadline;
  Timer? _sleepTimer;
  Timer? _resumeSaveTimer;
  static const String _resumeSessionKey = 'soundneed_resume_session_v1';
  static const String _sleepTimerKey = 'soundneed_sleep_timer_deadline_ms';
  final List<String> _recentPlaybackKeys = [];

  int _queueIndex = -1;

  final Map<int, Uint8List?> _artworkCache = {};
  final Map<int, Uint8List?> _onlineArtworkCache = {};
  // Reutiliza el stream cacheado por just_audio al repetir una canción.
  // Esto evita volver a pedir a YouTube una URL temporal durante la sesión.
  final Map<String, LockCachingAudioSource> _onlineAudioSources = {};
  // Caché persistente de URLs de YouTube (videoId -> URL)
  final Map<String, String> _youtubeUrlCache = {};
  // Comparte la extracción entre precarga y reproducción para evitar que una
  // selección inicie dos llamadas NewPipe para el mismo video.
  final Map<String, Future<String?>> _youtubeUrlRequests = {};
  final Set<String> _refreshingOnlineAudioUrls = {};
  final Map<String, int> _onlineAudioUrlRefreshAttempts = {};

  bool _loadingOnline = false;
  bool _controllerDisposed = false;
  bool? _networkConnected;
  bool _retryOnReconnect = false;
  bool _reconnectedWhileLoading = false;
  int _playToken = 0;
  StreamSubscription<dynamic>? _networkSubscription;
  StreamSubscription<dynamic>? _downloadProgressSubscription;
  StreamSubscription<PlayerException>? _playerErrorSubscription;
  StreamSubscription<int?>? _audioSessionSubscription;
  bool _isDownloading = false;
  double? _downloadProgress;
  bool _isDownloadingPlaylist = false;
  int _playlistDownloadFinished = 0;
  int _playlistDownloadTotal = 0;
  int _artworkRevision = 0;

  /// Mensaje del último error de reproducción (null si todo fue bien).
  String? playbackError;

  /// Timer para actualizar progreso en RecommendationService.
  Timer? _progressUpdateTimer;
  Future<void> _recommendationQueue = Future<void>.value();
  Future<void>? _pendingChartQueue;

  // Getters
  List<Song> get songs => _songs;
  List<Song> get hiddenSongs => _hiddenSongs;
  List<Song> get queue => _queue;
  Song? get currentSong => _currentSong;
  bool get loading => _loading;
  bool get permissionDenied => _permissionDenied;
  bool get isPlaying => _isPlaying;
  bool get shuffleEnabled => _playbackMode == modeShuffle;
  bool get repeatEnabled => _playbackMode == modeRepeatAll;
  int get playbackMode => _playbackMode;
  bool get autoContinueEnabled => _autoContinueEnabled;
  bool get rememberPlaybackEnabled => _rememberPlaybackEnabled;
  bool get newMusicNotificationsEnabled => _newMusicNotificationsEnabled;
  DateTime? get sleepTimerDeadline => _sleepTimerDeadline;
  Duration? get sleepTimerRemaining {
    final deadline = _sleepTimerDeadline;
    if (deadline == null) return null;
    final remaining = deadline.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get loadingOnline => _loadingOnline;
  bool get isDownloading => _isDownloading;
  double? get downloadProgress => _downloadProgress;
  bool get isDownloadingPlaylist => _isDownloadingPlaylist;
  int get playlistDownloadFinished => _playlistDownloadFinished;
  int get playlistDownloadTotal => _playlistDownloadTotal;
  int get artworkRevision => _artworkRevision;
  double? get playlistDownloadProgress => _playlistDownloadTotal == 0
      ? null
      : ((_playlistDownloadFinished +
                    (_isDownloading ? (_downloadProgress ?? 0) : 0)) /
                _playlistDownloadTotal)
            .clamp(0.0, 1.0)
            .toDouble();
  int get queueIndex => _queueIndex;
  AudioPlayer get audioPlayer => _audioPlayer;
  Stream<Duration> get positionStream => _audioPlayer.positionStream;

  MusicPlayerController({required SoundNeedAudioHandler audioHandler})
    : _audioHandler = audioHandler {
    _audioPlayer = audioHandler.player;
    _audioSessionSubscription = _audioPlayer.androidAudioSessionIdStream.listen(
      (sessionId) =>
          unawaited(EqualizerService.instance.bindSession(sessionId)),
      onError: (Object error) {
        debugPrint('[SoundNeed] No se pudo enlazar el ecualizador: $error');
      },
    );
    final initialAudioSessionId = _audioPlayer.androidAudioSessionId;
    if (initialAudioSessionId != null) {
      unawaited(EqualizerService.instance.bindSession(initialAudioSessionId));
    }
    _audioHandler.onPlayRequested = _handleExternalPlay;
    _audioHandler.onSkipToNext = nextSong;
    _audioHandler.onSkipToPrevious = previousSong;
    _audioHandler.onStopRequested = _handleExternalStop;
    _networkSubscription = _networkChannel.receiveBroadcastStream().listen(
      _handleNetworkState,
      onError: (Object error) {
        debugPrint('[SoundNeed] No se pudo observar la conexión: $error');
      },
    );
    _downloadProgressSubscription = _downloadProgressChannel
        .receiveBroadcastStream()
        .listen(
          (dynamic event) {
            if (event is Map) {
              final rawProgress = event['progress'];
              _downloadProgress = rawProgress is num
                  ? rawProgress.toDouble().clamp(0.0, 1.0).toDouble()
                  : null;
              notifyListeners();
            }
          },
          onError: (Object error) {
            debugPrint('[SoundNeed] No se pudo observar la descarga: $error');
          },
        );
    _audioPlayer.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      if (state.playing && _currentSong?.isOnline == true) {
        _onlineAudioUrlRefreshAttempts.remove(_currentSong!.onlineVideoId);
      }
      notifyListeners();
    });

    _audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _handleSongCompleted();
      }
    });
    _playerErrorSubscription = _audioPlayer.errorStream.listen((error) {
      final song = _currentSong;
      if (song == null || !song.isOnline || _loadedSong?.id != song.id) {
        return;
      }
      if (_isRefreshableOnlineAudioError(error)) {
        _refreshExpiredOnlineAudioUrl(song, error);
        return;
      }
      playbackError = 'Error al cargar el audio: ${error.message}';
      _waitForNetworkReconnect(song);
      _isPlaying = false;
      notifyListeners();
    });
  }

  void _handleNetworkState(dynamic value) {
    final connected = value == true;
    final wasConnected = _networkConnected;
    _networkConnected = connected;
    if (connected && wasConnected == false) {
      _onlineArtworkCache.removeWhere((_, bytes) => bytes == null);
      _audioHandler.refreshWidgetArtwork();
      final song = _currentSong;
      if (song != null && song.isOnline) {
        _onlineArtworkCache.remove(song.id);
        unawaited(_publishProcessedArtwork(song, _playToken));
      }
      _artworkRevision++;
      notifyListeners();
      if (_loadingOnline) {
        _reconnectedWhileLoading = true;
      } else {
        _retryCurrentOnlineSong();
      }
    }
  }

  void _saveYoutubeUrlCache() {
    try {
      _preferences.setString('youtube_url_cache', jsonEncode(_youtubeUrlCache));
    } catch (e) {
      debugPrint('[SoundNeed] Error guardando caché de URLs: $e');
    }
  }

  /// Precarga la URL de audio de YouTube en segundo plano.
  /// Llamar esto cuando el usuario selecciona o muestra una canción online.
  Future<void> preloadYoutubeUrl(String videoId) async {
    try {
      final cached = _youtubeUrlCache.containsKey(videoId);
      final audioUrl = await _getOrResolveYoutubeAudioUrl(videoId);
      if (!cached && audioUrl != null) {
        debugPrint('[SoundNeed] URL precargada para $videoId');
      }
    } catch (e) {
      debugPrint('[SoundNeed] Error precargando URL: $e');
    }
  }

  Future<String?> _getOrResolveYoutubeAudioUrl(String videoId) {
    final cached = _youtubeUrlCache[videoId];
    if (cached != null && cached.isNotEmpty) return Future.value(cached);

    final pending = _youtubeUrlRequests[videoId];
    if (pending != null) return pending;

    late final Future<String?> request;
    request = () async {
      try {
        final audioUrl = await YouTubeAudioService.instance.getAudioUrl(
          videoId,
        );
        if (audioUrl != null && audioUrl.isNotEmpty) {
          _youtubeUrlCache[videoId] = audioUrl;
          _saveYoutubeUrlCache();
        }
        return audioUrl;
      } finally {
        if (identical(_youtubeUrlRequests[videoId], request)) {
          _youtubeUrlRequests.remove(videoId);
        }
      }
    }();
    _youtubeUrlRequests[videoId] = request;
    return request;
  }

  void _retryCurrentOnlineSong() {
    final song = _currentSong;
    if (_controllerDisposed ||
        !_retryOnReconnect ||
        _loadingOnline ||
        song == null ||
        !song.isOnline) {
      return;
    }

    _retryOnReconnect = false;
    _reconnectedWhileLoading = false;
    unawaited(playSong(song, createQueue: false, retry: true));
  }

  Future<void> _handleExternalPlay() async {
    var song = _currentSong;
    if (song == null) {
      final item = _audioHandler.currentMediaItem;
      final videoId = item?.id;
      if (item == null ||
          videoId == null ||
          !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) {
        return;
      }

      // El servicio puede conservar los metadatos del widget aunque la
      // pantalla de la app haya recreado el controlador. Reconstruimos la
      // selección de YouTube y dejamos que playSong vuelva a extraer el audio.
      song = Song(
        id: videoId.hashCode & 0x7fffffff,
        title: item.title,
        displayName: item.title,
        artist: item.artist ?? 'YouTube',
        album: item.album ?? 'YouTube',
        albumId: null,
        duration: item.duration?.inMilliseconds ?? 0,
        mimeType: 'youtube',
        size: 0,
        uri: 'https://www.youtube.com/watch?v=$videoId',
        artworkUri: item.artUri?.toString() ?? '',
        isMusic: true,
      );
      _currentSong = song;
    }
    if (_loadingOnline) return;

    final loaded = _loadedSong?.id == song.id && _loadedSong?.uri == song.uri;
    if (!loaded ||
        _retryOnReconnect ||
        _audioPlayer.processingState == ProcessingState.idle) {
      await playSong(song, createQueue: false, retry: true);
      return;
    }

    try {
      if (_audioPlayer.processingState == ProcessingState.completed) {
        await _audioPlayer.seek(Duration.zero);
      }
      _queueStartListening(song);
      _recordRecentPlayback(song);
      unawaited(_savePlaybackSession());
      _startProgressUpdateTimer();
      await _audioPlayer.play();
    } catch (error) {
      playbackError = 'Error al reanudar la canción: $error';
      _waitForNetworkReconnect(song);
      _isPlaying = false;
      _progressUpdateTimer?.cancel();
      notifyListeners();
      debugPrint(
        '[SoundNeed] Error al reanudar desde controles externos: $error',
      );
    }
  }

  Future<void> _handleExternalStop() async {
    ++_playToken;
    _queueStopListening(_currentSong);
    _progressUpdateTimer?.cancel();
    _currentSong = null;
    _loadedSong = null;
    _queue = [];
    _queueIndex = -1;
    _loadingOnline = false;
    _retryOnReconnect = false;
    _reconnectedWhileLoading = false;
    _isPlaying = false;
    playbackError = null;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerDeadline = null;
    if (_preferencesReady) {
      unawaited(_preferences.remove(_sleepTimerKey));
      unawaited(_preferences.remove(_resumeSessionKey));
    }
    notifyListeners();
  }

  // ============================================================
  // INICIALIZACION
  // ============================================================
  Future<void> initialize() async {
    await _requestNotificationPermission();

    _preferences = await SharedPreferences.getInstance();
    _preferencesReady = true;
    _autoContinueEnabled =
        _preferences.getBool('auto_continue_playback') ?? true;
    _rememberPlaybackEnabled =
        _preferences.getBool('remember_playback_position') ?? true;
    _newMusicNotificationsEnabled =
        _preferences.getBool('new_music_notifications') ?? false;
    _restoreSleepTimer();
    _resumeSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_rememberPlaybackEnabled && _currentSong != null) {
        unawaited(_savePlaybackSession());
      }
    });

    final savedFavorites = _preferences.getStringList('favorite_song_ids');

    if (savedFavorites != null) {
      _favoriteIds.addAll(
        savedFavorites.map((id) => int.tryParse(id)).whereType<int>(),
      );
    }

    // Cargar caché de URLs de YouTube
    final savedUrls = _preferences.getString('youtube_url_cache');
    if (savedUrls != null) {
      try {
        final decoded = jsonDecode(savedUrls) as Map<String, dynamic>;
        _youtubeUrlCache.addAll(
          decoded.map((k, v) => MapEntry(k, v.toString())),
        );
        debugPrint(
          '[SoundNeed] Cargado caché de URLs: ${_youtubeUrlCache.length} entradas',
        );
      } catch (e) {
        debugPrint('[SoundNeed] Error cargando caché de URLs: $e');
      }
    }

    // Inicializar servicio de recomendaciones
    await RecommendationService.instance.initialize();

    await loadSongs();
    if (_rememberPlaybackEnabled) await _restorePlaybackSession();
  }

  Future<void> setAutoContinueEnabled(bool enabled) async {
    _autoContinueEnabled = enabled;
    if (_preferencesReady) {
      await _preferences.setBool('auto_continue_playback', enabled);
    }
    notifyListeners();
  }

  Future<void> setRememberPlaybackEnabled(bool enabled) async {
    _rememberPlaybackEnabled = enabled;
    if (_preferencesReady) {
      await _preferences.setBool('remember_playback_position', enabled);
      if (enabled) {
        await _savePlaybackSession();
      } else {
        await _preferences.remove(_resumeSessionKey);
      }
    }
    notifyListeners();
  }

  Future<void> setNewMusicNotificationsEnabled(bool enabled) async {
    _newMusicNotificationsEnabled = enabled;
    if (_preferencesReady) {
      await _preferences.setBool('new_music_notifications', enabled);
    }
    if (enabled) await requestNotificationPermission();
    notifyListeners();
  }

  Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod<void>('requestNotificationPermission');
    } catch (error) {
      debugPrint(
        '[SoundNeed] No se pudo solicitar permiso de notificaciones: $error',
      );
    }
  }

  Future<bool> notifyNewMusicDetected(int count) async {
    if (!_newMusicNotificationsEnabled || count <= 0) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'showNewMusicNotification',
            <String, Object>{'count': count},
          ) ??
          false;
    } catch (error) {
      debugPrint(
        '[SoundNeed] No se pudo mostrar el aviso de música nueva: $error',
      );
      return false;
    }
  }

  Future<void> setSleepTimer(Duration? duration) async {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerDeadline = null;

    if (duration != null && duration > Duration.zero) {
      final deadline = DateTime.now().add(duration);
      _sleepTimerDeadline = deadline;
      if (_preferencesReady) {
        await _preferences.setInt(
          _sleepTimerKey,
          deadline.millisecondsSinceEpoch,
        );
      }
      _scheduleSleepTimer(duration);
    } else if (_preferencesReady) {
      await _preferences.remove(_sleepTimerKey);
    }
    notifyListeners();
  }

  void _restoreSleepTimer() {
    final deadlineMs = _preferences.getInt(_sleepTimerKey);
    if (deadlineMs == null) return;

    final deadline = DateTime.fromMillisecondsSinceEpoch(deadlineMs);
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      unawaited(_preferences.remove(_sleepTimerKey));
      return;
    }
    _sleepTimerDeadline = deadline;
    _scheduleSleepTimer(remaining);
  }

  void _scheduleSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _sleepTimer = Timer(duration, () => unawaited(_expireSleepTimer()));
  }

  Future<void> _expireSleepTimer() async {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerDeadline = null;
    if (_preferencesReady) await _preferences.remove(_sleepTimerKey);

    if (_loadingOnline) {
      ++_playToken;
      _loadingOnline = false;
      _isPlaying = false;
    }
    try {
      await _audioPlayer.pause();
    } catch (_) {
      // El temporizador también puede vencer antes de cargar la primera pista.
    }
    _progressUpdateTimer?.cancel();
    await _savePlaybackSession();
    notifyListeners();
  }

  Future<void> _savePlaybackSession() async {
    if (!_preferencesReady || !_rememberPlaybackEnabled) return;
    final current = _currentSong;
    if (current == null) {
      await _preferences.remove(_resumeSessionKey);
      return;
    }

    const maxSavedQueueItems = 160;
    final safeIndex = _queueIndex.clamp(
      0,
      _queue.isEmpty ? 0 : _queue.length - 1,
    );
    var start = 0;
    if (_queue.length > maxSavedQueueItems) {
      start = (safeIndex - maxSavedQueueItems ~/ 2).clamp(
        0,
        _queue.length - maxSavedQueueItems,
      );
    }
    final savedQueue = _queue
        .skip(start)
        .take(maxSavedQueueItems)
        .map((song) => song.toMap())
        .toList();

    await _preferences.setString(
      _resumeSessionKey,
      jsonEncode({
        'song': current.toMap(),
        'queue': savedQueue,
        'queueIndex': safeIndex - start,
        'playbackMode': _playbackMode,
        'positionMs': _audioPlayer.position.inMilliseconds,
      }),
    );
  }

  Future<void> _restorePlaybackSession() async {
    final raw = _preferences.getString(_resumeSessionKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      Song? resolveSong(dynamic value) {
        if (value is! Map) return null;
        final saved = Song.fromMap(value);
        if (saved.isOnline || saved.isPodcast) return saved;
        for (final local in _songs) {
          if (local.id == saved.id || local.uri == saved.uri) return local;
        }
        return null;
      }

      final current = resolveSong(data['song']);
      if (current == null) {
        await _preferences.remove(_resumeSessionKey);
        return;
      }

      final restoredQueue = <Song>[];
      final savedQueue = data['queue'];
      if (savedQueue is List) {
        for (final item in savedQueue) {
          final song = resolveSong(item);
          if (song != null &&
              !restoredQueue.any((queued) => _sameSong(queued, song))) {
            restoredQueue.add(song);
          }
        }
      }
      if (!restoredQueue.any((queued) => _sameSong(queued, current))) {
        restoredQueue.add(current);
      }
      _queue = restoredQueue;
      _queueIndex = restoredQueue.indexWhere(
        (song) => _sameSong(song, current),
      );
      _playbackMode =
          (data['playbackMode'] as num?)?.toInt().clamp(0, 3).toInt() ??
          modeNormal;
      _recordRecentPlayback(current);

      final positionMs = (data['positionMs'] as num?)?.toInt() ?? 0;
      await playSong(
        current,
        createQueue: false,
        retry: true,
        startPaused: true,
        initialPosition: Duration(milliseconds: positionMs),
      );
    } catch (error) {
      debugPrint(
        '[SoundNeed] No se pudo restaurar la última reproducción: $error',
      );
      await _preferences.remove(_resumeSessionKey);
    }
  }

  bool _sameSong(Song first, Song second) =>
      first.id == second.id && first.uri == second.uri;

  String _songPlaybackKey(Song song) => '${song.id}|${song.uri}';

  void _recordRecentPlayback(Song song) {
    final key = _songPlaybackKey(song);
    _recentPlaybackKeys.remove(key);
    _recentPlaybackKeys.add(key);
    if (_recentPlaybackKeys.length > 40) {
      _recentPlaybackKeys.removeRange(0, _recentPlaybackKeys.length - 40);
    }
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
      await _channel.invokeMethod('requestNotificationPermission');
    } catch (e) {
      debugPrint('Error solicitando permiso de notificaciones: $e');
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

      final List<dynamic>? result = await _channel.invokeMethod<List<dynamic>>(
        'getSongs',
      );

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
      final localSongsData = _songs
          .map(
            (song) => {
              'id': song.id,
              'title': song.title,
              'artist': song.artist,
              'artworkUri': song.artworkUri,
              'duration': song.duration,
            },
          )
          .toList();

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

  Future<List<Map<String, String>>> getMusicFolders() async {
    try {
      final folders = await _channel.invokeListMethod<dynamic>(
        'getMusicFolders',
      );
      return (folders ?? const <dynamic>[])
          .whereType<Map>()
          .map(
            (folder) => <String, String>{
              'path': folder['path']?.toString() ?? '',
              'name': folder['name']?.toString() ?? '',
            },
          )
          .where((folder) => folder['path']!.isNotEmpty)
          .toList();
    } catch (error) {
      debugPrint('[SoundNeed] No se pudieron cargar las carpetas: $error');
      return const [];
    }
  }

  Future<Map<String, String>?> addMusicFolder() async {
    try {
      final folder = await _channel.invokeMapMethod<String, dynamic>(
        'pickMusicFolder',
      );
      if (folder == null) return null;
      await loadSongs();
      return {
        'path': folder['path']?.toString() ?? '',
        'name': folder['name']?.toString() ?? '',
      };
    } catch (error) {
      debugPrint('[SoundNeed] No se pudo agregar la carpeta: $error');
      rethrow;
    }
  }

  Future<void> removeMusicFolder(String path) async {
    await _channel.invokeMethod<bool>('removeMusicFolder', <String, Object?>{
      'path': path,
    });
    await loadSongs();
  }

  /// Elimina una canción local mediante el diálogo de confirmación del sistema.
  Future<bool> deleteSong(Song song) async {
    if (song.isOnline || song.isPodcast || !song.uri.startsWith('content://')) {
      return false;
    }

    final deleted =
        await _channel.invokeMethod<bool>('deleteSong', <String, Object?>{
          'uri': song.uri,
        }) ??
        false;
    if (!deleted) return false;

    final wasCurrent =
        _currentSong?.id == song.id && _currentSong?.uri == song.uri;
    if (wasCurrent) {
      await _audioHandler.stop();
    } else {
      final oldIndex = _queueIndex;
      final removedIndex = _queue.indexWhere(
        (queued) => queued.id == song.id && queued.uri == song.uri,
      );
      _queue.removeWhere(
        (queued) => queued.id == song.id && queued.uri == song.uri,
      );
      if (removedIndex >= 0 && removedIndex < oldIndex) {
        _queueIndex = oldIndex - 1;
      }
    }
    if (song.albumId != null) _artworkCache.remove(song.albumId);
    _artworkCache.remove(song.id);
    if (_favoriteIds.remove(song.id)) await _saveFavorites();
    await loadSongs();
    return true;
  }

  Future<void> downloadSong(Song song) async {
    if (_isDownloading) return;
    _isDownloading = true;
    _downloadProgress = null;
    notifyListeners();
    try {
      debugPrint('[SoundNeed] Iniciando descarga: ${song.title}');
      final sourceMetadata = song.isOnline
          ? await YouTubeAudioService.instance.getVideoMetadata(
              song.onlineVideoId,
            )
          : const <String, String>{};
      final sourceTitle = sourceMetadata['title']?.trim();
      final downloadTitle = sourceTitle?.isNotEmpty == true
          ? sourceTitle!
          : song.title;
      final sourceArtist = sourceMetadata['artist']?.trim() ?? '';
      final artworkFuture = loadArtwork(song)
          .then<Uint8List?>((value) => value, onError: (_) => null);

      // Reintentos automáticos para errores 403/410
      const maxRetries = 2;
      int attempt = 0;
      Map<String, dynamic>? saved;

      while (attempt <= maxRetries) {
        attempt++;
        debugPrint('[SoundNeed] Intento $attempt de ${maxRetries + 1}');

        String? audioUrl;
        if (song.isOnline) {
          // Limpiar caché de URL si estamos reintentando después de un error
          if (attempt > 1) {
            final videoId = song.onlineVideoId;
            _youtubeUrlCache.remove(videoId);
            _saveYoutubeUrlCache();
            debugPrint('[SoundNeed] URL cacheada eliminada para reintentar');
          }

          debugPrint('[SoundNeed] Obteniendo URL de YouTube para descarga...');
          audioUrl = await YouTubeAudioService.instance.getAudioUrl(
            song.onlineVideoId,
          );
          debugPrint(
            '[SoundNeed] URL obtenida: ${audioUrl?.substring(0, 50)}...',
          );
        } else if (song.isPodcast ||
            song.uri.startsWith('http://') ||
            song.uri.startsWith('https://')) {
          audioUrl = song.uri;
        } else {
          throw StateError('Esta canción ya está guardada en el dispositivo.');
        }

        if (audioUrl == null || audioUrl.isEmpty) {
          throw StateError(
            YouTubeAudioService.instance.lastError ??
                'No se pudo extraer el audio para descargarlo.',
          );
        }

        final artwork = await artworkFuture;

        final artist = _validSourceArtist(sourceArtist)
            ? sourceArtist
            : _artistForDownload(song);
        final songTitle = _songTitleForDownload(downloadTitle, artist);
        debugPrint(
          '[SoundNeed] Descargando archivo (intento $attempt): $artist - $songTitle',
        );

        try {
          saved = await _channel.invokeMapMethod<String, dynamic>(
            'downloadAudio',
            <String, Object?>{
              'url': audioUrl,
              'title': songTitle.isEmpty ? song.displayName : songTitle,
              'artist': artist,
              'album': _albumForDownload(song, sourceMetadata),
              'duration': song.duration,
              'artwork': artwork,
              'sourceUrl': song.isOnline
                  ? 'https://www.youtube.com/watch?v=${song.onlineVideoId}'
                  : song.uri,
            },
          );

          if (saved != null) {
            // Éxito
            debugPrint('[SoundNeed] Descarga completada: ${saved['name']}');
            break;
          } else {
            throw StateError('Android no confirmó la descarga.');
          }
        } catch (e) {
          final errorStr = e.toString().toLowerCase();
          // Errores recuperables: 403, 410, connection reset, socket exception, timeout, eof
          final isRecoverable =
              errorStr.contains('403') ||
              errorStr.contains('410') ||
              errorStr.contains('connection reset') ||
              errorStr.contains('socketexception') ||
              errorStr.contains('timeout') ||
              errorStr.contains('eof') ||
              errorStr.contains('download_failed');

          if (attempt <= maxRetries && isRecoverable) {
            debugPrint(
              '[SoundNeed] Error recuperable ($e) - Reintentando con nueva URL...',
            );
            await Future.delayed(const Duration(milliseconds: 500));
            continue;
          } else {
            // No es error recuperable o no hay más reintentos
            rethrow;
          }
        }
      }

      if (saved == null) {
        throw StateError(
          'No se pudo descargar después de ${maxRetries + 1} intentos.',
        );
      }

      await loadSongs();
    } finally {
      _isDownloading = false;
      _downloadProgress = null;
      notifyListeners();
    }
  }

  Future<int> downloadPlaylist(List<Song> songs) async {
    if (_isDownloadingPlaylist || _isDownloading) return 0;
    final downloadable = songs
        .where(
          (song) =>
              song.isOnline ||
              song.isPodcast ||
              song.uri.startsWith('http://') ||
              song.uri.startsWith('https://'),
        )
        .toList();
    if (downloadable.isEmpty) return 0;

    _isDownloadingPlaylist = true;
    _playlistDownloadFinished = 0;
    _playlistDownloadTotal = downloadable.length;
    notifyListeners();
    var failures = 0;
    try {
      for (final song in downloadable) {
        try {
          await downloadSong(song);
        } catch (error) {
          failures++;
          debugPrint('[SoundNeed] Falló una descarga de playlist: $error');
        } finally {
          _playlistDownloadFinished++;
          notifyListeners();
        }
      }
      return failures;
    } finally {
      _isDownloadingPlaylist = false;
      _downloadProgress = null;
      notifyListeners();
    }
  }

  String _artistForDownload(Song song) {
    final artist = song.artist.trim();
    if (_validSourceArtist(artist)) return artist;

    // Si el artista es un placeholder, intentar extraer del título
    final title = song.title.trim();
    for (final separator in [
      ' - ',
      ' – ',
      ' — ',
      ' | ',
      ' • ',
      ' ft. ',
      ' feat. ',
    ]) {
      final index = title.indexOf(separator);
      if (index > 0) {
        final extractedArtist = title.substring(0, index).trim();
        // Verificar que el artista extraído no esté ya en el título para evitar duplicación
        if (extractedArtist.isNotEmpty &&
            !title.startsWith('$extractedArtist - $extractedArtist')) {
          return extractedArtist;
        }
      }
    }

    // Para YouTube, si no hay separador válido, usar el artista de la búsqueda si existe
    if (song.isOnline && _validSourceArtist(song.artist)) {
      return song.artist;
    }

    return 'Artista desconocido';
  }

  String _albumForDownload(Song song, Map<String, String> sourceMetadata) {
    final sourceAlbum = sourceMetadata['album']?.trim() ?? '';
    if (sourceAlbum.isNotEmpty) return sourceAlbum;

    final album = song.album.trim();
    if (album.isEmpty || album.toLowerCase() == 'youtube') return '';
    return album;
  }

  bool _validSourceArtist(String artist) {
    final normalized = artist.trim().toLowerCase();
    return normalized.isNotEmpty &&
        normalized != '<unknown>' &&
        normalized != 'unknown' &&
        normalized != 'unknown artist' &&
        normalized != 'artista desconocido' &&
        normalized != 'youtube';
  }

  String _songTitleForDownload(String title, String artist) {
    var songTitle = title.trim();
    final separators = [' - ', ' – ', ' — ', ' | '];
    String? separator;
    var separatorIndex = -1;
    for (final candidate in separators) {
      final index = songTitle.indexOf(candidate);
      if (index >= 0 && (separatorIndex < 0 || index < separatorIndex)) {
        separator = candidate;
        separatorIndex = index;
      }
    }
    if (separator != null) {
      final prefix = songTitle.substring(0, separatorIndex).trim();
      String normalize(String value) => value
          .toLowerCase()
          .replaceAll(RegExp(r'\s*[-_&]\s*'), '')
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      final normalizedPrefix = normalize(prefix);
      final normalizedArtist = normalize(artist);
      if (normalizedPrefix.isNotEmpty &&
          normalizedArtist.isNotEmpty &&
          (normalizedArtist.contains(normalizedPrefix) ||
              normalizedPrefix.contains(normalizedArtist))) {
        songTitle = songTitle
            .substring(separatorIndex + separator.length)
            .trim();
      }
    }

    songTitle = songTitle.replaceFirst(
      RegExp(
        r'\s*[_|–—-]*\s*(?:video\s+oficial|official\s+video|video\s+lyric|lyric\s+video|video\s+letra|audio\s+oficial|official\s+audio).*$',
        caseSensitive: false,
      ),
      '',
    );
    return songTitle
        .replaceAll(RegExp(r'\s*_+\s*'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\s|–—-]+|[\s|–—-]+$'), '')
        .trim();
  }

  // ============================================================
  // FAVORITOS
  // ============================================================

  bool isFavorite(Song song) {
    return _favoriteIds.contains(song.id);
  }

  Future<void> toggleFavorite(Song song) async {
    final wasFavorite = _favoriteIds.contains(song.id);
    if (wasFavorite) {
      _favoriteIds.remove(song.id);
    } else {
      _favoriteIds.add(song.id);
    }

    await _saveFavorites();
    notifyListeners();

    try {
      await RecommendationService.instance.setFavorite(
        songId: song.isOnline ? song.onlineVideoId : song.id.toString(),
        favorite: !wasFavorite,
      );
    } catch (error) {
      debugPrint('[MusicPlayer] No se pudo sincronizar favorito: $error');
    }
  }

  Future<void> setFavorite(Song song, bool favorite) async {
    if (favorite) {
      _favoriteIds.add(song.id);
    } else {
      _favoriteIds.remove(song.id);
    }

    await _saveFavorites();
    notifyListeners();

    try {
      await RecommendationService.instance.setFavorite(
        songId: song.isOnline ? song.onlineVideoId : song.id.toString(),
        favorite: favorite,
      );
    } catch (error) {
      debugPrint('[MusicPlayer] No se pudo sincronizar favorito: $error');
    }
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
    bool retry = false,
    bool startPaused = false,
    Duration? initialPosition,
  }) async {
    // Tocar otra vez la canción seleccionada no debe cancelar una extracción
    // activa ni reiniciar el stream. La interfaz abre el reproductor completo.
    if (!retry &&
        _currentSong?.id == song.id &&
        _currentSong?.uri == song.uri) {
      return;
    }
    _pendingChartQueue = null;

    if (!retry) {
      _retryOnReconnect = false;
      _reconnectedWhileLoading = false;
    }
    playbackError = null;
    final token = ++_playToken;

    _queueStopListening(_currentSong);
    _progressUpdateTimer?.cancel();

    // Pausar la pista actual de inmediato, incluso cuando la nueva requiere
    // resolver primero una URL de YouTube.
    try {
      await _audioPlayer.pause();
    } catch (_) {
      // Puede no haber una fuente cargada en el primer inicio.
    }
    if (token != _playToken) return;

    _currentSong = song;
    _recordRecentPlayback(song);
    _loadingOnline = song.isOnline;
    _isPlaying = false;
    _audioHandler.setPendingMediaItem(_mediaItemFor(song));
    if (song.isOnline) {
      unawaited(_publishProcessedArtwork(song, token));
    }
    notifyListeners();

    try {
      if (createQueue && !song.isOnline) {
        _createQueueFromSong(song);
      }
      unawaited(_savePlaybackSession());

      final Uri sourceUri;
      AudioSource? preparedSource;
      LockCachingAudioSource? onlineSource;

      if (song.isOnline) {
        final videoId = song.onlineVideoId;
        onlineSource = _onlineAudioSources[videoId];
        preparedSource = onlineSource;

        if (onlineSource == null) {
          // Intentar usar URL cacheada primero
          String? audioUrl = _youtubeUrlCache[videoId];

          if (audioUrl == null) {
            debugPrint('[SoundNeed] Resolviendo audio de YouTube: $videoId');
            final resolveTimer = Stopwatch()..start();
            audioUrl = await _getOrResolveYoutubeAudioUrl(videoId);

            // Si el usuario eligió otra canción mientras obtenía la URL, descartamos esta.
            if (token != _playToken) {
              return;
            }

            if (audioUrl == null || audioUrl.isEmpty) {
              playbackError =
                  YouTubeAudioService.instance.lastError ??
                  'No se pudo obtener el audio de YouTube';
              _waitForNetworkReconnect(song);
              debugPrint('[SoundNeed] $playbackError');
              return;
            }

            debugPrint('[SoundNeed] URL cacheada para $videoId');
            debugPrint(
              '[SoundNeed] URL resuelta en ${resolveTimer.elapsedMilliseconds}ms: $videoId',
            );
          } else {
            debugPrint('[SoundNeed] Usando URL cacheada para $videoId');
          }

          onlineSource = LockCachingAudioSource(
            Uri.parse(audioUrl),
            tag: _mediaItemFor(song),
          );
          preparedSource = onlineSource;
          _onlineAudioSources[videoId] = onlineSource;
        }

        sourceUri = onlineSource.uri;
      } else {
        sourceUri = Uri.parse(song.uri);
      }

      // Validar que la URI es válida antes de usarla
      if (!sourceUri.hasScheme || !sourceUri.hasAuthority) {
        playbackError = 'URL de audio inválida: ${sourceUri.toString()}';
        _waitForNetworkReconnect(song);
        debugPrint('[SoundNeed] $playbackError');
        return;
      }

      final mediaItem = _mediaItemFor(song);
      // ============================================================
      // MANEJO ROBUSTO DE ERRORES EN REPRODUCCIÓN
      // ============================================================
      try {
        final sourceTimer = Stopwatch()..start();
        await _audioPlayer
            .setAudioSource(
              preparedSource ??
                  AudioSource.uri(
                    sourceUri,
                    headers: song.isPodcast
                        ? const {
                            'User-Agent':
                                'Mozilla/5.0 (compatible; SoundNeed/1.0)',
                            'Accept': 'audio/*,application/octet-stream,*/*',
                          }
                        : null,
                    tag: mediaItem,
                  ),
            )
            .timeout(
              const Duration(seconds: 20),
              onTimeout: () {
                throw TimeoutException('Timeout al preparar el audio (20s)');
              },
            );
        debugPrint(
          '[SoundNeed] Audio preparado en ${sourceTimer.elapsedMilliseconds}ms: ${song.title}',
        );
      } on TimeoutException catch (e) {
        if (token != _playToken) return;
        try {
          await _audioPlayer.stop();
        } catch (_) {}
        if (song.isOnline && _isRefreshableOnlineAudioError(e)) {
          _refreshExpiredOnlineAudioUrl(song, e);
          return;
        }
        playbackError =
            'Timeout: No se pudo cargar el audio a tiempo. '
            'Inténtalo de nuevo o verifica tu conexión.';
        _waitForNetworkReconnect(song);
        debugPrint('[SoundNeed] Timeout en setAudioSource: $e');
        return;
      } on PlayerException catch (e) {
        if (token != _playToken) return;
        if (song.isOnline && _isRefreshableOnlineAudioError(e)) {
          _refreshExpiredOnlineAudioUrl(song, e);
          return;
        }
        // Errores específicos de just_audio/MediaCodec
        final errorMsg = e.message?.toLowerCase() ?? '';
        if (errorMsg.contains('codec') ||
            errorMsg.contains('format') ||
            errorMsg.contains('decode')) {
          playbackError =
              'Error de códec/decodificación: ${e.message}. '
              'El formato de audio no es compatible con tu dispositivo.';
        } else {
          playbackError =
              'Error del reproductor: ${e.message}. '
              'Este formato puede no ser compatible.';
          _waitForNetworkReconnect(song);
        }
        debugPrint('[SoundNeed] PlayerException: ${e.message}');
        return;
      } on PlatformException catch (e) {
        if (token != _playToken) return;
        // Errores del lado nativo (Android MediaCodec)
        playbackError =
            'Error del sistema: ${e.message}. '
            'Posible incompatibilidad de formato en tu dispositivo.';
        _waitForNetworkReconnect(song);
        debugPrint('[SoundNeed] PlatformException: ${e.code} ${e.message}');
        return;
      } catch (e) {
        if (token != _playToken) return;
        playbackError =
            'Error al preparar el audio: $e. '
            'El stream seleccionado puede no ser compatible.';
        _waitForNetworkReconnect(song);
        debugPrint('[SoundNeed] Error en setAudioSource: $e');
        return;
      }

      if (token != _playToken) return;

      if (initialPosition != null && initialPosition > Duration.zero) {
        final duration = _audioPlayer.duration;
        final requested = initialPosition.inMilliseconds;
        final maximum = duration?.inMilliseconds;
        final safePosition = maximum != null && maximum > 0
            ? Duration(milliseconds: requested.clamp(0, maximum - 1).toInt())
            : initialPosition;
        try {
          await _audioPlayer.seek(safePosition);
        } catch (error) {
          debugPrint(
            '[SoundNeed] Esta fuente no permitió restaurar la posición: $error',
          );
        }
      }

      _retryOnReconnect = false;
      _reconnectedWhileLoading = false;
      _loadedSong = song;
      _currentSong = song;
      _isPlaying = false;
      notifyListeners();

      if (startPaused) {
        await _savePlaybackSession();
      } else {
        _queueStartListening(song);
        _startProgressUpdateTimer();
        // Esta espera solo termina al pausar o al terminar toda la canción.
        // Se ejecuta en segundo plano, sin timeout de 45 s.
        unawaited(_startAudioPlayback(token));
      }
    } catch (e) {
      if (token != _playToken) return;
      playbackError = 'Error inesperado: $e';
      _waitForNetworkReconnect(song);
      debugPrint('[SoundNeed] Error general en playSong: $e');
    } finally {
      if (_loadingOnline && token == _playToken) {
        _loadingOnline = false;
        notifyListeners();
      }
      if (_reconnectedWhileLoading && _retryOnReconnect) {
        _reconnectedWhileLoading = false;
        Future<void>.delayed(
          const Duration(seconds: 1),
          _retryCurrentOnlineSong,
        );
      }
    }
  }

  void _waitForNetworkReconnect(Song song) {
    if (!song.isOnline) return;
    _retryOnReconnect = true;
    _onlineAudioSources.remove(song.onlineVideoId);
  }

  bool _isRefreshableOnlineAudioError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('403') ||
        message.contains('410') ||
        message.contains('http status error') ||
        message.contains('source error');
  }

  void _refreshExpiredOnlineAudioUrl(Song song, Object error) {
    final videoId = song.onlineVideoId;
    if (videoId.isEmpty || !_refreshingOnlineAudioUrls.add(videoId)) return;

    final attempts = _onlineAudioUrlRefreshAttempts[videoId] ?? 0;
    if (attempts >= 2) {
      _refreshingOnlineAudioUrls.remove(videoId);
      playbackError =
          'YouTube rechazó el enlace de audio después de varios intentos.';
      _isPlaying = false;
      _progressUpdateTimer?.cancel();
      notifyListeners();
      debugPrint(
        '[SoundNeed] Se agotaron los reintentos de URL para $videoId: $error',
      );
      return;
    }

    _onlineAudioUrlRefreshAttempts[videoId] = attempts + 1;
    _youtubeUrlCache.remove(videoId);
    _onlineAudioSources.remove(videoId);
    _saveYoutubeUrlCache();
    _retryOnReconnect = false;
    playbackError = 'Actualizando el enlace de audio…';
    _isPlaying = false;
    notifyListeners();
    debugPrint(
      '[SoundNeed] URL de audio vencida para $videoId; extrayendo una nueva.',
    );

    unawaited(() async {
      try {
        if (_currentSong?.id == song.id && !_controllerDisposed) {
          await playSong(song, createQueue: false, retry: true);
        }
      } finally {
        _refreshingOnlineAudioUrls.remove(videoId);
      }
    }());
  }

  Future<void> _publishProcessedArtwork(Song song, int token) async {
    try {
      final bytes = await loadOnlineArtwork(song);
      if (bytes == null || token != _playToken) return;
      final uri = await _channel.invokeMethod<String>(
        'cacheOnlineArtwork',
        <String, Object?>{'key': song.onlineVideoId, 'bytes': bytes},
      );
      if (uri == null || token != _playToken) return;
      _audioHandler.updateMediaItemArtwork(
        _mediaItemFor(song, artworkUriOverride: Uri.parse(uri)),
      );
    } catch (error) {
      debugPrint(
        '[SoundNeed] No se pudo publicar la portada recortada: $error',
      );
    }
  }

  Future<void> _startAudioPlayback(int token) async {
    try {
      await _audioPlayer.play();
    } catch (error) {
      if (token != _playToken) return;
      playbackError = 'Error al reproducir: $error';
      final song = _currentSong;
      if (song != null &&
          song.isOnline &&
          _isRefreshableOnlineAudioError(error)) {
        _refreshExpiredOnlineAudioUrl(song, error);
      } else if (song != null) {
        _waitForNetworkReconnect(song);
      }
      _isPlaying = false;
      _progressUpdateTimer?.cancel();
      notifyListeners();
    }
  }

  MediaItem _mediaItemFor(Song song, {Uri? artworkUriOverride}) => MediaItem(
    id: song.id.toString(),
    title: song.title.isEmpty ? song.displayName : song.title,
    artist: song.artist,
    album: song.album,
    duration: song.duration > 0 ? Duration(milliseconds: song.duration) : null,
    artUri:
        artworkUriOverride ??
        (song.artworkUri.isNotEmpty ? Uri.tryParse(song.artworkUri) : null),
    playable: true,
  );

  void _enqueueRecommendation(Future<void> Function() operation) {
    _recommendationQueue = _recommendationQueue.then((_) async {
      try {
        await operation();
      } catch (error) {
        debugPrint('[SoundNeed] Error de recomendaciones: $error');
      }
    });
  }

  void _queueStopListening(Song? song) {
    if (song == null || song.isPodcast) return;
    final position = _audioPlayer.position.inSeconds;
    final duration = _audioPlayer.duration?.inSeconds;
    _enqueueRecommendation(
      () => RecommendationService.instance.stopListening(
        positionSeconds: position,
        durationSeconds: duration,
      ),
    );
  }

  void _queueStartListening(Song song) {
    if (song.isPodcast) return;
    _enqueueRecommendation(
      () => RecommendationService.instance.startListening(
        id: song.isOnline ? song.onlineVideoId : song.id.toString(),
        title: song.title.isEmpty ? song.displayName : song.title,
        artist: song.artist,
        thumbnail: song.artworkUri.isNotEmpty ? song.artworkUri : null,
        source: song.isOnline ? 'youtube' : 'local',
        durationSeconds: (song.duration / 1000).round(),
      ),
    );
  }

  Future<void> playPlaylist(
    List<Song> songs, {
    int startIndex = 0,
    bool shuffle = false,
  }) async {
    if (songs.isEmpty) return;
    final safeIndex = startIndex.clamp(0, songs.length - 1);
    final selected = songs[safeIndex];
    _queue = List<Song>.from(songs);
    if (shuffle) {
      _queue.removeAt(safeIndex);
      _queue.shuffle();
      _queue.insert(0, selected);
      _playbackMode = modeShuffle;
      _queueIndex = 0;
    } else {
      _queueIndex = safeIndex;
    }
    notifyListeners();
    await playSong(selected, createQueue: false);
  }

  /// Adds a track at the end of the current queue without interrupting it.
  void addToQueue(Song song) {
    if (_queue.isEmpty) {
      if (_currentSong != null) {
        _queue = <Song>[_currentSong!];
        _queueIndex = 0;
        _queue.add(song);
      } else {
        _queue = <Song>[song];
        _queueIndex = -1;
      }
    } else {
      if (_queueIndex < 0 && _currentSong != null) {
        _queue.insert(0, _currentSong!);
        _queueIndex = 0;
      }
      _queue.add(song);
    }
    unawaited(_savePlaybackSession());
    notifyListeners();
  }

  /// Reproduce un resultado de YouTube. Si pasas [playlist], esos
  /// resultados forman la cola (siguiente / anterior funcionan).
  /// Devuelve false si falló (ver [playbackError]).
  Future<bool> playOnline(
    YouTubeSearchResult result, {
    List<YouTubeSearchResult>? playlist,
    bool repeatAll = false,
  }) async {
    final source = (playlist == null || playlist.isEmpty)
        ? <YouTubeSearchResult>[result]
        : playlist;

    final song = Song.fromYouTube(result);
    _pendingChartQueue = null;

    _queue = source.map(Song.fromYouTube).toList();

    var index = _queue.indexWhere((s) => s.id == song.id);

    if (index == -1) {
      _queue.insert(0, song);
      index = 0;
    }

    _queueIndex = index;
    if (repeatAll) _playbackMode = modeRepeatAll;

    await playSong(_queue[_queueIndex], createQueue: false);

    return playbackError == null;
  }

  /// Completa en segundo plano la cola de un tema de tendencias.
  /// La primera canción empieza a sonar sin esperar las demás búsquedas.
  void loadChartQueue(
    String currentVideoId,
    Future<List<YouTubeSearchResult>> queueFuture,
  ) {
    late final Future<void> pending;
    pending = queueFuture
        .then((results) {
          if (_currentSong?.onlineVideoId != currentVideoId ||
              results.length < 2) {
            return;
          }
          final songs = results.map(Song.fromYouTube).toList();
          final currentIndex = songs.indexWhere(
            (song) => song.onlineVideoId == currentVideoId,
          );
          if (currentIndex < 0) return;
          _queue = songs;
          _queueIndex = currentIndex;
          notifyListeners();
        })
        .catchError((Object error) {
          debugPrint(
            '[SoundNeed] No se pudo completar la cola de tendencias: $error',
          );
        })
        .whenComplete(() {
          if (identical(_pendingChartQueue, pending)) _pendingChartQueue = null;
        });
    _pendingChartQueue = pending;
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

    if (_loadingOnline) {
      // Si se pulsa pausa mientras resolvemos el stream, cancela esa solicitud.
      ++_playToken;
      _loadingOnline = false;
      _isPlaying = false;
      notifyListeners();
      return;
    }

    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
      _progressUpdateTimer?.cancel();
      await _savePlaybackSession();
    } else {
      final song = _currentSong!;
      if (_loadedSong == null ||
          _loadedSong!.id != song.id ||
          _loadedSong!.uri != song.uri) {
        await playSong(song, createQueue: false, retry: true);
        return;
      }
      if (_audioPlayer.processingState == ProcessingState.completed) {
        await _audioPlayer.seek(Duration.zero);
      }
      _queueStartListening(song);
      _recordRecentPlayback(song);
      unawaited(_savePlaybackSession());
      _startProgressUpdateTimer();
      unawaited(_startAudioPlayback(_playToken));
    }
  }

  // ============================================================
  // SIGUIENTE
  // ============================================================

  Future<void> nextSong() async {
    if (_queue.length <= 1 && _pendingChartQueue != null) {
      await _pendingChartQueue;
    }
    if (_songs.isEmpty && _queue.isEmpty) return;

    if (_queue.isEmpty) {
      _queue = List<Song>.from(_songs);
    }

    Song? nextSong;

    if (shuffleEnabled) {
      nextSong = _getRandomSong();
      _queueIndex = _queue.indexWhere((song) => song.id == nextSong?.id);
    } else {
      if (_queueIndex < 0) {
        _queueIndex = 0;
      } else {
        _queueIndex++;
      }

      if (_queueIndex >= _queue.length) {
        if (repeatEnabled) {
          _queueIndex = 0;
        } else {
          _queueIndex = _queue.length - 1;

          if (_autoContinueEnabled) {
            await _continueWithRecommendations();
            return;
          }

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
    if (_songs.isEmpty && _queue.isEmpty) return;

    if (_queue.isEmpty) {
      _queue = List<Song>.from(_songs);
    }

    if (_audioPlayer.position.inSeconds > 3) {
      await _audioPlayer.seek(Duration.zero);
      return;
    }

    if (shuffleEnabled) {
      final previousSong = _getRandomSong();
      _queueIndex = _queue.indexWhere((song) => song.id == previousSong?.id);

      if (previousSong != null) {
        await playSong(previousSong, createQueue: false);
      }

      return;
    }

    _queueIndex--;

    if (_queueIndex < 0) {
      if (repeatEnabled) {
        _queueIndex = _queue.length - 1;
      } else {
        _queueIndex = 0;
      }
    }

    await playSong(_queue[_queueIndex], createQueue: false);
  }

  // ============================================================
  // CANCIÓN TERMINADA
  // ============================================================

  Future<void> _handleSongCompleted() async {
    if (_loadingAutoContinue) return;
    if (_queue.length <= 1 && _pendingChartQueue != null) {
      await _pendingChartQueue;
    }
    if (_playbackMode == modeRepeatOne && _currentSong != null) {
      await _audioPlayer.seek(Duration.zero);
      await _audioPlayer.play();
      _startProgressUpdateTimer();
      return;
    }

    if (shuffleEnabled) {
      final nextSong = _getRandomSong();
      _queueIndex = _queue.indexWhere((song) => song.id == nextSong?.id);

      if (nextSong != null) {
        await playSong(nextSong, createQueue: false);
      }

      return;
    }

    if (_queue.isEmpty) {
      if (_autoContinueEnabled) await _continueWithRecommendations();
      return;
    }

    final nextIndex = _queueIndex + 1;

    if (nextIndex >= _queue.length) {
      if (repeatEnabled) {
        _queueIndex = 0;

        await playSong(_queue[_queueIndex], createQueue: false);
      } else if (_autoContinueEnabled) {
        _isPlaying = false;
        notifyListeners();
        await _continueWithRecommendations();
      } else {
        _isPlaying = false;
        await _savePlaybackSession();
        notifyListeners();
      }

      return;
    }

    _queueIndex = nextIndex;

    await playSong(_queue[_queueIndex], createQueue: false);
  }

  Future<void> _continueWithRecommendations() async {
    if (_loadingAutoContinue || !_autoContinueEnabled) return;
    _loadingAutoContinue = true;
    final token = _playToken;
    try {
      final candidates = <Song>[];
      final seen = <String>{};

      void addCandidate(Song song) {
        final key = _songPlaybackKey(song);
        if (song.id == _currentSong?.id && song.uri == _currentSong?.uri)
          return;
        if (_recentPlaybackKeys.contains(key) || !seen.add(key)) return;
        candidates.add(song);
      }

      void addLearnedSong(LearnedSong learned) {
        if (learned.source == 'local') {
          for (final local in _songs) {
            if (local.id.toString() == learned.id) {
              addCandidate(local);
              return;
            }
          }
          return;
        }

        if (learned.source != 'youtube' ||
            !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(learned.id)) {
          return;
        }
        addCandidate(
          Song.fromYouTube(
            YouTubeSearchResult(
              videoId: learned.id,
              title: learned.title,
              artist: learned.artist,
              duration: learned.durationSeconds,
              thumbnail: learned.thumbnail,
              url: 'https://www.youtube.com/watch?v=${learned.id}',
            ),
          ),
        );
      }

      final recommendations = await RecommendationService.instance
          .getRecommendations(limit: 40);
      for (final learned in recommendations) {
        addLearnedSong(learned);
        if (candidates.length >= 12) break;
      }

      if (candidates.length < 5) {
        final discoveries = await RecommendationService.instance
            .discoverNewSongs(limit: 16);
        for (final learned in discoveries) {
          addLearnedSong(learned);
          if (candidates.length >= 12) break;
        }
      }

      // Si no hay red o historial suficiente, recorre música local sin
      // repetir las últimas canciones escuchadas.
      if (candidates.isEmpty) {
        for (final local in _songs) {
          addCandidate(local);
        }
      }
      if (candidates.isEmpty && _songs.isNotEmpty) {
        _recentPlaybackKeys.clear();
        for (final local in _songs) {
          addCandidate(local);
        }
      }
      if (token != _playToken || candidates.isEmpty) {
        _isPlaying = false;
        await _savePlaybackSession();
        notifyListeners();
        return;
      }

      _queue = candidates;
      _queueIndex = 0;
      _playbackMode = modeNormal;
      notifyListeners();
      await playSong(_queue.first, createQueue: false);
    } catch (error) {
      debugPrint(
        '[SoundNeed] No se pudo continuar con recomendaciones: $error',
      );
      _isPlaying = false;
      notifyListeners();
    } finally {
      _loadingAutoContinue = false;
    }
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

    final available = pool.where((song) => song.id != currentId).toList();

    if (available.isEmpty) {
      return pool.first;
    }

    available.shuffle();

    return available.first;
  }

  void toggleShuffle() {
    _playbackMode = shuffleEnabled ? modeNormal : modeShuffle;
    notifyListeners();
  }

  // ============================================================
  // REPETICIÓN
  // ============================================================

  void toggleRepeat() {
    _playbackMode = repeatEnabled ? modeNormal : modeRepeatAll;
    notifyListeners();
  }

  void cyclePlaybackMode() {
    _playbackMode = (_playbackMode + 1) % 4;
    notifyListeners();
  }

  // ============================================================
  // SEEK
  // ============================================================

  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
    unawaited(_savePlaybackSession());

    // Si se hace seek al inicio, contarlo como replay
    if (position.inSeconds < 3 &&
        _currentSong != null &&
        !_currentSong!.isPodcast) {
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

      Uint8List? bytes = response.statusCode == 200 ? response.bodyBytes : null;
      if (bytes != null && song.isOnline) {
        bytes = await _cropYouTubeLetterbox(bytes);
      }

      if (bytes != null) _onlineArtworkCache[song.id] = bytes;

      return bytes;
    } catch (e) {
      debugPrint('Error descargando portada online: $e');

      return null;
    }
  }

  Future<Uint8List> _cropYouTubeLetterbox(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    try {
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (raw == null) return bytes;
      final pixels = raw.buffer.asUint8List(
        raw.offsetInBytes,
        raw.lengthInBytes,
      );
      const samples = 32;
      final maxCrop = (image.height * 0.30).floor();

      bool isDarkRow(int y) {
        var darkPixels = 0;
        for (var sample = 0; sample < samples; sample++) {
          final x = sample * (image.width - 1) ~/ (samples - 1);
          final offset = (y * image.width + x) * 4;
          if (pixels[offset] <= 20 &&
              pixels[offset + 1] <= 20 &&
              pixels[offset + 2] <= 20) {
            darkPixels++;
          }
        }
        return darkPixels >= samples * 0.94;
      }

      var top = 0;
      while (top < maxCrop && isDarkRow(top)) {
        top++;
      }
      var bottom = 0;
      while (bottom < maxCrop && isDarkRow(image.height - bottom - 1)) {
        bottom++;
      }
      if (top + bottom < image.height * 0.04) return bytes;

      final cropHeight = image.height - top - bottom;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(
          0,
          top.toDouble(),
          image.width.toDouble(),
          cropHeight.toDouble(),
        ),
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), cropHeight.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final cropped = await recorder.endRecording().toImage(
        image.width,
        cropHeight,
      );
      try {
        final encoded = await cropped.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (encoded == null) return bytes;
        return encoded.buffer.asUint8List(
          encoded.offsetInBytes,
          encoded.lengthInBytes,
        );
      } finally {
        cropped.dispose();
      }
    } finally {
      image.dispose();
      codec.dispose();
    }
  }

  Future<Uint8List?> loadArtwork(Song song) async {
    if (song.isOnline || song.isPodcast) {
      return loadOnlineArtwork(song);
    }

    if (song.artworkUri.startsWith('file://')) {
      try {
        return await File.fromUri(Uri.parse(song.artworkUri)).readAsBytes();
      } catch (error) {
        debugPrint('[SoundNeed] No se pudo leer la portada guardada: $error');
      }
    }

    // Leer primero la portada incrustada en el archivo. Usar albumId primero
    // puede asignar la misma carátula a canciones distintas que comparten
    // álbum en MediaStore (por ejemplo, descargas de YouTube).
    final cacheKey = song.id;
    if (_artworkCache.containsKey(cacheKey)) {
      return _artworkCache[cacheKey];
    }

    try {
      final Uint8List? artwork = await _channel.invokeMethod<Uint8List>(
        'getArtwork',
        {'uri': song.uri},
      );

      if (artwork != null && artwork.isNotEmpty) {
        _artworkCache[cacheKey] = artwork;
        return artwork;
      }
    } catch (e) {
      debugPrint('Error obteniendo portada por URI: $e');
    }

    final albumId = song.albumId;
    if (albumId != null && albumId > 0) {
      try {
        final Uint8List? artwork = await _channel.invokeMethod<Uint8List>(
          'getArtwork',
          {'albumId': albumId},
        );
        _artworkCache[cacheKey] = artwork;
        return artwork;
      } catch (e) {
        debugPrint('Error obteniendo portada por albumId: $e');
      }
    }

    _artworkCache[cacheKey] = null;
    return null;
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
    unawaited(_savePlaybackSession());
  }

  // ============================================================
  // RECOMMENDATION SERVICE - TIMER DE PROGRESO
  // ============================================================

  void _startProgressUpdateTimer() {
    _progressUpdateTimer?.cancel();

    _progressUpdateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_currentSong != null &&
          !_currentSong!.isPodcast &&
          _audioPlayer.playing) {
        final position = _audioPlayer.position.inSeconds;
        final duration = _audioPlayer.duration?.inSeconds;

        RecommendationService.instance.updateProgress(
          positionSeconds: position,
          durationSeconds: duration,
        );
      }
    });
  }

  @override
  void dispose() {
    _controllerDisposed = true;
    _audioHandler.onStopRequested = null;
    _progressUpdateTimer?.cancel();
    _resumeSaveTimer?.cancel();
    _sleepTimer?.cancel();
    unawaited(_savePlaybackSession());
    unawaited(_networkSubscription?.cancel() ?? Future<void>.value());
    unawaited(_downloadProgressSubscription?.cancel() ?? Future<void>.value());
    unawaited(_playerErrorSubscription?.cancel() ?? Future<void>.value());
    unawaited(_audioSessionSubscription?.cancel() ?? Future<void>.value());
    unawaited(EqualizerService.instance.release());
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_controllerDisposed) super.notifyListeners();
  }
}

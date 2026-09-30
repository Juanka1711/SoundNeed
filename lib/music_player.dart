import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    );
  }
}

class MusicPlayerController extends ChangeNotifier {
  static const MethodChannel _channel = MethodChannel('music_player/media');

  final AudioPlayer _audioPlayer = AudioPlayer();

  late SharedPreferences _preferences;

  List<Song> _songs = [];
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

  // Getters
  List<Song> get songs => _songs;
  List<Song> get queue => _queue;
  Song? get currentSong => _currentSong;
  bool get loading => _loading;
  bool get permissionDenied => _permissionDenied;
  bool get isPlaying => _isPlaying;
  bool get shuffleEnabled => _shuffleEnabled;
  bool get repeatEnabled => _repeatEnabled;
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

      _songs = songs;
      _loading = false;
      _permissionDenied = false;
      notifyListeners();

      if (_queue.isEmpty && songs.isNotEmpty) {
        _queue = List<Song>.from(songs);
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
    } else {
      _favoriteIds.add(song.id);
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
    try {
      if (createQueue) {
        _createQueueFromSong(song);
      }

      final mediaItem = MediaItem(
        id: song.id.toString(),
        title: song.title.isEmpty
            ? song.displayName
            : song.title,
        artist: song.artist,
        album: song.album,
        duration: Duration(
          milliseconds: song.duration,
        ),
        playable: true,
      );

      await _audioPlayer.setAudioSource(
        AudioSource.uri(
          Uri.parse(song.uri),
          tag: mediaItem,
        ),
      );

      _currentSong = song;
      _isPlaying = true;
      notifyListeners();

      await _audioPlayer.play();
    } catch (e) {
      debugPrint('Error reproduciendo canción: $e');
    }
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
    } else {
      await _audioPlayer.play();
    }
  }

  // ============================================================
  // SIGUIENTE
  // ============================================================

  Future<void> nextSong() async {
    if (_songs.isEmpty) return;

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
    if (_songs.isEmpty) return;

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
    if (_songs.isEmpty) {
      return null;
    }

    final currentId = _currentSong?.id;

    final available = _songs
        .where((song) => song.id != currentId)
        .toList();

    if (available.isEmpty) {
      return _songs.first;
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
  }

  // ============================================================
  // PORTADAS
  // ============================================================

  Future<Uint8List?> loadArtwork(Song song) async {
    final albumId = song.albumId;

    if (albumId == null || albumId <= 0) {
      return null;
    }

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

      return artwork;
    } catch (e) {
      debugPrint('Error obteniendo portada: $e');

      _artworkCache[albumId] = null;

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

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}

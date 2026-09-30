import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.music_player.channel.audio',
    androidNotificationChannelName: 'SoundNeed',
    androidNotificationChannelDescription:
        'Controles de reproducción de SoundNeed',
    androidNotificationOngoing: true,
  );

  runApp(const MusicPlayerApp());
}

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key});

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
        ),

        cardTheme: const CardThemeData(
          color: card,
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
      home: const MusicHomePage(),
    );
  }
}

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

class MusicHomePage extends StatefulWidget {
  const MusicHomePage({super.key});

  @override
  State<MusicHomePage> createState() => _MusicHomePageState();
}

class _MusicHomePageState extends State<MusicHomePage> {
  static const MethodChannel _channel = MethodChannel('music_player/media');

  final AudioPlayer _audioPlayer = AudioPlayer();
  final TextEditingController _searchController = TextEditingController();

  late SharedPreferences _preferences;

  List<Song> _songs = [];
  List<Song> _filteredSongs = [];
  List<Song> _queue = [];

  Song? _currentSong;

  final Set<int> _favoriteIds = {};

  bool _loading = true;
  bool _permissionDenied = false;
  bool _isPlaying = false;
  bool _isSearching = false;

  bool _shuffleEnabled = false;
  bool _repeatEnabled = false;

  bool _showFavoritesOnly = false;

  String _searchText = '';

  int _queueIndex = -1;

  final Map<int, Uint8List?> _artworkCache = {};

  @override
  void initState() {
    super.initState();

    _searchController.addListener(() {
      _filterSongs(_searchController.text);
    });

    _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;

      setState(() {
        _isPlaying = state.playing;
      });
    });

    _audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _handleSongCompleted();
      }
    });

    _initialize();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ============================================================
  // INICIALIZACION
  // ============================================================
Future<void> _initialize() async {
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

    await _loadSongs();
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

  Future<void> _loadSongs() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _permissionDenied = false;
      });
    }

    try {
      bool permission = await _checkPermission();

      if (!permission) {
        permission = await _requestPermission();
      }

      if (!permission) {
        if (!mounted) return;

        setState(() {
          _loading = false;
          _permissionDenied = true;
        });

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

      if (!mounted) return;

      setState(() {
        _songs = songs;
        _loading = false;
        _permissionDenied = false;
      });

      _filterSongs(_searchController.text);

      if (_queue.isEmpty && songs.isNotEmpty) {
        _queue = List<Song>.from(songs);
        _queueIndex = -1;
      }
    } catch (e) {
      debugPrint('Error cargando canciones: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      _showMessage('No se pudieron cargar las canciones.');
    }
  }

  // ============================================================
  // FAVORITOS
  // ============================================================

  bool _isFavorite(Song song) {
    return _favoriteIds.contains(song.id);
  }

  Future<void> _toggleFavorite(Song song) async {
    setState(() {
      if (_favoriteIds.contains(song.id)) {
        _favoriteIds.remove(song.id);
      } else {
        _favoriteIds.add(song.id);
      }
    });

    await _saveFavorites();

    if (!mounted) return;

    _filterSongs(_searchController.text);

    _showMessage(
      _isFavorite(song)
          ? 'Añadida a favoritos ❤️'
          : 'Eliminada de favoritos',
    );
  }

  Future<void> _saveFavorites() async {
    await _preferences.setStringList(
      'favorite_song_ids',
      _favoriteIds.map((id) => id.toString()).toList(),
    );
  }

  // ============================================================
  // BUSCADOR Y FILTROS
  // ============================================================

  void _filterSongs(String value) {
    final query = value.trim().toLowerCase();

    if (!mounted) return;

    setState(() {
      _searchText = query;

      Iterable<Song> result = _songs;

      if (_showFavoritesOnly) {
        result = result.where(
          (song) => _favoriteIds.contains(song.id),
        );
      }

      if (query.isNotEmpty) {
        result = result.where((song) {
          final title = song.title.toLowerCase();
          final artist = song.artist.toLowerCase();
          final album = song.album.toLowerCase();
          final fileName = song.displayName.toLowerCase();

          return title.contains(query) ||
              artist.contains(query) ||
              album.contains(query) ||
              fileName.contains(query);
        });
      }

      _filteredSongs = result.toList();
    });
  }

  void _toggleFavoritesFilter() {
    setState(() {
      _showFavoritesOnly = !_showFavoritesOnly;
    });

    _filterSongs(_searchController.text);
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
    });

    if (!_isSearching) {
      _searchController.clear();
      FocusScope.of(context).unfocus();
    }
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

 Future<void> _playSong(
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

    if (!mounted) return;

    // Mostramos inmediatamente el reproductor inferior
    setState(() {
      _currentSong = song;
      _isPlaying = true;
    });

    // Comenzamos la reproducción
    await _audioPlayer.play();
  } catch (e) {
    debugPrint('Error reproduciendo canción: $e');

    _showMessage(
      'No se pudo reproducir esta canción.',
    );
  }
}

  // ============================================================
  // PLAY / PAUSE
  // ============================================================

  Future<void> _togglePlayPause() async {
    if (_currentSong == null) {
      if (_songs.isNotEmpty) {
        await _playSong(_songs.first);
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

  Future<void> _nextSong() async {
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
      await _playSong(nextSong, createQueue: false);
    }
  }

  // ============================================================
  // ANTERIOR
  // ============================================================

  Future<void> _previousSong() async {
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
        await _playSong(previousSong, createQueue: false);
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

    await _playSong(
      _queue[_queueIndex],
      createQueue: false,
    );
  }

  // ============================================================
  // CANCIÓN TERMINADA
  // ============================================================

  Future<void> _handleSongCompleted() async {
    if (!mounted) return;

    if (_shuffleEnabled) {
      final nextSong = _getRandomSong();

      if (nextSong != null) {
        await _playSong(
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

        await _playSong(
          _queue[_queueIndex],
          createQueue: false,
        );
      } else {
        setState(() {
          _isPlaying = false;
        });
      }

      return;
    }

    _queueIndex = nextIndex;

    await _playSong(
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

  void _toggleShuffle() {
    setState(() {
      _shuffleEnabled = !_shuffleEnabled;
    });

    _showMessage(
      _shuffleEnabled
          ? 'Reproducción aleatoria activada'
          : 'Reproducción aleatoria desactivada',
    );
  }

  // ============================================================
  // REPETICIÓN
  // ============================================================

  void _toggleRepeat() {
    setState(() {
      _repeatEnabled = !_repeatEnabled;
    });

    _showMessage(
      _repeatEnabled
          ? 'Repetición activada'
          : 'Repetición desactivada',
    );
  }

  // ============================================================
  // PORTADAS
  // ============================================================

  Future<Uint8List?> _loadArtwork(Song song) async {
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

  Widget _buildArtwork(
    Song song, {
    double size = 56,
  }) {
    return FutureBuilder<Uint8List?>(
      future: _loadArtwork(song),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              snapshot.data!,
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          );
        }

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: MusicPlayerApp.primary.withOpacity(0.20),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: MusicPlayerApp.primary.withOpacity(0.25),
            ),
          ),
          child: Icon(
            Icons.music_note,
            size: size * 0.48,
            color: MusicPlayerApp.secondary,
          ),
        );
      },
    );
  }

  // ============================================================
  // UTILIDADES
  // ============================================================

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);

    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ============================================================
  // INTERFAZ
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(
                  color: Colors.white,
                ),
                decoration: const InputDecoration(
                  hintText: 'Buscar canción, artista o álbum...',
                  border: InputBorder.none,
                ),
              )
            : Text(
                _showFavoritesOnly ? 'Favoritos' : 'SoundNeed',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
        actions: [
          IconButton(
            tooltip: 'Favoritos',
            onPressed: _toggleFavoritesFilter,
            icon: Icon(
              _showFavoritesOnly
                  ? Icons.favorite
                  : Icons.favorite_border,
              color: _showFavoritesOnly
                  ? MusicPlayerApp.favorite
                  : null,
            ),
          ),
          IconButton(
            tooltip: 'Buscar',
            onPressed: _toggleSearch,
            icon: Icon(
              _isSearching ? Icons.close : Icons.search,
            ),
          ),
          IconButton(
            tooltip: 'Cola',
            onPressed: _showQueue,
            icon: const Icon(Icons.queue_music),
          ),
          IconButton(
            tooltip: 'Actualizar biblioteca',
            onPressed: _loading ? null : _loadSongs,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_isSearching) _buildLibraryHeader(),
          Expanded(child: _buildSongList()),
          if (_currentSong != null) _buildBottomPlayer(),
        ],
      ),
    );
  }

  // ============================================================
  // ENCABEZADO
  // ============================================================

  Widget _buildLibraryHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: [
          Icon(
            _showFavoritesOnly
                ? Icons.favorite
                : Icons.library_music,
            color: _showFavoritesOnly
                ? MusicPlayerApp.favorite
                : MusicPlayerApp.primary,
          ),
          const SizedBox(width: 10),
          Text(
            _showFavoritesOnly
                ? 'Mis favoritos'
                : 'Biblioteca',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Text(
            '${_filteredSongs.length}',
            style: const TextStyle(
              color: MusicPlayerApp.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // LISTA
  // ============================================================

  Widget _buildSongList() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_permissionDenied) {
      return _buildPermissionMessage();
    }

    if (_songs.isEmpty) {
      return _buildEmptyLibrary();
    }

    if (_filteredSongs.isEmpty) {
      if (_showFavoritesOnly) {
        return _buildNoFavorites();
      }

      return _buildNoResults();
    }

    return RefreshIndicator(
      color: MusicPlayerApp.primary,
      onRefresh: _loadSongs,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 12),
        itemCount: _filteredSongs.length,
        itemBuilder: (context, index) {
          final song = _filteredSongs[index];
          final isCurrent = _currentSong?.id == song.id;

          return _buildSongTile(
            song,
            isCurrent,
          );
        },
      ),
    );
  }

  // ============================================================
  // CANCIÓN
  // ============================================================

  Widget _buildSongTile(
    Song song,
    bool isCurrent,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 4,
      ),
      leading: _buildArtwork(
        song,
        size: 58,
      ),
      title: Text(
        song.title.isEmpty
            ? song.displayName
            : song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight:
              isCurrent ? FontWeight.bold : FontWeight.w500,
          color: isCurrent
              ? MusicPlayerApp.secondary
              : Colors.white,
        ),
      ),
      subtitle: Text(
        '${song.artist} • ${song.album}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: MusicPlayerApp.textSecondary,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatDuration(song.duration),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 12,
            ),
          ),
          IconButton(
            tooltip: _isFavorite(song)
                ? 'Quitar de favoritos'
                : 'Añadir a favoritos',
            onPressed: () => _toggleFavorite(song),
            icon: Icon(
              _isFavorite(song)
                  ? Icons.favorite
                  : Icons.favorite_border,
              color: _isFavorite(song)
                  ? MusicPlayerApp.favorite
                  : Colors.white38,
            ),
          ),
        ],
      ),
      onTap: () => _playSong(song),
    );
  }

  // ============================================================
  // SIN FAVORITOS
  // ============================================================

  Widget _buildNoFavorites() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite_border,
              size: 80,
              color: Colors.white.withOpacity(0.25),
            ),
            const SizedBox(height: 20),
            const Text(
              'No tienes favoritos',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Pulsa el corazón de una canción para añadirla a tus favoritos.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MusicPlayerApp.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SIN RESULTADOS
  // ============================================================

  Widget _buildNoResults() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 70,
              color: Colors.white.withOpacity(0.25),
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
              'No hay resultados para "$_searchText".',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MusicPlayerApp.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BIBLIOTECA VACÍA
  // ============================================================

  Widget _buildEmptyLibrary() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.music_off,
              size: 80,
              color: Colors.white.withOpacity(0.25),
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
                color: MusicPlayerApp.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _loadSongs,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // PERMISO
  // ============================================================

  Widget _buildPermissionMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 80,
              color: Colors.white.withOpacity(0.25),
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
                color: MusicPlayerApp.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _loadSongs,
              icon: const Icon(Icons.lock_open),
              label: const Text('Conceder permiso'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // COLA
  // ============================================================

  void _showQueue() {
    showModalBottomSheet(
      context: context,
      backgroundColor: MusicPlayerApp.surface,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.70,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Icon(
                        Icons.queue_music,
                        color: MusicPlayerApp.primary,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Cola de reproducción',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: _queue.isEmpty
                      ? const Center(
                          child: Text(
                            'La cola está vacía.',
                            style: TextStyle(
                              color: MusicPlayerApp.textSecondary,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _queue.length,
                          itemBuilder: (context, index) {
                            final song = _queue[index];
                            final isCurrent =
                                _currentSong?.id == song.id;

                            return ListTile(
                              leading: _buildArtwork(
                                song,
                                size: 48,
                              ),
                              title: Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isCurrent
                                      ? MusicPlayerApp.secondary
                                      : Colors.white,
                                  fontWeight: isCurrent
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: isCurrent
                                  ? const Icon(
                                      Icons.equalizer,
                                      color:
                                          MusicPlayerApp.primary,
                                    )
                                  : null,
                              onTap: () async {
                                Navigator.pop(context);

                                _queueIndex = index;

                                await _playSong(
                                  song,
                                  createQueue: false,
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // REPRODUCTOR INFERIOR
  // ============================================================

  Widget _buildBottomPlayer() {
    final song = _currentSong!;

    return Container(
      decoration: BoxDecoration(
        color: MusicPlayerApp.card,
        border: Border(
          top: BorderSide(
            color: MusicPlayerApp.primary.withOpacity(0.20),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<Duration>(
            stream: _audioPlayer.positionStream,
            builder: (context, snapshot) {
              final position =
                  snapshot.data ?? Duration.zero;

              final duration =
                  _audioPlayer.duration ??
                  Duration(milliseconds: song.duration);

              final max = duration.inMilliseconds > 0
                  ? duration.inMilliseconds
                  : 1;

              final current =
                  position.inMilliseconds.clamp(0, max);

              return Slider(
                value: current.toDouble(),
                min: 0,
                max: max.toDouble(),
                onChanged: (value) {
                  _audioPlayer.seek(
                    Duration(
                      milliseconds: value.toInt(),
                    ),
                  );
                },
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              14,
              0,
              14,
              10,
            ),
            child: Row(
              children: [
                _buildArtwork(
                  song,
                  size: 52,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title.isEmpty
                            ? song.displayName
                            : song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MusicPlayerApp.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: _isFavorite(song)
                      ? 'Quitar de favoritos'
                      : 'Añadir a favoritos',
                  onPressed: () =>
                      _toggleFavorite(song),
                  icon: Icon(
                    _isFavorite(song)
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: _isFavorite(song)
                        ? MusicPlayerApp.favorite
                        : Colors.white54,
                  ),
                ),
                IconButton(
                  tooltip: 'Aleatorio',
                  onPressed: _toggleShuffle,
                  icon: Icon(
                    Icons.shuffle,
                    color: _shuffleEnabled
                        ? MusicPlayerApp.secondary
                        : Colors.white54,
                  ),
                ),
                IconButton(
                  tooltip: 'Anterior',
                  onPressed: _previousSong,
                  icon: const Icon(
                    Icons.skip_previous,
                  ),
                ),
                IconButton(
                  tooltip:
                      _isPlaying ? 'Pausar' : 'Reproducir',
                  onPressed: _togglePlayPause,
                  icon: Icon(
                    _isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                    size: 42,
                    color: MusicPlayerApp.primary,
                  ),
                ),
                IconButton(
                  tooltip: 'Siguiente',
                  onPressed: _nextSong,
                  icon: const Icon(
                    Icons.skip_next,
                  ),
                ),
                IconButton(
                  tooltip: 'Repetir',
                  onPressed: _toggleRepeat,
                  icon: Icon(
                    Icons.repeat,
                    color: _repeatEnabled
                        ? MusicPlayerApp.secondary
                        : Colors.white54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'music_player.dart';
import 'player_navigation.dart';
import 'mini_player.dart';
import 'sections/home_section.dart';
import 'sections/songs_section.dart';
import 'sections/playlists_section.dart';
import 'sections/folders_section.dart';
import 'sections/artists_section.dart';
import 'sections/albums_section.dart';
import 'services/youtube_audio_service.dart';
import 'services/artwork_palette.dart';
import 'widgets/soundneed_search_field.dart';

// ============================================================
// COLORES BASE DE SOUNDNEED
// ============================================================

class AppColors {
  static const Color background = Color(0xFF0B0B12);
  static const Color surface = Color(0xFF151522);
  static const Color card = Color(0xFF1D1D2B);

  // Solo para acciones semánticas.
  static const Color favorite = Color(0xFFF43F5E);

  static const Color textSecondary = Color(0xFFA1A1AA);
}

// ============================================================
// SECCIONES PRINCIPALES
// ============================================================

enum MusicSection { home, songs, playlists, folders, artists, albums }

// ============================================================
// HOME
// ============================================================

class MusicHomePage extends StatefulWidget {
  final MusicPlayerController player;

  const MusicHomePage({super.key, required this.player});

  @override
  State<MusicHomePage> createState() => _MusicHomePageState();
}

class _MusicHomePageState extends State<MusicHomePage> {
  final TextEditingController _searchController = TextEditingController();

  List<Song> _filteredSongs = [];

  bool _isSearching = false;
  bool _appBarVisible = true;
  double _scrollDeltaSinceDirectionChange = 0;
  static const double _appBarScrollThreshold = 28;
  String _searchText = '';

  ArtworkPalette _appPalette = ArtworkPalette.neutral;
  int? _paletteSongId;
  int _paletteRequest = 0;

  // ==========================================================
  // ONLINE SEARCH
  // ==========================================================

  bool _isSearchingOnline = false;
  List<YouTubeSearchResult> _onlineResults = [];
  String _onlineQuery = '';
  Timer? _onlineSearchDebounce;

  MusicSection _section = MusicSection.home;

  @override
  void initState() {
    super.initState();

    _searchController.addListener(() {
      _filterSongs(_searchController.text);
      _triggerOnlineSearch(_searchController.text);
    });

    widget.player.addListener(_onPlayerChanged);

    _filteredSongs = widget.player.songs;
    _paletteSongId = widget.player.currentSong?.id;
    _loadAppPalette(widget.player.currentSong);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _onlineSearchDebounce?.cancel();
    widget.player.removeListener(_onPlayerChanged);
    super.dispose();
  }

  // ==========================================================
  // PLAYER CHANGED
  // ==========================================================

  void _onPlayerChanged() {
    if (!mounted) return;

    final song = widget.player.currentSong;
    if (song?.id != _paletteSongId) {
      _paletteSongId = song?.id;
      _loadAppPalette(song);
    }

    _filterSongs(_searchController.text, rebuild: true);
  }

  Future<void> _loadAppPalette(Song? song) async {
    final request = ++_paletteRequest;

    if (song == null) {
      if (!mounted) return;
      setState(() => _appPalette = ArtworkPalette.neutral);
      return;
    }

    try {
      final artwork = await widget.player.loadArtwork(song);
      final palette = artwork == null
          ? ArtworkPalette.neutral
          : await ArtworkPaletteExtractor.fromBytes(artwork);

      if (!mounted || request != _paletteRequest) return;
      setState(() => _appPalette = palette);
    } catch (_) {
      if (!mounted || request != _paletteRequest) return;
      setState(() => _appPalette = ArtworkPalette.neutral);
    }
  }

  Widget _buildAppBackdrop() {
    final palette = _appPalette;
    final baseColor = palette.isArtworkDerived
        ? Color.lerp(palette.dark, AppColors.background, 0.58)!
        : palette.dark;

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeInOutCubic,
              color: baseColor,
            ),
            if (palette.isArtworkDerived)
              LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned(
                        top: -constraints.maxHeight * 0.24,
                        left: -constraints.maxWidth * 0.14,
                        width: constraints.maxWidth * 1.28,
                        height: constraints.maxHeight * 0.78,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 1100),
                          curve: Curves.easeInOutCubic,
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              colors: [
                                palette.primary.withValues(alpha: 0.18),
                                palette.primary.withValues(alpha: 0.07),
                                palette.primary.withValues(alpha: 0),
                              ],
                              stops: const [0, 0.48, 1],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: -constraints.maxHeight * 0.43,
                        right: -constraints.maxWidth * 0.38,
                        width: constraints.maxWidth * 1.18,
                        height: constraints.maxHeight * 0.86,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 1400),
                          curve: Curves.easeInOutCubic,
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              colors: [
                                palette.secondary.withValues(alpha: 0.08),
                                palette.secondary.withValues(alpha: 0.03),
                                palette.secondary.withValues(alpha: 0),
                              ],
                              stops: const [0, 0.52, 1],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // SEARCH
  // ==========================================================

  void _filterSongs(String value, {bool rebuild = false}) {
    final query = value.trim().toLowerCase();

    Iterable<Song> result = widget.player.songs;

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

    final songs = result.toList();

    if (!mounted) {
      _filteredSongs = songs;
      _searchText = query;
      return;
    }

    setState(() {
      _searchText = query;
      _filteredSongs = songs;
    });
  }

  // ==========================================================
  // ONLINE SEARCH
  // ==========================================================

  void _triggerOnlineSearch(String query) {
    _onlineSearchDebounce?.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _onlineResults = [];
        _onlineQuery = '';
        _isSearchingOnline = false;
      });
      return;
    }

    _onlineSearchDebounce = Timer(const Duration(milliseconds: 800), () {
      _searchOnline(query);
    });
  }

  Future<void> _searchOnline(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _isSearchingOnline = true;
      _onlineResults = [];
      _onlineQuery = query;
    });

    try {
      final results = await YouTubeAudioService.instance.search(query);

      if (!mounted) return;

      setState(() {
        _onlineResults = results;
        _isSearchingOnline = false;
      });
    } catch (e) {
      debugPrint('[SoundNeed] Error buscando YouTube: $e');

      if (!mounted) return;

      setState(() {
        _onlineResults = [];
        _isSearchingOnline = false;
      });
    }
  }

  void _clearOnlineSearch() {
    setState(() {
      _onlineResults = [];
      _onlineQuery = '';
      _isSearchingOnline = false;
    });
  }

  // ==========================================================
  // SEARCH TOGGLE
  // ==========================================================

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
    });

    if (!_isSearching) {
      _searchController.clear();
      FocusScope.of(context).unfocus();
      _clearOnlineSearch();
    }
  }

  // ==========================================================
  // SECTION
  // ==========================================================

  void _selectSection(MusicSection section) {
    setState(() {
      _section = section;
    });
  }

  bool _handleMainScroll(ScrollNotification notification) {
    if (_isSearching || notification.metrics.axis != Axis.vertical) {
      return false;
    }

    // Only follow the section's main vertical list; nested lists and tiny
    // scroll reversals should not make the app bar flicker.
    if (notification.depth != 0) return false;

    if (notification is ScrollStartNotification) {
      _scrollDeltaSinceDirectionChange = 0;
    } else if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      if (delta == 0) return false;

      final changedDirection =
          _scrollDeltaSinceDirectionChange != 0 &&
          delta.sign != _scrollDeltaSinceDirectionChange.sign;
      if (changedDirection) _scrollDeltaSinceDirectionChange = 0;
      _scrollDeltaSinceDirectionChange += delta;

      if (_scrollDeltaSinceDirectionChange >= _appBarScrollThreshold &&
          _appBarVisible) {
        setState(() => _appBarVisible = false);
        _scrollDeltaSinceDirectionChange = 0;
      } else if (_scrollDeltaSinceDirectionChange <= -_appBarScrollThreshold &&
          !_appBarVisible) {
        setState(() => _appBarVisible = true);
        _scrollDeltaSinceDirectionChange = 0;
      }
    } else if (notification is OverscrollNotification &&
        notification.metrics.pixels <= notification.metrics.minScrollExtent &&
        !_appBarVisible) {
      setState(() => _appBarVisible = true);
      _scrollDeltaSinceDirectionChange = 0;
    } else if (notification is ScrollEndNotification) {
      _scrollDeltaSinceDirectionChange = 0;
    }
    return false;
  }

  // ==========================================================
  // SETTINGS
  // ==========================================================

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ajustes',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                const ListTile(
                  leading: Icon(
                    Icons.music_note_outlined,
                    color: Colors.white70,
                  ),
                  title: Text('SoundNeed'),
                  subtitle: Text('Configuración del reproductor'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _appPalette.dark,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildAppBackdrop(),
          SafeArea(
            top: true,
            bottom: false,
            child: Column(
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _appBarVisible
                      ? AppBar(
                          title: _isSearching
                              ? SoundNeedSearchField(
                                  controller: _searchController,
                                  autofocus: true,
                                  hintText: 'Canción, artista o álbum',
                                  height: 46,
                                )
                              : const Text(
                                  'SoundNeed',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                          actions: [
                            // ==================================================
                            // BUSCAR
                            // ==================================================

                            IconButton(
                              tooltip: 'Buscar',
                              onPressed: _toggleSearch,
                              icon: Icon(
                                _isSearching ? Icons.close : Icons.search,
                                color: Colors.white,
                              ),
                            ),

                            // ==================================================
                            // COLA
                            // ==================================================
                            IconButton(
                              tooltip: 'Cola',
                              onPressed: _showQueue,
                              icon: const Icon(
                                Icons.queue_music_outlined,
                                color: Colors.white,
                              ),
                            ),

                            // ==================================================
                            // AJUSTES
                            // ==================================================
                            IconButton(
                              tooltip: 'Ajustes',
                              onPressed: _showSettings,
                              icon: const Icon(
                                Icons.settings_outlined,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),

                // ======================================================
                // BODY
                // ======================================================
                Expanded(
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        height: _appBarVisible ? 0 : 2,
                      ),
                      // Navegación fija y completa.
                      _buildFloatingSections(),

                      // Contenido
                      Expanded(
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _handleMainScroll,
                          child: _buildCurrentSection(),
                        ),
                      ),

                      // Keep the mini player above Android's gesture area so
                      // it never appears to float over the system navigation.
                      if (widget.player.currentSong != null)
                        SafeArea(
                          top: false,
                          minimum: const EdgeInsets.only(bottom: 4),
                          child: MiniPlayer(player: widget.player),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // NAVEGACIÓN PRINCIPAL
  // ==========================================================

  Widget _buildFloatingSections() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SizedBox(
        height: 54,
        child: ListView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildSectionBubble(
                MusicSection.home,
                Icons.home_outlined,
                'Inicio',
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildSectionBubble(
                MusicSection.songs,
                Icons.music_note_outlined,
                'Canciones',
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildSectionBubble(
                MusicSection.playlists,
                Icons.playlist_play_rounded,
                'Playlists',
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildSectionBubble(
                MusicSection.folders,
                Icons.folder_outlined,
                'Carpetas',
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildSectionBubble(
                MusicSection.artists,
                Icons.person_outline,
                'Artistas',
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildSectionBubble(
                MusicSection.albums,
                Icons.album_outlined,
                'Álbumes',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // BURBUJA DE NAVEGACIÓN
  // ==========================================================

  Widget _buildSectionBubble(
    MusicSection section,
    IconData icon,
    String label,
  ) {
    final selected = _section == section;

    return GestureDetector(
      onTap: () => _selectSection(section),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          // Nada de morado.
          color: selected ? Colors.white : AppColors.surface,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: selected ? 0.28 : 0.18),
              blurRadius: selected ? 10 : 8,
              offset: Offset(0, selected ? 4 : 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 17,
              color: selected ? Colors.black : Colors.white70,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.black : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // SECCIÓN ACTUAL
  // ==========================================================

  Widget _buildCurrentSection() {
    switch (_section) {
      case MusicSection.home:
        return HomeSection(
          player: widget.player,
          onlineResults: _onlineResults,
          onlineQuery: _onlineQuery,
          isSearchingOnline: _isSearchingOnline,
          clearOnlineSearch: _clearOnlineSearch,
          localSearchResults: _searchText.isNotEmpty ? _filteredSongs : null,
        );

      case MusicSection.songs:
        return SongsSection(
          player: widget.player,
          filteredSongs: _filteredSongs,
          searchText: _searchText,
        );

      case MusicSection.playlists:
        return PlaylistsSection(player: widget.player);

      case MusicSection.folders:
        return FoldersSection(player: widget.player);

      case MusicSection.artists:
        return ArtistsSection(
          player: widget.player,
          songs: _filteredSongs,
          searchText: _searchText,
        );

      case MusicSection.albums:
        return AlbumsSection(
          player: widget.player,
          songs: _filteredSongs,
          searchText: _searchText,
        );
    }
  }

  // ==========================================================
  // ARTWORK (para el queue)
  // ==========================================================

  Widget _buildArtwork(Song song, {double size = 52}) {
    return FutureBuilder<Uint8List?>(
      future: widget.player.loadArtwork(song),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(13),
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
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: const Icon(Icons.music_note, size: 24, color: Colors.white54),
        );
      },
    );
  }

  // ==========================================================
  // QUEUE
  // ==========================================================

  void _showQueue() {
    final pageContext = context;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      showDragHandle: true,
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
                      Icon(Icons.queue_music_outlined, color: Colors.white70),
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
                  child: widget.player.queue.isEmpty
                      ? const Center(
                          child: Text(
                            'La cola está vacía.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          itemCount: widget.player.queue.length,
                          itemBuilder: (context, index) {
                            final song = widget.player.queue[index];

                            final isCurrent =
                                widget.player.currentSong?.id == song.id;

                            return ListTile(
                              leading: _buildArtwork(song, size: 52),
                              title: Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
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
                                      color: Colors.white,
                                    )
                                  : null,
                              onTap: () async {
                                Navigator.pop(context);

                                widget.player.setQueueIndex(index);
                                await selectSongOrOpenPlayer(
                                  pageContext,
                                  widget.player,
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
}

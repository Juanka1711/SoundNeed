import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'music_player.dart';
import 'full_player.dart';
import 'mini_player.dart';
import 'app_colors.dart';
import 'sections/home_section.dart';
import 'sections/songs_section.dart';
import 'sections/playlists_section.dart';
import 'sections/folders_section.dart';
import 'sections/artists_section.dart';
import 'sections/albums_section.dart';

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

enum MusicSection {
  home,
  songs,
  playlists,
  folders,
  artists,
  albums,
}

// ============================================================
// HOME
// ============================================================

class MusicHomePage extends StatefulWidget {
  final MusicPlayerController player;

  const MusicHomePage({
    super.key,
    required this.player,
  });

  @override
  State<MusicHomePage> createState() => _MusicHomePageState();
}

class _MusicHomePageState extends State<MusicHomePage> {
  final TextEditingController _searchController =
      TextEditingController();

  List<Song> _filteredSongs = [];

  bool _isSearching = false;
  String _searchText = '';

  MusicSection _section = MusicSection.home;

  bool _isAppBarVisible = true;
  double _lastScrollPosition = 0;
  static const double _scrollThreshold = 5.0;

  @override
  void initState() {
    super.initState();

    _searchController.addListener(() {
      _filterSongs(_searchController.text);
    });

    widget.player.addListener(_onPlayerChanged);

    _filteredSongs = widget.player.songs;
  }

  @override
  void dispose() {
    _searchController.dispose();
    widget.player.removeListener(_onPlayerChanged);
    super.dispose();
  }

  // ==========================================================
  // PLAYER CHANGED
  // ==========================================================

  void _onPlayerChanged() {
    if (!mounted) return;

    _filterSongs(
      _searchController.text,
      rebuild: true,
    );
  }

  // ==========================================================
  // SEARCH
  // ==========================================================

  void _filterSongs(
    String value, {
    bool rebuild = false,
  }) {
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
  // SEARCH TOGGLE
  // ==========================================================

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
    });

    if (!_isSearching) {
      _searchController.clear();
      FocusScope.of(context).unfocus();
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

  // ==========================================================
  // SCROLL HANDLER
  // ==========================================================

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final currentScroll = notification.metrics.pixels;
      final scrollDelta = currentScroll - _lastScrollPosition;

      // Si el scroll aumenta (hacia abajo) y supera el umbral, ocultar el AppBar
      if (scrollDelta > _scrollThreshold && _isAppBarVisible) {
        setState(() {
          _isAppBarVisible = false;
        });
      }
      // Si el scroll disminuye (hacia arriba) y supera el umbral, mostrar el AppBar
      else if (scrollDelta < -_scrollThreshold && !_isAppBarVisible) {
        setState(() {
          _isAppBarVisible = true;
        });
      }

      _lastScrollPosition = currentScroll;
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
            padding: const EdgeInsets.fromLTRB(
              20,
              8,
              20,
              30,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ajustes',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                const ListTile(
                  leading: Icon(
                    Icons.music_note_outlined,
                    color: Colors.white70,
                  ),
                  title: Text('SoundNeed'),
                  subtitle: Text(
                    'Configuración del reproductor',
                  ),
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
      body: Column(
        children: [
          // AppBar animado
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _isAppBarVisible
                ? AppBar(
                    title: _isSearching
                        ? TextField(
                            controller: _searchController,
                            autofocus: true,
                            style: const TextStyle(
                              color: Colors.white,
                            ),
                            decoration: const InputDecoration(
                              hintText:
                                  'Buscar canción, artista o álbum...',
                              border: InputBorder.none,
                            ),
                          )
                        : const Text(
                            'SoundNeed',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                    actions: [
                      // ==================================================
                      // BUSCAR
                      // ==================================================

                      IconButton(
                        tooltip: 'Buscar',
                        onPressed: _toggleSearch,
                        icon: Icon(
                          _isSearching
                              ? Icons.close
                              : Icons.search,
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
          // Espacio cuando está oculto
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            height: _isAppBarVisible ? 0 : 30,
          ),

          // ======================================================
          // BODY
          // ======================================================

          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: Column(
                children: [
                  // Paneles flotantes
                  _buildFloatingSections(),

                  // Contenido
                  Expanded(
                    child: _buildCurrentSection(),
                  ),

                  // Mini player
                  if (widget.player.currentSong != null)
                    MiniPlayer(
                      player: widget.player,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // PANELES FLOTANTES
  // ==========================================================

  Widget _buildFloatingSections() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        12,
        8,
        12,
        8,
      ),
      child: SizedBox(
        height: 54,
        child: ListView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          children: [
            _buildFloatingSection(
              MusicSection.home,
              Icons.home_outlined,
              'Inicio',
            ),
            _buildFloatingSection(
              MusicSection.songs,
              Icons.music_note_outlined,
              'Canciones',
            ),
            _buildFloatingSection(
              MusicSection.playlists,
              Icons.queue_music_outlined,
              'Playlists',
            ),
            _buildFloatingSection(
              MusicSection.folders,
              Icons.folder_outlined,
              'Carpetas',
            ),
            _buildFloatingSection(
              MusicSection.artists,
              Icons.person_outline,
              'Artistas',
            ),
            _buildFloatingSection(
              MusicSection.albums,
              Icons.album_outlined,
              'Álbumes',
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // PANEL FLOTANTE INDIVIDUAL
  // ==========================================================

  Widget _buildFloatingSection(
    MusicSection section,
    IconData icon,
    String label,
  ) {
    final selected = _section == section;

    return Padding(
      padding: const EdgeInsets.only(
        right: 8,
      ),
      child: GestureDetector(
        onTap: () => _selectSection(section),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(
            milliseconds: 180,
          ),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            // Nada de morado.
            color: selected
                ? Colors.white
                : AppColors.surface,
            borderRadius:
                BorderRadius.circular(30),
            border: Border.all(
              color: selected
                  ? Colors.white
                  : Colors.white.withOpacity(0.08),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color:
                          Colors.black.withOpacity(0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 19,
                color: selected
                    ? Colors.black
                    : Colors.white70,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: selected
                      ? Colors.black
                      : Colors.white70,
                ),
              ),
            ],
          ),
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
        );

      case MusicSection.songs:
        return SongsSection(
          player: widget.player,
          filteredSongs: _filteredSongs,
          searchText: _searchText,
        );

      case MusicSection.playlists:
        return const PlaylistsSection();

      case MusicSection.folders:
        return const FoldersSection();

      case MusicSection.artists:
        return const ArtistsSection();

      case MusicSection.albums:
        return const AlbumsSection();
    }
  }

  // ==========================================================
  // ARTWORK (para el queue)
  // ==========================================================

  Widget _buildArtwork(
    Song song, {
    double size = 52,
  }) {
    return FutureBuilder<Uint8List?>(
      future: widget.player.loadArtwork(song),
      builder: (context, snapshot) {
        if (snapshot.hasData &&
            snapshot.data != null) {
          return ClipRRect(
            borderRadius:
                BorderRadius.circular(13),
            child: Image.memory(
              snapshot.data!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          );
        }

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius:
                BorderRadius.circular(13),
            border: Border.all(
              color:
                  Colors.white.withOpacity(0.10),
            ),
          ),
          child: const Icon(
            Icons.music_note,
            size: 24,
            color: Colors.white54,
          ),
        );
      },
    );
  }

  // ==========================================================
  // QUEUE
  // ==========================================================

  void _showQueue() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height:
                MediaQuery.of(context)
                        .size
                        .height *
                    0.70,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Icon(
                        Icons.queue_music_outlined,
                        color: Colors.white70,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Cola de reproducción',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight:
                              FontWeight.bold,
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
                            style: TextStyle(
                              color:
                                  AppColors
                                      .textSecondary,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount:
                              widget.player
                                  .queue.length,
                          itemBuilder:
                              (context, index) {
                            final song =
                                widget.player
                                    .queue[index];

                            final isCurrent =
                                widget.player
                                        .currentSong
                                        ?.id ==
                                    song.id;

                            return ListTile(
                              leading:
                                  _buildArtwork(
                                song,
                                size: 52,
                              ),
                              title: Text(
                                song.title,
                                maxLines: 1,
                                overflow:
                                    TextOverflow
                                        .ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight:
                                      isCurrent
                                          ? FontWeight
                                              .bold
                                          : FontWeight
                                              .normal,
                                ),
                              ),
                              subtitle: Text(
                                song.artist,
                                maxLines: 1,
                                overflow:
                                    TextOverflow
                                        .ellipsis,
                              ),
                              trailing: isCurrent
                                  ? const Icon(
                                      Icons
                                          .equalizer,
                                      color:
                                          Colors.white,
                                    )
                                  : null,
                              onTap: () async {
                                Navigator.pop(
                                  context,
                                );

                                widget.player
                                    .setQueueIndex(
                                  index,
                                );

                                await widget.player
                                    .playSong(
                                  song,
                                  createQueue:
                                      false,
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
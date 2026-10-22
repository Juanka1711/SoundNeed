import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
import 'widgets/local_music_badge.dart';
import 'notifications/notification_center_page.dart';
import 'services/notification_service.dart';

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
  final NotificationService _notificationService = NotificationService.instance;
  StreamSubscription<NotificationNavigationRequest>?
  _notificationNavigationSubscription;

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
  int _onlineSearchRequestId = 0;

  MusicSection _section = MusicSection.home;
  int? _notificationFocusSongId;
  Timer? _notificationFocusTimer;
  bool _showNotificationDownloads = false;
  String? _notificationDownloadsFolderPath;

  @override
  void initState() {
    super.initState();

    _searchController.addListener(() {
      _filterSongs(_searchController.text);
      _triggerOnlineSearch(_searchController.text);
    });

    widget.player.addListener(_onPlayerChanged);
    _notificationService.addListener(_onNotificationsChanged);
    _notificationNavigationSubscription = _notificationService
        .navigationRequests
        .listen((request) => unawaited(_openNotificationDestination(request)));
    unawaited(
      _notificationService.initialize().then((_) {
        if (!mounted) return;
        final pending = _notificationService.takePendingNavigation();
        if (pending != null) unawaited(_openNotificationDestination(pending));
      }),
    );

    _filteredSongs = widget.player.songs;
    _paletteSongId = widget.player.currentSong?.id;
    _loadAppPalette(widget.player.currentSong);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _onlineSearchDebounce?.cancel();
    _notificationFocusTimer?.cancel();
    widget.player.removeListener(_onPlayerChanged);
    _notificationService.removeListener(_onNotificationsChanged);
    _notificationNavigationSubscription?.cancel();
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

  void _onNotificationsChanged() {
    if (mounted) setState(() {});
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
    _onlineSearchRequestId++;
    _onlineSearchDebounce?.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _onlineResults = [];
        _onlineQuery = '';
        _isSearchingOnline = false;
      });
      return;
    }

    setState(() {
      _onlineResults = [];
      _onlineQuery = query;
      _isSearchingOnline = true;
    });

    _onlineSearchDebounce = Timer(const Duration(milliseconds: 800), () {
      _searchOnline(query);
    });
  }

  Future<void> _searchOnline(String query) async {
    if (query.trim().isEmpty) return;
    final requestId = ++_onlineSearchRequestId;

    setState(() {
      _isSearchingOnline = true;
      _onlineResults = [];
      _onlineQuery = query;
    });

    try {
      final results = await YouTubeAudioService.instance.search(query);

      if (!mounted || requestId != _onlineSearchRequestId) return;

      setState(() {
        _onlineResults = results;
        _isSearchingOnline = false;
      });
    } catch (e) {
      debugPrint('[SoundNeed] Error buscando YouTube: $e');

      if (!mounted || requestId != _onlineSearchRequestId) return;

      setState(() {
        _onlineResults = [];
        _isSearchingOnline = false;
      });
    }
  }

  void _clearOnlineSearch() {
    _onlineSearchRequestId++;
    _onlineSearchDebounce?.cancel();
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
    _notificationFocusTimer?.cancel();
    setState(() {
      _section = section;
      _showNotificationDownloads = false;
      _notificationDownloadsFolderPath = null;
      _notificationFocusSongId = null;
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SoundNeedSettingsPage(player: widget.player, palette: _appPalette),
      ),
    );
  }

  void _showNotificationCenter() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationCenterPage(
          service: _notificationService,
          player: widget.player,
          palette: _appPalette,
          onOpenDestination: (record) {
            Navigator.of(context).pop();
            unawaited(_openNotificationRecord(record));
          },
        ),
      ),
    );
  }

  Future<void> _openNotificationDestination(
    NotificationNavigationRequest request,
  ) async {
    final record = request.notificationId == null
        ? null
        : _notificationService.findByNotificationId(request.notificationId!);
    if (record != null) await _notificationService.markRead(record.id);
    await _openNotificationRecord(
      record,
      fallbackDestination: request.destination,
    );
  }

  Future<void> _openNotificationRecord(
    SoundNeedNotification? record, {
    String? fallbackDestination,
  }) async {
    final destination = record?.destination ?? fallbackDestination;
    if (!mounted ||
        destination == null ||
        !NotificationService.isValidDestination(destination)) {
      return;
    }

    if (record?.eventType == 'song_download_completed') {
      await _openDownloadedSongNotification(record!);
      return;
    }

    if (record?.eventType == 'new_music_detected') {
      setState(() => _section = MusicSection.home);
      final count = record?.metadata['count'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            count is num && count == 1
                ? 'Hay música nueva para descubrir en Inicio.'
                : 'Las novedades musicales están en Inicio.',
          ),
        ),
      );
      return;
    }

    switch (destination) {
      case 'songs':
        setState(() {
          _section = MusicSection.songs;
          _notificationFocusSongId = null;
          _showNotificationDownloads = false;
          _notificationDownloadsFolderPath = null;
        });
        return;
      case 'playlists':
        setState(() => _section = MusicSection.playlists);
        return;
      case 'home':
        setState(() => _section = MusicSection.home);
        return;
      case 'settings':
        _showSettings();
        return;
      case 'notifications':
        _showNotificationCenter();
        return;
    }
  }

  Future<void> _openDownloadedSongNotification(
    SoundNeedNotification record,
  ) async {
    final metadata = record.metadata;
    final targetId = int.tryParse(
      '${metadata['downloadedSongId'] ?? metadata['songId'] ?? ''}',
    );
    final targetUri = '${metadata['downloadedSongUri'] ?? ''}'.trim();
    final folderPath = '${metadata['folderPath'] ?? ''}'.trim();
    final title =
        '${metadata['songTitle'] ?? record.description.replaceFirst(RegExp(r'\s+se guardó en el dispositivo\.?$'), '')}'
            .trim();
    final artist = '${metadata['songArtist'] ?? ''}'.trim();

    _clearOnlineSearch();
    _searchController.clear();
    await widget.player.loadSongs();
    if (!mounted) return;

    Song? song;
    if (targetUri.isNotEmpty) {
      for (final candidate in widget.player.songs) {
        if (candidate.uri == targetUri) {
          song = candidate;
          break;
        }
      }
    }
    if (targetId != null) {
      if (song == null) {
        for (final candidate in widget.player.songs) {
          if (candidate.id == targetId) {
            song = candidate;
            break;
          }
        }
      }
    }
    if (song == null && title.isNotEmpty) {
      final normalizedTitle = _normalizeNotificationText(title);
      final normalizedArtist = _normalizeNotificationText(artist);
      final candidates = widget.player.songs.where((candidate) {
        final candidateTitle = _normalizeNotificationText(
          candidate.title.isEmpty ? candidate.displayName : candidate.title,
        );
        return candidateTitle == normalizedTitle;
      }).toList();
      if (candidates.isNotEmpty) {
        song = candidates.firstWhere(
          (candidate) =>
              normalizedArtist.isNotEmpty &&
              _normalizeNotificationText(candidate.artist) == normalizedArtist,
          orElse: () => candidates.first,
        );
      }
    }

    setState(() {
      _section = MusicSection.songs;
      _notificationFocusSongId = song?.id;
      _showNotificationDownloads = true;
      _notificationDownloadsFolderPath = folderPath.isNotEmpty
          ? folderPath
          : song?.folderPath;
    });
    _notificationFocusTimer?.cancel();
    if (song != null) {
      final highlightedSongId = song.id;
      _notificationFocusTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted || _notificationFocusSongId != highlightedSongId) return;
        setState(() => _notificationFocusSongId = null);
      });
    }
    if (song == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Abriendo tus descargas. Actualiza la lista si hace falta.',
          ),
        ),
      );
    }
  }

  String _normalizeNotificationText(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]*\)|\[[^]]*\]'), '')
      .replaceAll(RegExp(r'[^a-z0-9áéíóúüñ]'), '');

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
                          leadingWidth: 48,
                          titleSpacing: 16,
                          leading: null,
                          title: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              final slide = Tween<Offset>(
                                begin: const Offset(0.12, 0),
                                end: Offset.zero,
                              ).animate(animation);
                              return ClipRect(
                                child: FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: slide,
                                    child: child,
                                  ),
                                ),
                              );
                            },
                            child: _isSearching
                                ? SoundNeedSearchField(
                                    key: const ValueKey('appbar-search'),
                                    controller: _searchController,
                                    autofocus: true,
                                    hintText: 'Canción, artista o álbum',
                                    height: 46,
                                    accent: _appPalette.primary,
                                    surfaceColor: Color.lerp(
                                      _appPalette.dark,
                                      _appPalette.primary,
                                      _appPalette.isArtworkDerived ? 0.16 : 0,
                                    )!,
                                    suffix: IconButton(
                                      tooltip: 'Cerrar búsqueda',
                                      onPressed: _toggleSearch,
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints:
                                          const BoxConstraints.tightFor(
                                            width: 32,
                                            height: 32,
                                          ),
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  )
                                : Row(
                                    key: const ValueKey('appbar-brand'),
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Image.asset(
                                        'assets/icon/app_icon_source.png',
                                        width: 32,
                                        height: 32,
                                        fit: BoxFit.contain,
                                      ),
                                      const SizedBox(width: 4),
                                      Image.asset(
                                        'assets/icon/titulo.png',
                                        height: 32,
                                        fit: BoxFit.contain,
                                      ),
                                    ],
                                  ),
                          ),
                          actions: [
                            // ==================================================
                            // BUSCAR
                            // ==================================================

                            if (!_isSearching)
                              IconButton(
                                tooltip: 'Buscar',
                                onPressed: _toggleSearch,
                                icon: const Icon(
                                  Icons.search,
                                  color: Colors.white,
                                ),
                              ),

                            // ==================================================
                            // COLA
                            // ==================================================
                            if (!_isSearching)
                              IconButton(
                                tooltip: 'Cola',
                                onPressed: _showQueue,
                                icon: const Icon(
                                  Icons.queue_music_outlined,
                                  color: Colors.white,
                                ),
                              ),

                            if (!_isSearching)
                              IconButton(
                                tooltip: _notificationService.unreadCount == 0
                                    ? 'Notificaciones'
                                    : 'Notificaciones: ${_notificationService.unreadCount} sin leer',
                                onPressed: _showNotificationCenter,
                                icon: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    const Icon(
                                      Icons.notifications_outlined,
                                      color: Colors.white,
                                    ),
                                    if (_notificationService.unreadCount > 0)
                                      Positioned(
                                        right: -4,
                                        top: -3,
                                        child: Container(
                                          width: 16,
                                          height: 16,
                                          decoration: const BoxDecoration(
                                            color: Color(0xfff43f5e),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Text(
                                              _notificationService.unreadCount >
                                                      9
                                                  ? '9+'
                                                  : '${_notificationService.unreadCount}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 8,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                            // ==================================================
                            // AJUSTES
                            // ==================================================
                            if (!_isSearching)
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
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            reverseDuration: const Duration(milliseconds: 180),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              final slide = Tween<Offset>(
                                begin: const Offset(0.025, 0),
                                end: Offset.zero,
                              ).animate(animation);
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: slide,
                                  child: child,
                                ),
                              );
                            },
                            child: KeyedSubtree(
                              key: ValueKey<MusicSection>(_section),
                              child: _buildCurrentSection(),
                            ),
                          ),
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
          palette: _appPalette,
          onlineResults: _onlineResults,
          onlineQuery: _onlineQuery,
          isSearchingOnline: _isSearchingOnline,
          clearOnlineSearch: _clearOnlineSearch,
          localSearchResults: _searchText.isNotEmpty ? _filteredSongs : null,
        );

      case MusicSection.songs:
        return SongsSection(
          key: ValueKey<Object?>(
            'songs-${_showNotificationDownloads ? 'downloads' : 'all'}',
          ),
          player: widget.player,
          filteredSongs: _filteredSongs,
          searchText: _searchText,
          palette: _appPalette,
          focusedSongId: _notificationFocusSongId,
          showDownloadsOnly: _showNotificationDownloads,
          downloadsFolderPath: _notificationDownloadsFolderPath,
        );

      case MusicSection.playlists:
        return PlaylistsSection(player: widget.player, palette: _appPalette);

      case MusicSection.folders:
        return FoldersSection(player: widget.player, palette: _appPalette);

      case MusicSection.artists:
        return ArtistsSection(
          player: widget.player,
          songs: _filteredSongs,
          searchText: _searchText,
          palette: _appPalette,
        );

      case MusicSection.albums:
        return AlbumsSection(
          player: widget.player,
          songs: _filteredSongs,
          searchText: _searchText,
          palette: _appPalette,
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
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (isLocalMusic(song)) ...[
                                    const SizedBox(height: 3),
                                    const LocalMusicBadge(),
                                  ],
                                ],
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

class SoundNeedSettingsPage extends StatefulWidget {
  const SoundNeedSettingsPage({
    super.key,
    required this.player,
    required this.palette,
  });

  final MusicPlayerController player;
  final ArtworkPalette palette;

  @override
  State<SoundNeedSettingsPage> createState() => _SoundNeedSettingsPageState();
}

class _SoundNeedSettingsPageState extends State<SoundNeedSettingsPage>
    with WidgetsBindingObserver {
  static const MethodChannel _settingsChannel = MethodChannel(
    'music_player/media',
  );

  String _version = 'Cargando…';
  bool _notificationsEnabled = true;
  bool _generalSystemNotificationsEnabled = false;
  late ArtworkPalette _settingsPalette;
  int? _paletteSongId;
  int _paletteRequest = 0;
  Timer? _sleepTimerUi;
  final NotificationService _notificationService = NotificationService.instance;

  @override
  void initState() {
    super.initState();
    _settingsPalette = widget.palette;
    _paletteSongId = widget.player.currentSong?.id;
    WidgetsBinding.instance.addObserver(this);
    widget.player.addListener(_onPlayerChanged);
    _notificationService.addListener(_onNotificationSettingsChanged);
    unawaited(_loadSettingsPalette(widget.player.currentSong));
    _loadSettingsInfo();
    unawaited(
      _notificationService.initialize().then(
        (_) => _loadGeneralNotificationStatus(),
      ),
    );
    _sleepTimerUi = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.player.sleepTimerDeadline != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.player.removeListener(_onPlayerChanged);
    _notificationService.removeListener(_onNotificationSettingsChanged);
    _sleepTimerUi?.cancel();
    super.dispose();
  }

  void _onPlayerChanged() {
    final song = widget.player.currentSong;
    if (song?.id != _paletteSongId) {
      _paletteSongId = song?.id;
      unawaited(_loadSettingsPalette(song));
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadSettingsPalette(Song? song) async {
    final request = ++_paletteRequest;
    if (song == null) {
      if (mounted) setState(() => _settingsPalette = ArtworkPalette.neutral);
      return;
    }
    try {
      final artwork = await widget.player.loadArtwork(song);
      final palette = artwork == null
          ? ArtworkPalette.neutral
          : await ArtworkPaletteExtractor.fromBytes(artwork);
      if (!mounted || request != _paletteRequest) return;
      setState(() => _settingsPalette = palette);
    } catch (_) {
      if (!mounted || request != _paletteRequest) return;
      setState(() => _settingsPalette = ArtworkPalette.neutral);
    }
  }

  Color _settingsAccent(int index) {
    return _settingsPalette.primary;
  }

  void _onNotificationSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadNotificationStatus();
      _loadGeneralNotificationStatus();
    }
  }

  Future<void> _loadSettingsInfo() async {
    try {
      final version = await _settingsChannel.invokeMethod<String>(
        'getAppVersion',
      );
      if (mounted && version != null && version.isNotEmpty) {
        setState(() => _version = version);
      }
    } on PlatformException {
      if (mounted) setState(() => _version = 'No disponible');
    }
    await _loadNotificationStatus();
    await _loadGeneralNotificationStatus();
  }

  Future<void> _loadNotificationStatus() async {
    try {
      final enabled = await _settingsChannel.invokeMethod<bool>(
        'areNotificationsEnabled',
      );
      if (mounted && enabled != null) {
        setState(() => _notificationsEnabled = enabled);
      }
    } on PlatformException {
      // La pantalla de administración del sistema seguirá disponible.
    }
  }

  Future<void> _loadGeneralNotificationStatus() async {
    final enabled = await _notificationService.areSystemNotificationsEnabled();
    if (mounted) setState(() => _generalSystemNotificationsEnabled = enabled);
  }

  Future<void> _manageGeneralNotificationPermission() async {
    await _notificationService.requestSystemPermission();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await _loadGeneralNotificationStatus();
  }

  Future<void> _openNotificationSettings() async {
    try {
      await _settingsChannel.invokeMethod<void>('openNotificationSettings');
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudieron abrir los ajustes del sistema.'),
        ),
      );
    }
  }

  Future<void> _shareFeedback() async {
    try {
      await _settingsChannel.invokeMethod<void>(
        'shareFeedback',
        <String, Object>{'version': _version},
      );
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el menú para enviar comentarios.'),
        ),
      );
    }
  }

  Future<void> _showSleepTimerOptions() async {
    final remaining = widget.player.sleepTimerRemaining;
    final choices = <(String, Duration?)>[
      ('15 minutos', const Duration(minutes: 15)),
      ('30 minutos', const Duration(minutes: 30)),
      ('45 minutos', const Duration(minutes: 45)),
      ('1 hora', const Duration(hours: 1)),
      ('2 horas', const Duration(hours: 2)),
      if (remaining != null) ('Cancelar temporizador', null),
    ];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Color.lerp(
        AppColors.surface,
        _settingsPalette.dark,
        .38,
      ),
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        side: BorderSide(
          color: _settingsPalette.primary.withValues(alpha: .26),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(8, 8, 8, 12),
                child: Text(
                  'Temporizador para dormir',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _settingsPalette.primary,
                  ),
                ),
              ),
              for (final choice in choices)
                ListTile(
                  leading: Icon(
                    choice.$2 == null
                        ? Icons.timer_off_outlined
                        : Icons.bedtime_outlined,
                    color: _settingsAccent(choices.indexOf(choice)),
                  ),
                  title: Text(choice.$1),
                  onTap: () async {
                    await widget.player.setSleepTimer(choice.$2);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatRemaining(Duration? duration) {
    if (duration == null)
      return 'La música se detendrá al terminar el tiempo elegido';
    final seconds = duration.inSeconds;
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return 'Se detiene en ${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color.lerp(
          AppColors.surface,
          _settingsPalette.dark,
          .38,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: _settingsPalette.primary.withValues(alpha: .22),
          ),
        ),
        title: const Text('Ayuda de SoundNeed'),
        content: const Text(
          'Los controles de reproducción aparecen en las notificaciones mientras '
          'escuchas música. Si no los ves, revisa que SoundNeed tenga permiso para '
          'mostrar notificaciones en los ajustes de Android.\n\n'
          'El temporizador pausa la música al cumplirse el tiempo elegido. La '
          'reproducción automática continúa con canciones recomendadas cuando se '
          'acaba la cola, y puedes guardar el punto donde dejaste una canción.\n\n'
          '¿Encontraste un problema o tienes una idea? Envíanos tus comentarios '
          'desde esta pantalla.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: _settingsPalette.primary,
            ),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String title, {Color? accent}) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
    child: Text(
      title.toUpperCase(),
      style: TextStyle(
        color: accent ?? AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.15,
      ),
    ),
  );

  Widget _settingsCard({required List<Widget> children, Color? accent}) =>
      AnimatedContainer(
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color:
                accent?.withValues(alpha: .22) ??
                Colors.white.withValues(alpha: .055),
          ),
          boxShadow: accent == null
              ? null
              : [
                  BoxShadow(
                    color: accent.withValues(alpha: .08),
                    blurRadius: 20,
                    spreadRadius: -8,
                  ),
                ],
        ),
        child: Column(children: children),
      );

  Widget _subscriptionPlanCard() {
    final accent = _settingsPalette.primary;
    final surface = Color.lerp(AppColors.card, _settingsPalette.dark, .22)!;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: accent.withValues(alpha: .30)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: .12),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(surface, accent, .25)!,
                      surface,
                      Color.lerp(surface, accent, .08)!,
                    ],
                    stops: const [0, .48, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -62,
              right: -48,
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: .10),
                ),
              ),
            ),
            Positioned(
              top: 18,
              right: 14,
              child: Icon(
                Icons.graphic_eq_rounded,
                size: 118,
                color: Colors.white.withValues(alpha: .045),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accent.withValues(alpha: .34),
                              accent.withValues(alpha: .12),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: accent.withValues(alpha: .34),
                          ),
                        ),
                        child: Icon(Icons.graphic_eq_rounded, color: accent),
                      ),
                      const SizedBox(width: 13),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SOUNDNEED',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.8,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Premium',
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .13),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: accent.withValues(alpha: .30),
                          ),
                        ),
                        child: Text(
                          'PRÓXIMAMENTE',
                          style: TextStyle(
                            color: accent,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .65,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 19),
                  Text(
                    'Tu música,\na tu manera.',
                    style: TextStyle(
                      fontSize: 27,
                      height: 1.06,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.75,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: .22),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'Estamos preparando una nueva forma de disfrutar SoundNeed.',
                    style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: .94),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(19),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .08),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '\$6.900',
                          style: TextStyle(
                            color: accent,
                            fontSize: 31,
                            height: .98,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 2),
                          child: Text(
                            'COP / mes',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.calendar_month_rounded,
                          size: 17,
                          color: accent.withValues(alpha: .9),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'Plan mensual',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 13),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.notifications_active_outlined,
                          size: 18,
                          color: accent,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Pronto anunciaremos qué incluye el plan.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .88),
                              fontSize: 12,
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
          ],
        ),
      ),
    );
  }

  Widget _divider() => const Divider(
    height: 1,
    indent: 64,
    endIndent: 16,
    color: Colors.white10,
  );

  String _notificationCategoryDescription(NotificationCategory category) =>
      switch (category) {
        NotificationCategory.downloads => 'Finalización y errores de descargas',
        NotificationCategory.imports =>
          'Playlists compartidas importadas o con errores',
        NotificationCategory.errors =>
          'Problemas importantes que requieren atención',
        NotificationCategory.library => 'Cambios importantes de la biblioteca',
        NotificationCategory.news => 'Novedades publicadas por SoundNeed',
        NotificationCategory.maintenance =>
          'Procesos de mantenimiento de la biblioteca',
      };

  @override
  Widget build(BuildContext context) {
    final statusText = _notificationsEnabled
        ? 'Permitir controles desde la notificación de Android'
        : 'Las notificaciones están desactivadas en Android';
    final settingsTheme = Theme.of(context).copyWith(
      colorScheme: Theme.of(context).colorScheme.copyWith(
        primary: _settingsPalette.primary,
        secondary: _settingsPalette.primary,
      ),
    );

    return Theme(
      data: settingsTheme,
      child: Scaffold(
        backgroundColor: _settingsPalette.isArtworkDerived
            ? Color.lerp(_settingsPalette.dark, AppColors.background, .58)
            : AppColors.background,
        appBar: AppBar(
          backgroundColor: _settingsPalette.isArtworkDerived
              ? Color.lerp(_settingsPalette.dark, AppColors.background, .58)
              : AppColors.background,
          foregroundColor: _settingsPalette.primary,
          title: const Text(
            'Ajustes',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: AnimatedContainer(
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOutCubic,
          color: _settingsPalette.isArtworkDerived
              ? Color.lerp(_settingsPalette.dark, AppColors.background, .58)
              : AppColors.background,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeInOutCubic,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    colors: [
                      _settingsPalette.primary.withValues(alpha: .28),
                      _settingsPalette.primary.withValues(alpha: .08),
                      AppColors.card,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: _settingsPalette.primary.withValues(alpha: .30),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 25,
                      backgroundColor: _settingsPalette.primary.withValues(
                        alpha: .20,
                      ),
                      child: Icon(
                        Icons.tune_rounded,
                        color: _settingsPalette.primary,
                      ),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tu SoundNeed',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Personaliza tu experiencia',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _subscriptionPlanCard(),
              _sectionLabel('Notificaciones', accent: _settingsAccent(1)),
              _settingsCard(
                accent: _settingsAccent(0),
                children: [
                  ListTile(
                    leading: _SettingsIcon(
                      icon: Icons.graphic_eq_rounded,
                      color: _settingsAccent(0),
                    ),
                    title: const Text(
                      'Controles de reproducción',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      statusText,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    trailing: Icon(
                      Icons.open_in_new_rounded,
                      size: 19,
                      color: _settingsAccent(0),
                    ),
                    onTap: _openNotificationSettings,
                  ),
                  _divider(),
                  SwitchListTile.adaptive(
                    secondary: _SettingsIcon(
                      icon: Icons.fiber_new_rounded,
                      color: _settingsAccent(1),
                    ),
                    title: const Text(
                      'Música nueva',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      _notificationsEnabled
                          ? 'Avisos al actualizar las tendencias de Colombia y el mundo'
                          : 'Activa las notificaciones de SoundNeed en Android',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    activeThumbColor: _settingsAccent(1),
                    inactiveTrackColor: _settingsAccent(1)
                        .withValues(alpha: .20),
                    value: widget.player.newMusicNotificationsEnabled,
                    onChanged: (enabled) async {
                      await widget.player.setNewMusicNotificationsEnabled(
                        enabled,
                      );
                      await _loadNotificationStatus();
                    },
                  ),
                ],
              ),
              _sectionLabel('Avisos generales', accent: _settingsAccent(2)),
              _settingsCard(
                accent: _settingsAccent(2),
                children: [
                  ListTile(
                    leading: _SettingsIcon(
                      icon: Icons.notifications_active_outlined,
                      color: _settingsAccent(2),
                    ),
                    title: const Text(
                      'Notificaciones de Android',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      _generalSystemNotificationsEnabled
                          ? 'Activadas; el historial interno se conserva.'
                          : 'Desactivadas en Android; SoundNeed conservará el historial.',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    trailing: Icon(
                      Icons.open_in_new_rounded,
                      size: 19,
                      color: _settingsAccent(2),
                    ),
                    onTap: _manageGeneralNotificationPermission,
                  ),
                  _divider(),
                  for (final category in NotificationCategory.values) ...[
                    SwitchListTile.adaptive(
                      secondary: _SettingsIcon(
                        icon: category.icon,
                        color: _settingsAccent(category.index + 3),
                      ),
                      title: Text(
                        category.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        _notificationCategoryDescription(category),
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      activeThumbColor: _settingsAccent(category.index + 3),
                      inactiveTrackColor: _settingsAccent(category.index + 3)
                          .withValues(alpha: .20),
                      value: _notificationService.isCategoryEnabled(category),
                      onChanged: (enabled) => _notificationService
                          .setCategoryEnabled(category, enabled),
                    ),
                    if (category != NotificationCategory.values.last)
                      _divider(),
                  ],
                ],
              ),
              _sectionLabel('Reproducción', accent: _settingsAccent(3)),
              _settingsCard(
                accent: _settingsAccent(3),
                children: [
                  ListTile(
                    leading: _SettingsIcon(
                      icon: Icons.bedtime_outlined,
                      color: _settingsAccent(3),
                    ),
                    title: const Text(
                      'Temporizador para dormir',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      _formatRemaining(widget.player.sleepTimerRemaining),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: _settingsAccent(3),
                    ),
                    onTap: _showSleepTimerOptions,
                  ),
                  _divider(),
                  SwitchListTile.adaptive(
                    secondary: _SettingsIcon(
                      icon: Icons.playlist_play_rounded,
                      color: _settingsAccent(4),
                    ),
                    title: const Text(
                      'Continuar automáticamente',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'Al terminar la cola, sigue con canciones recomendadas',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    activeThumbColor: _settingsAccent(4),
                    inactiveTrackColor: _settingsAccent(4)
                        .withValues(alpha: .20),
                    value: widget.player.autoContinueEnabled,
                    onChanged: widget.player.setAutoContinueEnabled,
                  ),
                  _divider(),
                  SwitchListTile.adaptive(
                    secondary: _SettingsIcon(
                      icon: Icons.history_rounded,
                      color: _settingsAccent(0),
                    ),
                    title: const Text(
                      'Recordar dónde quedaste',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'Restaura la canción y el punto al volver a abrir SoundNeed',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    activeThumbColor: _settingsAccent(0),
                    inactiveTrackColor: _settingsAccent(0)
                        .withValues(alpha: .20),
                    value: widget.player.rememberPlaybackEnabled,
                    onChanged: widget.player.setRememberPlaybackEnabled,
                  ),
                ],
              ),
              _sectionLabel('Acerca de SoundNeed', accent: _settingsAccent(4)),
              _settingsCard(
                accent: _settingsAccent(4),
                children: [
                  ListTile(
                    leading: _SettingsIcon(
                      icon: Icons.info_outline_rounded,
                      color: _settingsAccent(4),
                    ),
                    title: const Text(
                      'Versión',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      _version,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  _divider(),
                  ListTile(
                    leading: _SettingsIcon(
                      icon: Icons.help_outline_rounded,
                      color: _settingsAccent(0),
                    ),
                    title: const Text(
                      'Ayuda',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'Consejos para usar SoundNeed',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: _settingsAccent(0),
                    ),
                    onTap: _showHelp,
                  ),
                  _divider(),
                  ListTile(
                    leading: _SettingsIcon(
                      icon: Icons.chat_bubble_outline_rounded,
                      color: _settingsAccent(2),
                    ),
                    title: const Text(
                      'Comentarios',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'Comparte una idea o reporta un problema',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: _settingsAccent(2),
                    ),
                    onTap: _shareFeedback,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'SoundNeed  ·  $_version',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon({
    required this.icon,
    this.color = const Color(0xFFB99AFF),
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 650),
    curve: Curves.easeInOutCubic,
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Icon(icon, color: color, size: 21),
  );
}

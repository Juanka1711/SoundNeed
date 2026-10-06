import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../music_player.dart';
import '../player_navigation.dart';
import '../app_colors.dart';
import '../playlist_artwork.dart';
import '../services/youtube_audio_service.dart';
import '../playlist_manager.dart';
import '../widgets/soundneed_search_field.dart';
import '../widgets/soundneed_section_heading.dart';
import '../widgets/soundneed_empty_state.dart';
import '../artist_catalog_service.dart';
import '../artist_discovery_service.dart';
import '../services/recommendation_service.dart';
import '../podcast_service.dart';
import '../services/artwork_palette.dart';

class HomeSection extends StatefulWidget {
  final MusicPlayerController player;
  final ArtworkPalette palette;
  final List<YouTubeSearchResult>? onlineResults;
  final String? onlineQuery;
  final bool isSearchingOnline;
  final VoidCallback? clearOnlineSearch;
  final List<Song>? localSearchResults;

  const HomeSection({
    super.key,
    required this.player,
    required this.palette,
    this.onlineResults,
    this.onlineQuery,
    this.isSearchingOnline = false,
    this.clearOnlineSearch,
    this.localSearchResults,
  });

  @override
  State<HomeSection> createState() => _HomeSectionState();
}

class _HomeSectionState extends State<HomeSection> with WidgetsBindingObserver {
  final PlaylistManager _playlistManager = PlaylistManager.instance;
  List<ArtistPreference> _radioArtists = [];
  List<YouTubeSearchResult> _discoverySuggestions = [];
  List<MusicChartTrack> _currentChart = [];
  List<MusicChartTrack> _worldChart = [];
  List<PodcastEpisode> _podcastEpisodes = [];
  List<PodcastShow> _podcastRecommendations = [];
  List<PodcastShow> _podcastSearchResults = [];
  PodcastShow? _selectedPodcastShow;
  final TextEditingController _podcastSearchController =
      TextEditingController();
  List<Song> _continueListening = [];
  bool _loadingPodcastRecommendations = false;
  bool _searchingPodcasts = false;
  bool _loadingPodcastEpisodes = false;
  List<Song> _surpriseMix = [];
  static const _recentMixKey = 'soundneed_home_mix_recent_ids_v1';
  bool _loadingChart = false;
  Timer? _chartRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playlistManager.initialize();
    _loadRadioArtists();
    _loadDiscoverySuggestions();
    _loadCurrentChart();
    _loadWorldChart();
    _loadPodcastRecommendations();
    widget.player.addListener(_onPlayerChanged);
    _chartRefreshTimer = Timer.periodic(const Duration(hours: 6), (_) {
      _loadCurrentChart(refresh: true);
      _loadWorldChart(refresh: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.player.removeListener(_onPlayerChanged);
    _podcastSearchController.dispose();
    _chartRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _loadCurrentChart();
    _loadWorldChart();
  }

  void _onPlayerChanged() {
    if (widget.player.songs.isNotEmpty && _surpriseMix.isEmpty) {
      _buildSurpriseMix();
    }
  }

  Future<void> _loadDiscoverySuggestions({bool refresh = false}) async {
    try {
      final suggestions = await ArtistDiscoveryService.instance.load(
        forceRefresh: refresh,
      );
      if (!mounted) return;
      setState(() {
        _discoverySuggestions = suggestions;
      });
      _buildSurpriseMix();
    } catch (_) {
      // Keep the last successful discovery list on network failures.
    }
  }

  Future<void> _loadRadioArtists() async {
    try {
      await RecommendationService.instance.initialize();
      final artists = await RecommendationService.instance.getTopArtists(
        limit: 8,
      );
      final learned = await RecommendationService.instance.getContinueListening(
        limit: 12,
      );
      if (!mounted) return;
      final continued = <Song>[];
      for (final entry in learned) {
        if (entry.source == 'youtube') {
          final suggested = _discoverySuggestions.where(
            (result) => result.videoId == entry.id,
          );
          if (suggested.isNotEmpty) {
            continued.add(Song.fromYouTube(suggested.first));
          } else {
            continued.add(
              Song.fromYouTube(
                YouTubeSearchResult(
                  videoId: entry.id,
                  title: entry.title,
                  artist: entry.artist,
                  duration: entry.durationSeconds,
                  thumbnail: entry.thumbnail,
                  url: 'https://www.youtube.com/watch?v=${entry.id}',
                ),
              ),
            );
          }
        } else {
          final local = widget.player.songs.where(
            (song) => song.id.toString() == entry.id,
          );
          if (local.isNotEmpty) continued.add(local.first);
        }
      }
      setState(() {
        _radioArtists = artists;
        _continueListening = continued;
      });
    } catch (_) {
      // Personalized radio stays hidden until local listening data exists.
    }
  }

  Future<void> _loadCurrentChart({bool refresh = false}) async {
    if (mounted) setState(() => _loadingChart = true);
    try {
      final tracks = await ArtistDiscoveryService.instance.loadCurrentChart(
        forceRefresh: refresh,
      );
      if (!mounted) return;
      setState(() {
        _currentChart = tracks;
        _loadingChart = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingChart = false);
    }
  }

  Future<void> _loadWorldChart({bool refresh = false}) async {
    try {
      final tracks = await ArtistDiscoveryService.instance.loadWorldChart(
        forceRefresh: refresh,
      );
      if (!mounted) return;
      setState(() => _worldChart = tracks);
    } catch (_) {
      // Colombia sigue disponible si la consulta multi país falla.
    }
  }

  Future<void> _loadPodcastRecommendations() async {
    if (mounted) setState(() => _loadingPodcastRecommendations = true);
    try {
      final shows = await PodcastService.instance.recommendedPodcasts();
      if (!mounted) return;
      setState(() {
        _podcastRecommendations = shows;
        _loadingPodcastRecommendations = false;
      });
    } catch (_) {
      // La búsqueda sigue disponible aunque falle la lista sugerida.
      if (mounted) setState(() => _loadingPodcastRecommendations = false);
    }
  }

  Future<void> _searchPodcasts() async {
    final query = _podcastSearchController.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searchingPodcasts = true;
      _podcastSearchResults = [];
      _selectedPodcastShow = null;
    });
    try {
      final shows = await PodcastService.instance.searchPodcasts(query);
      if (!mounted) return;
      setState(() {
        _podcastSearchResults = shows;
        _searchingPodcasts = false;
      });
    } catch (_) {
      if (mounted) setState(() => _searchingPodcasts = false);
    }
  }

  Future<void> _selectPodcastShow(PodcastShow show) async {
    setState(() {
      _selectedPodcastShow = show;
      _loadingPodcastEpisodes = true;
      _podcastEpisodes = [];
    });
    List<PodcastEpisode> episodes;
    try {
      episodes = await PodcastService.instance.loadEpisodesForShow(show);
    } catch (_) {
      episodes = const [];
    }
    if (!mounted || _selectedPodcastShow?.id != show.id) return;
    setState(() {
      _podcastEpisodes = episodes;
      _loadingPodcastEpisodes = false;
    });
    if (episodes.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este podcast no publicó un feed de episodios disponible.',
          ),
        ),
      );
    } else if (episodes.isNotEmpty && mounted) {
      // Al elegir un programa desde la búsqueda, inicia su episodio más nuevo.
      await _playPodcast(episodes.first);
    }
  }

  Future<void> _buildSurpriseMix() async {
    final candidates = <Song>[
      ...widget.player.songs,
      ..._discoverySuggestions.map(Song.fromYouTube),
    ];
    final unique = <String, Song>{};
    for (final song in candidates) {
      final key = song.isOnline
          ? 'yt:${song.onlineVideoId}'
          : 'local:${song.uri}';
      if (key.trim().isNotEmpty) unique.putIfAbsent(key, () => song);
    }
    if (unique.isEmpty) return;

    final preferences = await SharedPreferences.getInstance();
    final recent = preferences.getStringList(_recentMixKey) ?? const [];
    final fresh = unique.entries
        .where((entry) => !recent.contains(entry.key))
        .toList();
    final pool = fresh.length >= 4 ? fresh : unique.entries.toList();
    pool.shuffle();
    if (!mounted) return;
    setState(
      () => _surpriseMix = pool.take(15).map((entry) => entry.value).toList(),
    );
  }

  Future<void> _playSurpriseMix() async {
    if (_surpriseMix.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final keys = _surpriseMix.map(
      (song) =>
          song.isOnline ? 'yt:${song.onlineVideoId}' : 'local:${song.uri}',
    );
    final previous = prefs.getStringList(_recentMixKey) ?? const [];
    await prefs.setStringList(
      _recentMixKey,
      [...keys, ...previous].toSet().take(50).toList(),
    );
    await widget.player.playPlaylist(_surpriseMix, shuffle: true);
  }

  Future<void> _playPodcast(PodcastEpisode episode) async {
    if (episode.audioUrl.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este episodio no tiene audio disponible.'),
        ),
      );
      return;
    }
    final queue = _podcastEpisodes.map((item) => item.toSong()).toList();
    var startIndex = _podcastEpisodes.indexOf(episode);
    if (startIndex < 0) {
      queue.insert(0, episode.toSong());
      startIndex = 0;
    }
    await widget.player.playPlaylist(queue, startIndex: startIndex);
    if (!mounted) return;
    final error = widget.player.playbackError;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo reproducir el podcast: $error')),
      );
      return;
    }
    try {
      await PodcastService.instance.markPlayed(
        episode,
        show: _selectedPodcastShow,
      );
      unawaited(_loadPodcastRecommendations());
    } catch (_) {
      // Un error al actualizar recomendaciones no interrumpe el audio.
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;

    final showOnlineResults =
        widget.onlineResults != null || widget.isSearchingOnline;

    final hasLocalSearch = widget.localSearchResults != null;

    return RefreshIndicator(
      color: Colors.white,
      backgroundColor: AppColors.card,
      onRefresh: () async {
        await player.loadSongs();

        await _loadDiscoverySuggestions(refresh: true);
        await _loadCurrentChart(refresh: true);
        await _loadWorldChart(refresh: true);
        await _loadRadioArtists();
        await _loadPodcastRecommendations();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          _buildHeader(),

          const SizedBox(height: 20),

          /// ====================================================
          /// BÚSQUEDA LOCAL
          /// ====================================================
          if (hasLocalSearch) ...[
            _buildLocalSearchResults(),

            const SizedBox(height: 32),
          ]
          /// ====================================================
          /// CONTENIDO NORMAL
          /// ====================================================
          else ...[
            if (_currentChart.isNotEmpty) ...[
              _buildHomeFeature(),
              const SizedBox(height: 22),
            ],
            if (!player.loading && !player.permissionDenied) ...[
              _buildQuickPlaylists(),
              const SizedBox(height: 24),
              _buildSurpriseMixCard(),
            ],

            if (player.loading)
              _buildLoading()
            else if (player.permissionDenied)
              _buildPermissionMessage()
            else if (player.songs.isEmpty) ...[
              const SizedBox(height: 24),
              _buildEmptyLibrary(),
            ],

            if (!player.loading &&
                !player.permissionDenied &&
                _continueListening.isNotEmpty) ...[
              const SizedBox(height: 30),
              _buildContinueListening(),
            ],

            const SizedBox(height: 30),
            _buildDiscoverySuggestions(),

            if (_worldChart.isNotEmpty) ...[
              const SizedBox(height: 26),
              _buildWorldChart(),
            ],

            const SizedBox(height: 30),
            _buildPodcasts(),

            if (_radioArtists.isNotEmpty) ...[
              const SizedBox(height: 30),
              _buildRecommendedStations(),
            ],
          ],

          /// ====================================================
          /// YOUTUBE
          /// ====================================================
          if (showOnlineResults) ...[
            const SizedBox(height: 32),
            _buildOnlineResults(),
          ],

          /// Evita que el último contenido
          /// quede pegado al borde inferior.
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildQuickPlaylists() => AnimatedBuilder(
    animation: _playlistManager,
    builder: (context, _) {
      final items = <_HomePlaylistItem>[];
      final likedByKey = <String, Song>{};
      for (final song in _playlistManager.likedSongs) {
        likedByKey[songKey(song)] = song;
      }
      for (final song in widget.player.songs.where(widget.player.isFavorite)) {
        likedByKey.putIfAbsent(songKey(song), () => song);
      }
      if (likedByKey.isNotEmpty) {
        items.add(
          _HomePlaylistItem(
            name: 'Me gusta',
            songs: likedByKey.values.toList(),
            color: const Color(0xFFF43F5E),
            icon: Icons.favorite_rounded,
          ),
        );
      }
      items.addAll(
        _playlistManager.playlists.map(
          (playlist) => _HomePlaylistItem(
            name: playlist.name,
            songs: playlist.songs,
            color: const Color(0xFF7652D8),
            icon: Icons.queue_music_rounded,
          ),
        ),
      );
      final visible = items.take(6).toList();
      if (visible.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading('Tus playlists', ''),
          const SizedBox(height: 13),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visible.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 17,
              childAspectRatio: .80,
            ),
            itemBuilder: (context, index) {
              final item = visible[index];
              return InkWell(
                borderRadius: BorderRadius.circular(19),
                onTap: () {
                  if (item.songs.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${item.name} todavía está vacía.'),
                      ),
                    );
                    return;
                  }
                  widget.player.playPlaylist(item.songs);
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(19),
                          border: Border.all(
                            color: item.color.withValues(alpha: .35),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(19),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              PlaylistArtwork(
                                player: widget.player,
                                songs: item.songs,
                                icon: item.icon,
                                accent: item.color,
                              ),
                              Positioned(
                                right: 10,
                                bottom: 10,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(7),
                                    child: Icon(
                                      Icons.play_arrow_rounded,
                                      color: item.color,
                                      size: 25,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Playlist · ${item.songs.length} ${item.songs.length == 1 ? 'canción' : 'canciones'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      );
    },
  );

  Widget _buildSurpriseMixCard() {
    if (_surpriseMix.isEmpty &&
        _discoverySuggestions.isEmpty &&
        widget.player.songs.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.lerp(widget.palette.primary, widget.palette.dark, .52)!,
            widget.palette.dark,
            AppColors.card,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: widget.palette.secondary.withValues(alpha: .22),
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.shuffle_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mezcla sorpresa',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  _surpriseMix.isEmpty
                      ? 'Preparando tu mezcla…'
                      : '${_surpriseMix.length} canciones para descubrir',
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton.filled(
            tooltip: 'Reproducir mezcla',
            onPressed: _surpriseMix.isEmpty ? null : _playSurpriseMix,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF251A38),
            ),
            icon: const Icon(Icons.play_arrow_rounded),
          ),
          IconButton(
            tooltip: 'Mezclar de nuevo',
            onPressed: _buildSurpriseMix,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeFeature() {
    final track = _currentChart.first;
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: SizedBox(
        height: 245,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              track.artworkUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(
                color: AppColors.card,
                child: Icon(Icons.music_note_rounded, size: 52),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x22000000),
                    Color(0x44000000),
                    Color(0xF20B0B12),
                  ],
                  stops: [0, .36, 1],
                ),
              ),
            ),
            Positioned(
              top: 14,
              left: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xD90B0B12),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .14),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      size: 15,
                      color: widget.palette.secondary,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'SONANDO EN COLOMBIA',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .7,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 16,
              bottom: 16,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'N.º ${track.rank} DEL MOMENTO',
                          style: TextStyle(
                            color: widget.palette.secondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .8,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          track.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 24,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.5,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    tooltip: 'Reproducir canción destacada',
                    onPressed: () => _playChartTrack(track),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      fixedSize: const Size(52, 52),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 30),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueListening() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionHeading('Continúa escuchando', ''),
      const SizedBox(height: 14),
      SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _continueListening.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final song = _continueListening[index];
            return SizedBox(
              width: 245,
              child: Material(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _playContinuedSong(song),
                  child: Row(
                    children: [
                      _buildArtwork(song, size: 88),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );

  Widget _buildPodcasts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _sectionHeading('Podcasts', '')),
            IconButton(
              onPressed: _loadingPodcastRecommendations
                  ? null
                  : _loadPodcastRecommendations,
              tooltip: 'Actualizar recomendaciones',
              icon: Icon(
                Icons.refresh_rounded,
                color: widget.palette.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        const Text(
          'Busca y descubre podcasts.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 14),
        SoundNeedSearchField(
          controller: _podcastSearchController,
          hintText: 'Buscar podcasts o temas',
          prefixIcon: Icons.podcasts_rounded,
          height: 56,
          onChanged: (query) {
            if (query.trim().isEmpty && _podcastSearchResults.isNotEmpty) {
              setState(() => _podcastSearchResults = []);
            }
          },
          onSubmitted: (_) => _searchPodcasts(),
          suffix: IconButton(
            tooltip: 'Buscar podcasts',
            onPressed: _searchingPodcasts ? null : _searchPodcasts,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              fixedSize: const Size(38, 38),
            ),
            icon: _searchingPodcasts
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search_rounded, size: 20),
          ),
        ),
        if (_searchingPodcasts)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: CircularProgressIndicator(color: Colors.white),
            ),
          )
        else if (_podcastSearchResults.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionHeading(
            'Resultados de búsqueda',
            '${_podcastSearchResults.length}',
          ),
          const SizedBox(height: 10),
          ..._podcastSearchResults.take(8).map(_buildPodcastShowTile),
        ] else if (_podcastSearchController.text.trim().isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 15),
            child: Text(
              'No encontramos programas con ese término. Prueba con otro tema o nombre.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
        if (_loadingPodcastRecommendations && _podcastRecommendations.isEmpty)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          )
        else if (_podcastRecommendations.isNotEmpty) ...[
          const SizedBox(height: 22),
          _sectionHeading(
            _selectedPodcastShow == null
                ? 'Podcasts que podrían gustarte'
                : 'Más podcasts para ti',
            'Para ti',
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 164,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _podcastRecommendations.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final show = _podcastRecommendations[index];
                return SizedBox(
                  width: 122,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(15),
                    onTap: () => _selectPodcastShow(show),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: 122,
                            height: 112,
                            child: Image.network(
                              show.artworkUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const ColoredBox(
                                color: AppColors.card,
                                child: Icon(
                                  Icons.podcasts_rounded,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          show.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ] else if (_podcastSearchResults.isEmpty &&
            _podcastSearchController.text.isEmpty)
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Busca cualquier programa por su nombre o tema para ver sus episodios.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
        if (_selectedPodcastShow != null) ...[
          const SizedBox(height: 20),
          _sectionHeading('Episodios · ${_selectedPodcastShow!.title}', 'RSS'),
          const SizedBox(height: 10),
          if (_loadingPodcastEpisodes)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: CircularProgressIndicator(color: Colors.white),
              ),
            )
          else if (_podcastEpisodes.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'No se pudieron cargar episodios. Revisa tu conexión e inténtalo de nuevo.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            )
          else
            ..._podcastEpisodes.take(6).map(_buildPodcastTile),
        ],
      ],
    );
  }

  Widget _buildPodcastShowTile(PodcastShow show) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _selectPodcastShow(show),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Image.network(
                  show.artworkUrl,
                  width: 58,
                  height: 58,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(
                    width: 58,
                    height: 58,
                    child: ColoredBox(
                      color: Color(0xFF30254A),
                      child: Icon(
                        Icons.podcasts_rounded,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      show.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      show.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      show.genre,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white,
                size: 30,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _playContinuedSong(Song song) async {
    if (widget.player.currentSong?.id == song.id &&
        widget.player.currentSong?.uri == song.uri) {
      await selectSongOrOpenPlayer(context, widget.player, song);
      return;
    }
    if (!song.isOnline) {
      await widget.player.playSong(song);
      return;
    }
    final matches = _discoverySuggestions.where(
      (result) => result.videoId == song.onlineVideoId,
    );
    final result = matches.isNotEmpty
        ? matches.first
        : YouTubeSearchResult(
            videoId: song.onlineVideoId,
            title: song.title,
            artist: song.artist,
            duration: (song.duration / 1000).round(),
            thumbnail: song.artworkUri,
            url: song.uri,
          );
    await widget.player.playOnline(result, playlist: _discoverySuggestions);
  }

  Future<void> _playChartTrack(MusicChartTrack track) async {
    try {
      final inColombiaChart = _currentChart.any(
        (candidate) =>
            candidate.id == track.id &&
            candidate.title == track.title &&
            candidate.artist == track.artist,
      );
      final sourceChart = inColombiaChart ? _currentChart : _worldChart;
      final results = await YouTubeAudioService.instance.search(
        '${track.title} ${track.artist} audio',
      );
      if (results.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No encontramos este tema para reproducir.'),
            ),
          );
        }
        return;
      }
      final normalizedTitle = track.title.toLowerCase();
      final result = results.firstWhere(
        (candidate) => candidate.title.toLowerCase().contains(normalizedTitle),
        orElse: () => results.first,
      );
      final ok = await widget.player.playOnline(result, playlist: [result]);
      if (ok) {
        widget.player.loadChartQueue(
          result.videoId,
          ArtistDiscoveryService.instance.resolvePlaybackQueue(
            sourceChart,
            startWith: track,
            firstResult: result,
          ),
        );
      }
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.player.playbackError ?? 'No se pudo reproducir.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo buscar este tema ahora.')),
      );
    }
  }

  Widget _sectionHeading(String title, String trailing) =>
      SoundNeedSectionHeading(
        title: title,
        detail: trailing,
        accent: widget.palette.primary,
      );

  Widget _buildPodcastTile(PodcastEpisode episode) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(17),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _playPodcast(episode),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 68,
                  height: 68,
                  child: episode.artworkUrl.isEmpty
                      ? const ColoredBox(
                          color: Color(0xFF30254A),
                          child: Icon(
                            Icons.podcasts_rounded,
                            color: Colors.white70,
                            size: 30,
                          ),
                        )
                      : Image.network(
                          episode.artworkUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const ColoredBox(
                            color: Color(0xFF30254A),
                            child: Icon(
                              Icons.podcasts_rounded,
                              color: Colors.white70,
                              size: 30,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      episode.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      episode.showTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      episode.category,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white,
                size: 31,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildDiscoverySuggestions() {
    if (_currentChart.isEmpty &&
        _loadingChart &&
        _discoverySuggestions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 22),
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (_currentChart.isEmpty && _discoverySuggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _sectionHeading('Lo más escuchado ahora', '')),
            IconButton(
              tooltip: 'Actualizar éxitos',
              onPressed: _loadingChart
                  ? null
                  : () => _loadCurrentChart(refresh: true),
              icon: Icon(
                Icons.refresh_rounded,
                color: widget.palette.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          _currentChart.isNotEmpty
              ? 'Éxitos de Colombia'
              : 'Nuevos descubrimientos',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 226,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _currentChart.isNotEmpty
                ? _currentChart.skip(1).take(14).length
                : _discoverySuggestions.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              if (_currentChart.isNotEmpty) {
                final track = _currentChart[index + 1];
                final isRelated = _radioArtists.any(
                  (artist) =>
                      artist.name.toLowerCase() == track.artist.toLowerCase(),
                );
                return SizedBox(
                  width: 148,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _playChartTrack(track),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(13),
                                child: Image.network(
                                  track.artworkUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const ColoredBox(
                                    color: AppColors.card,
                                    child: Icon(Icons.music_note_rounded),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 8,
                                top: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xD9000000),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '#${track.rank}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              const Positioned(
                                right: 8,
                                bottom: 8,
                                child: CircleAvatar(
                                  radius: 17,
                                  backgroundColor: Colors.white,
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.black,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        if (isRelated)
                          const Text(
                            'Te puede gustar',
                            maxLines: 1,
                            style: TextStyle(
                              color: Color(0xFFC19AFF),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }

              final song = _discoverySuggestions[index];
              return SizedBox(
                width: 154,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => widget.player.playOnline(
                    song,
                    playlist: _discoverySuggestions,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 154,
                            child: song.thumbnail.isEmpty
                                ? const ColoredBox(
                                    color: AppColors.card,
                                    child: Icon(Icons.music_note_rounded),
                                  )
                                : Image.network(
                                    song.thumbnail,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const ColoredBox(
                                      color: AppColors.card,
                                      child: Icon(Icons.music_note_rounded),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        song.artist.isEmpty ? 'YouTube' : song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWorldChart() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading('Lo más escuchado en el mundo', 'Global'),
        const SizedBox(height: 5),
        const Text(
          'Éxitos de todo el mundo',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 218,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _worldChart.take(15).length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final track = _worldChart[index];
              return SizedBox(
                width: 148,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _playChartTrack(track),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(13),
                              child: Image.network(
                                track.artworkUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const ColoredBox(
                                  color: AppColors.card,
                                  child: Icon(Icons.music_note_rounded),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xD9000000),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '#${track.rank} · MUNDO',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            const Positioned(
                              right: 8,
                              bottom: 8,
                              child: CircleAvatar(
                                radius: 17,
                                backgroundColor: Colors.white,
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.black,
                                  size: 22,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendedStations() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionHeading('Estaciones recomendadas', ''),
      const SizedBox(height: 5),
      const Text(
        'Mezclas basadas en los artistas que escuchas',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
      const SizedBox(height: 14),
      SizedBox(
        height: 205,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _radioArtists.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final artist = _radioArtists[index];
            return SizedBox(
              width: 150,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _playArtistStation(artist.name),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _stationArtwork(artist.name)),
                    const SizedBox(height: 9),
                    Text(
                      artist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Radio para ti',
                      maxLines: 1,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ],
  );

  Widget _stationArtwork(String artist) => FutureBuilder<ArtistCatalogEntry?>(
    future: ArtistCatalogService.instance.lookup(artist),
    builder: (context, snapshot) {
      final imageUrl = snapshot.data?.pictureUrl;
      final localSongs = widget.player.songs
          .where((song) => song.artist.toLowerCase() == artist.toLowerCase())
          .toList();
      final localSong = localSongs.isEmpty ? null : localSongs.first;
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox.expand(
          child: imageUrl != null
              ? Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _stationFallback(localSong),
                )
              : _stationFallback(localSong),
        ),
      );
    },
  );

  Widget _stationFallback(Song? song) {
    if (song == null) {
      return const ColoredBox(
        color: Color(0xFF29243A),
        child: Icon(Icons.radio_rounded, size: 38, color: Colors.white70),
      );
    }
    return FutureBuilder(
      future: widget.player.loadArtwork(song),
      builder: (context, snapshot) => snapshot.data == null
          ? const ColoredBox(
              color: Color(0xFF29243A),
              child: Icon(Icons.radio_rounded, size: 38, color: Colors.white70),
            )
          : Image.memory(snapshot.data!, fit: BoxFit.cover),
    );
  }

  Future<void> _playArtistStation(String artist) async {
    try {
      final results = await YouTubeAudioService.instance.search('$artist mix');
      if (results.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No encontramos canciones para esta radio.'),
            ),
          );
        }
        return;
      }
      final ok = await widget.player.playOnline(
        results.first,
        playlist: results,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.player.playbackError ?? 'No se pudo iniciar la radio.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cargar esta radio.')),
      );
    }
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader() {
    final songCount = widget.player.songs.length;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Buenos días'
        : hour < 19
        ? 'Buenas tardes'
        : 'Buenas noches';
    final subtitle = songCount == 0
        ? 'Tu próximo descubrimiento empieza aquí.'
        : '$songCount ${songCount == 1 ? 'canción lista' : 'canciones listas'} para acompañarte.';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: widget.palette.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'TU SONIDO · HOY',
                    style: TextStyle(
                      color: widget.palette.secondary.withValues(alpha: .9),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.35,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                '$greeting 👋',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 29,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [widget.palette.secondary, widget.palette.primary],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: .18)),
            boxShadow: [
              BoxShadow(
                color: widget.palette.primary.withValues(alpha: .30),
                blurRadius: 22,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: const Icon(
            Icons.graphic_eq_rounded,
            color: Colors.white,
            size: 32,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // LOCAL SEARCH
  // ============================================================

  Widget _buildLocalSearchResults() {
    final results = widget.localSearchResults ?? [];

    if (results.isEmpty) {
      return SoundNeedEmptyState(
        icon: Icons.search_off_rounded,
        title: 'Sin resultados locales',
        message: 'No encontramos canciones en tu biblioteca.',
        accent: widget.palette.primary,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Resultados locales',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              '${results.length}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        ...results.map(_buildSongTile),
      ],
    );
  }

  // ============================================================
  // ONLINE RESULTS
  // ============================================================

  Widget _buildOnlineResults() {
    if (widget.isSearchingOnline) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 18),
            Text(
              'Buscando en YouTube...',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    final results = widget.onlineResults ?? [];

    if (results.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Resultados de YouTube',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              '${results.length}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        ...results.map(_buildOnlineSongTile),
      ],
    );
  }

  Widget _buildSongTile(Song song) {
    final player = widget.player;

    final isCurrent = player.currentSong?.id == song.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isCurrent ? Colors.white.withOpacity(0.06) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => selectSongOrOpenPlayer(context, player, song),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _buildArtwork(song, size: 56),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title.isEmpty ? song.displayName : song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isCurrent
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        song.artist.isEmpty
                            ? 'Artista desconocido'
                            : song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                Text(
                  player.formatDuration(song.duration),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ARTWORK LOCAL
  // ============================================================

  Widget _buildArtwork(Song song, {double size = 56}) {
    return FutureBuilder(
      future: widget.player.loadArtwork(song),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
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
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: const Icon(Icons.music_note, size: 24, color: Colors.white54),
        );
      },
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  // ============================================================
  // ONLINE SONG TILE
  // ============================================================

  Widget _buildOnlineSongTile(YouTubeSearchResult result) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            // Precargar URL en segundo plano
            unawaited(widget.player.preloadYoutubeUrl(result.videoId));

            final selectedSong = Song.fromYouTube(result);
            if (widget.player.currentSong?.id == selectedSong.id &&
                widget.player.currentSong?.uri == selectedSong.uri) {
              await selectSongOrOpenPlayer(
                context,
                widget.player,
                selectedSong,
              );
              return;
            }
            final messenger = ScaffoldMessenger.of(context);

            debugPrint(
              '[SoundNeed] YouTube seleccionado: '
              '${result.videoId}',
            );

            final ok = await widget.player.playOnline(
              result,
              playlist: widget.onlineResults,
            );

            if (!ok && mounted) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    'No se pudo reproducir: '
                    '${widget.player.playbackError ?? 'error desconocido'}',
                  ),
                ),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 120,
                    height: 68,
                    child: result.thumbnail.isNotEmpty
                        ? Image.network(
                            result.thumbnail,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return _buildOnlinePlaceholder();
                            },
                          )
                        : _buildOnlinePlaceholder(),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 5),

                      Text(
                        result.artist.isEmpty ? 'YouTube' : result.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),

                      if (result.duration > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          _formatOnlineDuration(result.duration),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                const Icon(
                  Icons.play_circle_outline,
                  color: Colors.white70,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOnlinePlaceholder() {
    return Container(
      color: Colors.white.withOpacity(0.06),
      child: const Icon(Icons.music_note, color: Colors.white38, size: 26),
    );
  }

  String _formatOnlineDuration(int seconds) {
    if (seconds <= 0) {
      return '';
    }

    final duration = Duration(seconds: seconds);

    final hours = duration.inHours;

    final minutes = duration.inMinutes.remainder(60);

    final secs = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:'
          '${secs.toString().padLeft(2, '0')}';
    }

    return '$minutes:'
        '${secs.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // LOADING
  // ============================================================

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Center(
        child: CircularProgressIndicator(color: widget.palette.secondary),
      ),
    );
  }

  // ============================================================
  // PERMISSION
  // ============================================================

  Widget _buildPermissionMessage() {
    return SoundNeedEmptyState(
      icon: Icons.folder_shared_rounded,
      title: 'Necesitamos acceso a tu música',
      message: 'Concede permiso para que SoundNeed pueda mostrar los archivos de audio del dispositivo.',
      accent: widget.palette.primary,
      action: FilledButton.icon(
        onPressed: widget.player.loadSongs,
        icon: const Icon(Icons.lock_open_rounded),
        label: const Text('Conceder permiso'),
        style: FilledButton.styleFrom(
          backgroundColor: widget.palette.primary,
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
        ),
      ),
    );
  }

  // ============================================================
  // EMPTY LIBRARY
  // ============================================================

  Widget _buildEmptyLibrary() {
    return SoundNeedEmptyState(
      icon: Icons.library_music_rounded,
      title: 'Tu biblioteca está lista para sonar',
      message: 'Agrega archivos de música a tu dispositivo y actualiza la biblioteca.',
      accent: widget.palette.primary,
      action: FilledButton.icon(
        onPressed: widget.player.loadSongs,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Actualizar música'),
        style: FilledButton.styleFrom(
          backgroundColor: widget.palette.primary,
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
        ),
      ),
    );
  }
}

class _HomePlaylistItem {
  const _HomePlaylistItem({
    required this.name,
    required this.songs,
    required this.color,
    required this.icon,
  });

  final String name;
  final List<Song> songs;
  final Color color;
  final IconData icon;
}

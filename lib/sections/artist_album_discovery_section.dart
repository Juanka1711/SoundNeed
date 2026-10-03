import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../artist_catalog_service.dart';
import '../music_player.dart';
import '../playlist_actions.dart';
import '../services/recommendation_service.dart';
import '../artist_discovery_service.dart';
import '../services/youtube_audio_service.dart';

/// Personal recommendations come from local listening history. YouTube search
/// results are presented as discovery results, never as verified charts.
class ArtistAlbumDiscoverySection extends StatefulWidget {
  const ArtistAlbumDiscoverySection({
    super.key,
    required this.player,
    required this.songs,
    required this.showArtists,
    this.searchText = '',
  });

  final MusicPlayerController player;
  final List<Song> songs;
  final bool showArtists;
  final String searchText;

  @override
  State<ArtistAlbumDiscoverySection> createState() =>
      _ArtistAlbumDiscoverySectionState();
}

class _ArtistAlbumDiscoverySectionState
    extends State<ArtistAlbumDiscoverySection>
    with WidgetsBindingObserver {
  final _recommendations = RecommendationService.instance;
  List<ArtistPreference> _topArtists = [];
  List<LearnedSong> _mostPlayed = [];
  List<YouTubeSearchResult> _youtubeDiscovery = [];
  List<MusicChartArtist> _worldArtists = [];
  List<MusicChartTrack> _worldChart = [];
  String? _selectedArtist;
  _MediaGroup? _selectedAlbum;
  List<YouTubeSearchResult> _artistResults = [];
  ArtistCatalogEntry? _artistCatalog;
  bool _loadingPersonal = true;
  bool _loadingOnline = false;
  bool _loadingDiscovery = true;
  String? _onlineError;
  int _requestId = 0;
  Timer? _chartRefreshTimer;
  bool _loadingWorldChart = true;

  bool get _isArtists => widget.showArtists;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadPersonalRecommendations());
    unawaited(_loadYouTubeDiscovery());
    unawaited(_loadWorldArtists());
    if (_isArtists) {
      _chartRefreshTimer = Timer.periodic(
        const Duration(hours: 6),
        (_) => unawaited(_loadWorldArtists(refresh: true)),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chartRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isArtists && state == AppLifecycleState.resumed) {
      unawaited(_loadWorldArtists());
    }
  }

  @override
  void didUpdateWidget(covariant ArtistAlbumDiscoverySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showArtists != widget.showArtists) {
      _selectedArtist = null;
      _selectedAlbum = null;
    }
  }

  Future<void> _loadPersonalRecommendations() async {
    if (mounted) setState(() => _loadingPersonal = true);
    try {
      await _recommendations.initialize();
      final values = await Future.wait([
        _recommendations.getTopArtists(limit: 30),
        _recommendations.getMostPlayed(limit: 30),
      ]);
      if (!mounted) return;
      setState(() {
        _topArtists = values[0] as List<ArtistPreference>;
        _mostPlayed = values[1] as List<LearnedSong>;
        _loadingPersonal = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingPersonal = false;
        _onlineError = 'No se pudieron cargar tus recomendaciones.';
      });
    }
  }

  Future<void> _refresh() async {
    await Future.wait([
      widget.player.loadSongs(),
      _loadPersonalRecommendations(),
      _loadYouTubeDiscovery(),
      _loadWorldArtists(refresh: true),
    ]);
    if (_selectedArtist != null) await _refreshArtist(_selectedArtist!);
  }

  Future<void> _loadWorldArtists({bool refresh = false}) async {
    if (!_isArtists) return;
    if (_worldChart.isEmpty && mounted) {
      setState(() => _loadingWorldChart = true);
    }
    try {
      final service = ArtistDiscoveryService.instance;
      final chart = await service.loadWorldChart(forceRefresh: refresh);
      if (!mounted) return;
      setState(() {
        _worldChart = chart;
        _worldArtists = service.worldArtists;
        _loadingWorldChart = false;
      });
    } catch (_) {
      // El ranking personalizado permanece disponible si falla la red.
      if (mounted) setState(() => _loadingWorldChart = false);
    }
  }

  Future<void> _refreshArtist(String artist) async {
    await Future.wait([
      _loadArtistSearch(artist),
      _loadArtistCatalog(artist, forceRefresh: true),
    ]);
  }

  Future<void> _loadYouTubeDiscovery() async {
    if (!_isArtists) return;
    if (mounted) setState(() => _loadingDiscovery = true);
    try {
      final results = await ArtistDiscoveryService.instance.load(
        forceRefresh: true,
      );
      if (!mounted) return;
      setState(() {
        _youtubeDiscovery = results;
        _loadingDiscovery = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingDiscovery = false);
    }
  }

  Future<void> _openArtist(String artist) async {
    setState(() {
      _selectedArtist = artist;
      _selectedAlbum = null;
      _artistResults = [];
      _artistCatalog = null;
      _onlineError = null;
    });
    await Future.wait([
      _loadArtistSearch(artist),
      _loadArtistCatalog(artist, forceRefresh: true),
    ]);
  }

  Future<void> _loadArtistCatalog(
    String artist, {
    bool forceRefresh = false,
  }) async {
    final entry = await ArtistCatalogService.instance.lookup(
      artist,
      forceRefresh: forceRefresh,
    );
    if (!mounted || _selectedArtist?.toLowerCase() != artist.toLowerCase()) {
      return;
    }
    setState(() => _artistCatalog = entry);
  }

  Future<void> _loadArtistSearch(String artist) async {
    final request = ++_requestId;
    setState(() {
      _loadingOnline = true;
      _onlineError = null;
    });
    try {
      final results = await YouTubeAudioService.instance.search(
        '$artist canciones',
      );
      if (!mounted || request != _requestId) return;
      final seen = <String>{};
      final filtered = results
          .where(
            (result) => result.videoId.isNotEmpty && seen.add(result.videoId),
          )
          .take(15)
          .toList();
      setState(() {
        _artistResults = filtered;
        _loadingOnline = false;
        if (filtered.isEmpty) {
          _onlineError =
              'No encontramos resultados de YouTube para este artista.';
        }
      });
    } catch (_) {
      if (!mounted || request != _requestId) return;
      setState(() {
        _loadingOnline = false;
        _onlineError = 'No se pudo actualizar la búsqueda. Intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedArtist != null && _isArtists) {
      return _artistProfile(_selectedArtist!);
    }
    if (_selectedAlbum != null && !_isArtists) {
      return _albumProfile(_selectedAlbum!);
    }

    final groups = _makeGroups(widget.songs);
    final query = widget.searchText.trim().toLowerCase();
    final visibleGroups = query.isEmpty
        ? groups
        : groups.where(
            (group) =>
                group.title.toLowerCase().contains(query) ||
                group.subtitle.toLowerCase().contains(query),
          );
    final visibleArtists = _topArtists
        .where((item) => item.name.trim().isNotEmpty)
        .where(
          (item) => query.isEmpty || item.name.toLowerCase().contains(query),
        )
        .toList();
    final visibleWorldArtists = _worldArtists
        .where(
          (artist) =>
              query.isEmpty || artist.name.toLowerCase().contains(query),
        )
        .toList();
    final monthlyDays = ArtistDiscoveryService.instance.monthlySnapshotDays;

    return RefreshIndicator(
      color: Colors.white,
      backgroundColor: AppColors.card,
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(
            _isArtists ? 'Artistas' : 'Álbumes de tu biblioteca',
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            _isArtists
                ? 'Tendencias globales y tus artistas.'
                : 'Ordenados según los artistas que más escuchas.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          if (_isArtists && _loadingWorldChart && visibleWorldArtists.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          if (_isArtists && visibleWorldArtists.isNotEmpty) ...[
            const SizedBox(height: 22),
            _sectionHeading('Tendencias de los últimos 30 días', 'Global'),
            const SizedBox(height: 5),
            Text(
              '12 países · $monthlyDays/30 días',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            _monthlyArtistFeature(visibleWorldArtists.first),
            const SizedBox(height: 21),
            _sectionHeading('Artistas más escuchados', 'Últimos 30 días'),
            const SizedBox(height: 13),
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: visibleWorldArtists.take(20).length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final artist = visibleWorldArtists[index];
                  return SizedBox(
                    width: 94,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => _openArtist(artist.name),
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              _Artwork(
                                player: widget.player,
                                song: null,
                                artistName: artist.name,
                                size: 82,
                                circular: true,
                                icon: Icons.person_rounded,
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: CircleAvatar(
                                  radius: 13,
                                  backgroundColor: const Color(0xFF211A37),
                                  child: Text(
                                    '${artist.rank}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            artist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (_isArtists && visibleArtists.isNotEmpty) ...[
            const SizedBox(height: 22),
            _sectionHeading(
              'Tus artistas más escuchados',
              'Según tu actividad',
            ),
            const SizedBox(height: 13),
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: visibleArtists.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final artist = visibleArtists[index];
                  final local = _songsForArtist(artist.name);
                  return SizedBox(
                    width: 94,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => _openArtist(artist.name),
                      child: Column(
                        children: [
                          _Artwork(
                            player: widget.player,
                            song: local.isEmpty ? null : local.first,
                            artistName: artist.name,
                            size: 82,
                            circular: true,
                            icon: Icons.person_rounded,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            artist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (_loadingPersonal && _isArtists)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          if (_isArtists &&
              visibleArtists.isEmpty &&
              !_loadingPersonal &&
              _worldArtists.isEmpty)
            _emptyPersonalHint(),
          if (_isArtists && query.isEmpty) ...[
            const SizedBox(height: 18),
            _sectionHeading('Descubre en YouTube', 'Búsqueda actual'),
            const SizedBox(height: 12),
            if (_loadingDiscovery)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              )
            else if (_youtubeDiscovery.isEmpty)
              _message(Icons.search_rounded, 'Desliza para buscar de nuevo.')
            else
              ..._youtubeDiscovery.map(_discoveryTile),
          ],
          const SizedBox(height: 18),
          _sectionHeading(
            _isArtists ? 'Artistas de tu biblioteca' : 'Tus álbumes',
            '${visibleGroups.length}',
          ),
          const SizedBox(height: 12),
          if (visibleGroups.isEmpty)
            _emptyLibrary()
          else if (_isArtists)
            ...visibleGroups.map(_artistTile)
          else
            _albumGrid(visibleGroups.toList()),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _monthlyArtistFeature(MusicChartArtist artist) => Material(
    color: AppColors.card,
    borderRadius: BorderRadius.circular(24),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => _openArtist(artist.name),
      child: SizedBox(
        height: 238,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (artist.artworkUrl.isNotEmpty)
              Image.network(
                artist.artworkUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: AppColors.card,
                  child: SizedBox.expand(),
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Color(0xAA542E88),
                    Color(0xCC171323),
                    Color(0xF20B0B12),
                  ],
                ),
              ),
            ),
            Positioned(
              right: -36,
              top: -55,
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .10),
                    width: 24,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .13),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .16),
                            ),
                          ),
                          child: Text(
                            'N.º ${artist.rank} · 30 DÍAS',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .7,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          artist.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 25,
                            height: 1.02,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.5,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${artist.songs.length} temas destacados',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 13),
                        FilledButton.icon(
                          onPressed: artist.songs.isEmpty
                              ? null
                              : () => _playWorldTrack(artist.songs.first),
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: const Text('Escuchar'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF171323),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .75),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .35),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: _Artwork(
                      player: widget.player,
                      song: null,
                      artistName: artist.name,
                      size: 112,
                      circular: true,
                      icon: Icons.person_rounded,
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

  Widget _artistProfile(String name) {
    final localSongs = _songsForArtist(name);
    final learnedSongs = _mostPlayed
        .where((song) => song.artist.toLowerCase() == name.toLowerCase())
        .toList();
    final sample = localSongs.isNotEmpty ? localSongs.first : null;

    return RefreshIndicator(
      color: Colors.white,
      backgroundColor: AppColors.card,
      onRefresh: () => _refreshArtist(name),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 128),
        children: [
          _detailHeader(
            title: name,
            eyebrow: 'PERFIL DEL ARTISTA',
            onBack: () => setState(() => _selectedArtist = null),
            onRefresh: _loadingOnline ? null : () => _refreshArtist(name),
          ),
          const SizedBox(height: 16),
          Center(
            child: _Artwork(
              player: widget.player,
              song: sample,
              artistName: name,
              size: 150,
              circular: true,
              icon: Icons.person_rounded,
            ),
          ),
          const SizedBox(height: 15),
          if (_artistCatalog?.name.toLowerCase() == name.toLowerCase() &&
              _artistCatalog?.fanCount != null) ...[
            const SizedBox(height: 6),
            Text(
              '${_formatFans(_artistCatalog!.fanCount!)} seguidores en Deezer',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
          if (_isArtists && _worldSongsForArtist(name).isNotEmpty) ...[
            const SizedBox(height: 22),
            _sectionHeading('Más escuchadas en 30 días', 'Tendencia global'),
            const SizedBox(height: 10),
            ..._worldSongsForArtist(name).map(_worldTrackTile),
          ],
          Text(
            '${localSongs.length} canciones en tu biblioteca',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 17),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: localSongs.isEmpty
                    ? null
                    : () => widget.player.playPlaylist(localSongs),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Reproducir'),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: 'Aleatorio',
                onPressed: localSongs.isEmpty
                    ? null
                    : () =>
                          widget.player.playPlaylist(localSongs, shuffle: true),
                icon: const Icon(Icons.shuffle_rounded),
              ),
            ],
          ),
          if (localSongs.isNotEmpty) ...[
            const SizedBox(height: 25),
            _sectionHeading('De tu biblioteca', 'Más escuchadas'),
            const SizedBox(height: 10),
            ..._orderedByListening(
              localSongs,
              learnedSongs,
            ).map(_localSongTile),
          ],
          const SizedBox(height: 24),
          _sectionHeading('Descubre en YouTube', 'Resultados de búsqueda'),
          const SizedBox(height: 5),
          const Text(
            'Son resultados actuales de búsqueda; YouTube no proporciona aquí un ranking oficial ni fechas verificadas.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 10),
          if (_loadingOnline)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: Colors.white),
              ),
            )
          else if (_artistResults.isNotEmpty)
            ..._artistResults.map(_onlineSongTile)
          else
            _message(
              Icons.search_rounded,
              _onlineError ?? 'Desliza para actualizar.',
            ),
        ],
      ),
    );
  }

  Widget _albumProfile(_MediaGroup album) {
    final songs = album.songs;
    return AnimatedBuilder(
      animation: widget.player,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 128),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Volver a álbumes',
                onPressed: () => setState(() => _selectedAlbum = null),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: Text(
                  album.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Reproducir aleatorio',
                onPressed: songs.isEmpty
                    ? null
                    : () => widget.player.playPlaylist(songs, shuffle: true),
                icon: const Icon(Icons.shuffle_rounded),
              ),
              IconButton(
                tooltip: 'Reproducir álbum',
                onPressed: songs.isEmpty
                    ? null
                    : () => widget.player.playPlaylist(songs),
                icon: const Icon(Icons.play_circle_fill_rounded, size: 30),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Center(
            child: _Artwork(
              player: widget.player,
              song: songs.first,
              size: 205,
              icon: Icons.album_rounded,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            album.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            '${album.subtitle} · ${_trackCount(songs.length)}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 22),
          ...songs.indexed.map(
            (entry) => _localSongTile(entry.$2, index: entry.$1),
          ),
          const SizedBox(height: 16),
          const Text(
            'Los álbumes de esta sección provienen de los archivos de música de tu dispositivo.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeading(String title, String detail) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      Text(detail, style: const TextStyle(color: AppColors.textSecondary)),
    ],
  );

  Widget _artistTile(_MediaGroup group) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Material(
      color: Colors.white.withValues(alpha: .05),
      borderRadius: BorderRadius.circular(25),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: _Artwork(
          player: widget.player,
          song: group.songs.first,
          artistName: group.title,
          size: 58,
          circular: true,
          icon: Icons.person_rounded,
        ),
        title: Text(
          group.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(_trackCount(group.songs.length)),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: Colors.white60,
        ),
        onTap: () => _openArtist(group.title),
      ),
    ),
  );

  Widget _albumGrid(List<_MediaGroup> groups) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: groups.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: 11,
      mainAxisSpacing: 12,
      childAspectRatio: .72,
    ),
    itemBuilder: (context, index) {
      final album = groups[index];
      return Material(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _selectedAlbum = album),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SizedBox.expand(
                    child: _Artwork(
                      player: widget.player,
                      song: album.songs.first,
                      size: null,
                      icon: Icons.album_rounded,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  album.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  album.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _trackCount(album.songs.length),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _discoveryTile(YouTubeSearchResult result) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Colors.white.withValues(alpha: .045),
      borderRadius: BorderRadius.circular(19),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Image.network(
            result.thumbnail,
            width: 50,
            height: 50,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox(
              width: 50,
              height: 50,
              child: Icon(Icons.music_note_rounded),
            ),
          ),
        ),
        title: Text(result.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          result.artist.isEmpty ? 'YouTube' : result.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          tooltip: 'Reproducir',
          onPressed: () => _playOnlineResult(result),
          icon: const Icon(Icons.play_circle_fill_rounded, size: 30),
        ),
        onTap: result.artist.isEmpty
            ? () => _playOnlineResult(result)
            : () => _openArtist(result.artist),
      ),
    ),
  );

  Future<void> _playOnlineResult(YouTubeSearchResult result) async {
    final ok = await widget.player.playOnline(result);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.player.playbackError ?? 'No se pudo reproducir.',
          ),
        ),
      );
    }
  }

  Widget _localSongTile(Song song, {int? index}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Colors.white.withValues(alpha: .04),
      borderRadius: BorderRadius.circular(19),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: _Artwork(
          player: widget.player,
          song: song,
          size: 48,
          icon: Icons.music_note_rounded,
        ),
        title: Text(
          song.title.isEmpty ? song.displayName : song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(
            isSongLiked(widget.player, song)
                ? Icons.favorite_rounded
                : Icons.more_vert_rounded,
            color: isSongLiked(widget.player, song)
                ? const Color(0xFFF43F5E)
                : Colors.white70,
          ),
          onSelected: (action) async {
            if (action == 'playlist') {
              await addSongToPlaylist(context, widget.player, song);
            } else if (action == 'like') {
              await toggleSongLiked(widget.player, song);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'playlist', child: Text('Añadir a playlist')),
            PopupMenuItem(value: 'like', child: Text('Me gusta')),
          ],
        ),
        onTap: () {
          final current =
              _selectedAlbum?.songs ??
              _songsForArtist(_selectedArtist ?? song.artist);
          final start =
              index ?? current.indexWhere((item) => item.id == song.id);
          widget.player.playPlaylist(
            current.isEmpty ? [song] : current,
            startIndex: start < 0 ? 0 : start,
          );
        },
      ),
    ),
  );

  Widget _onlineSongTile(YouTubeSearchResult result) {
    final song = Song.fromYouTube(result);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(19),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Image.network(
              result.thumbnail,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.music_note_rounded),
              ),
            ),
          ),
          title: Text(
            result.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            result.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'save') {
                await addSongToPlaylist(context, widget.player, song);
              } else if (value == 'like') {
                final liked = await toggleSongLiked(widget.player, song);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        liked ? 'Añadida a Me gusta' : 'Quitada de Me gusta',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'save', child: Text('Añadir a playlist')),
              PopupMenuItem(value: 'like', child: Text('Guardar en Me gusta')),
            ],
          ),
          onTap: () async {
            final ok = await widget.player.playOnline(result);
            if (!ok && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    widget.player.playbackError ?? 'No se pudo reproducir.',
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Widget _emptyPersonalHint() =>
      _message(Icons.headphones_rounded, 'Escucha música para conocerte');

  Widget _emptyLibrary() => _message(
    Icons.library_music_outlined,
    widget.songs.isEmpty
        ? 'No hay canciones locales. Tus recomendaciones personales aparecerán después de escuchar música.'
        : 'No hay coincidencias para “${widget.searchText}”.',
  );

  Widget _message(IconData icon, String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      children: [
        Icon(icon, size: 42, color: Colors.white38),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ],
    ),
  );

  Widget _detailHeader({
    required String title,
    required String eyebrow,
    required VoidCallback onBack,
    VoidCallback? onRefresh,
  }) => Row(
    children: [
      IconButton(
        tooltip: 'Volver a artistas',
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      const SizedBox(width: 4),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      if (onRefresh != null)
        IconButton(
          tooltip: 'Actualizar perfil',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
    ],
  );

  String _formatFans(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)} M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)} mil';
    return '$count';
  }

  List<Song> _songsForArtist(String artist) => widget.songs
      .where((song) => song.artist.toLowerCase() == artist.toLowerCase())
      .toList();

  List<MusicChartTrack> _worldSongsForArtist(String artist) {
    final monthlyArtist = _worldArtists.where(
      (entry) => entry.name.toLowerCase() == artist.toLowerCase(),
    );
    if (monthlyArtist.isNotEmpty && monthlyArtist.first.songs.isNotEmpty) {
      return monthlyArtist.first.songs;
    }
    return _worldChart
        .where((track) => track.artist.toLowerCase() == artist.toLowerCase())
        .take(10)
        .toList();
  }

  Widget _worldTrackTile(MusicChartTrack track) => Card(
    color: AppColors.card,
    margin: const EdgeInsets.only(bottom: 8),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      leading: SizedBox(
        width: 44,
        height: 44,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Image.network(
            track.artworkUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const ColoredBox(
              color: AppColors.surface,
              child: Icon(Icons.music_note_rounded, color: Colors.white70),
            ),
          ),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        'Tema #${track.rank} del artista en los últimos 30 días',
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: const Icon(Icons.play_circle_fill_rounded, size: 30),
      onTap: () => _playWorldTrack(track),
    ),
  );

  Future<void> _playWorldTrack(MusicChartTrack track) async {
    try {
      final results = await YouTubeAudioService.instance.search(
        '${track.title} ${track.artist} audio',
      );
      if (results.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No encontramos esta canción.')),
          );
        }
        return;
      }
      final title = track.title.toLowerCase();
      final match = results.where(
        (result) => result.title.toLowerCase().contains(title),
      );
      final selected = match.isEmpty ? results.first : match.first;
      final ok = await widget.player.playOnline(selected, playlist: results);
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo reproducir esta canción.')),
        );
      }
    }
  }

  List<Song> _orderedByListening(List<Song> songs, List<LearnedSong> learned) {
    final scores = {for (final item in learned) item.id: item.playCount};
    return List<Song>.from(songs)..sort(
      (a, b) => (scores[b.isOnline ? b.onlineVideoId : b.id.toString()] ?? 0)
          .compareTo(
            scores[a.isOnline ? a.onlineVideoId : a.id.toString()] ?? 0,
          ),
    );
  }

  List<_MediaGroup> _makeGroups(List<Song> songs) {
    final buckets = <String, List<Song>>{};
    final titles = <String, String>{};
    final subtitles = <String, String>{};
    final artistScores = {
      for (final artist in _topArtists) artist.name.toLowerCase(): artist.score,
    };

    for (final song in songs) {
      final artist = song.artist.trim().isEmpty || song.artist == '<unknown>'
          ? 'Artista desconocido'
          : song.artist.trim();
      final rawAlbum = song.album.trim();
      final album = rawAlbum.isEmpty || rawAlbum == '<unknown>'
          ? 'Álbum sin nombre'
          : rawAlbum;
      late final String key;
      late final String title;
      late final String subtitle;
      if (_isArtists) {
        key = 'artist:${artist.toLowerCase()}';
        title = artist;
        subtitle = 'Artista';
      } else {
        key = song.albumId != null && song.albumId! > 0
            ? 'album-id:${song.albumId}'
            : 'album:${album.toLowerCase()}|${artist.toLowerCase()}';
        title = album;
        subtitle = artist;
      }
      buckets.putIfAbsent(key, () => []).add(song);
      titles.putIfAbsent(key, () => title);
      subtitles.putIfAbsent(key, () => subtitle);
    }

    final groups = buckets.entries.map((entry) {
      final ordered = List<Song>.from(entry.value)
        ..sort(
          (a, b) => (a.title.isEmpty ? a.displayName : a.title)
              .toLowerCase()
              .compareTo(
                (b.title.isEmpty ? b.displayName : b.title).toLowerCase(),
              ),
        );
      return _MediaGroup(
        key: entry.key,
        title: titles[entry.key]!,
        subtitle: subtitles[entry.key]!,
        songs: ordered,
        score: artistScores[subtitles[entry.key]!.toLowerCase()] ?? 0,
      );
    }).toList();

    groups.sort((a, b) {
      if (!_isArtists && a.score != b.score) return b.score.compareTo(a.score);
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return groups;
  }

  String _trackCount(int count) =>
      '$count ${count == 1 ? 'canción' : 'canciones'}';
}

class _MediaGroup {
  const _MediaGroup({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.songs,
    required this.score,
  });

  final String key;
  final String title;
  final String subtitle;
  final List<Song> songs;
  final double score;
}

class _Artwork extends StatefulWidget {
  const _Artwork({
    required this.player,
    required this.song,
    required this.size,
    required this.icon,
    this.circular = false,
    this.artistName,
  });

  final MusicPlayerController player;
  final Song? song;
  final double? size;
  final IconData icon;
  final bool circular;
  final String? artistName;

  @override
  State<_Artwork> createState() => _ArtworkState();
}

class _ArtworkState extends State<_Artwork> {
  Future<Uint8List?>? _artworkFuture;
  Future<ArtistCatalogEntry?>? _artistFuture;

  @override
  void initState() {
    super.initState();
    _loadFutures();
  }

  @override
  void didUpdateWidget(covariant _Artwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song?.id != widget.song?.id ||
        oldWidget.artistName != widget.artistName) {
      _loadFutures();
    }
  }

  void _loadFutures() {
    _artworkFuture = widget.song == null
        ? null
        : widget.player.loadArtwork(widget.song!);
    _artistFuture = widget.artistName == null
        ? null
        : ArtistCatalogService.instance.lookup(widget.artistName!);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.artistName != null) {
      return FutureBuilder<ArtistCatalogEntry?>(
        future: _artistFuture,
        builder: (context, snapshot) {
          final portrait = snapshot.data;
          if (portrait == null) return _localArtwork();
          return ClipRRect(
            borderRadius: BorderRadius.circular(widget.circular ? 1000 : 15),
            child: Image.network(
              portrait.pictureUrl,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _localArtwork(),
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : _localArtwork(),
            ),
          );
        },
      );
    }
    return _localArtwork();
  }

  Widget _localArtwork() {
    if (_artworkFuture == null) return _placeholder();
    return FutureBuilder<Uint8List?>(
      future: _artworkFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return _placeholder();
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.circular ? 1000 : 15),
          child: Image.memory(
            bytes,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }

  Widget _placeholder() => Container(
    width: widget.size,
    height: widget.size,
    decoration: BoxDecoration(
      shape: widget.circular ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: widget.circular ? null : BorderRadius.circular(15),
      color: Colors.white.withValues(alpha: .07),
    ),
    child: Icon(
      widget.icon,
      size: (widget.size ?? 60) * .4,
      color: Colors.white54,
    ),
  );
}

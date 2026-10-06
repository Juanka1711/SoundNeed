import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../music_player.dart';
import '../player_navigation.dart';
import '../playlist_artwork.dart';
import '../playlist_actions.dart';
import '../playlist_manager.dart';
import '../services/youtube_audio_service.dart';
import '../services/artwork_palette.dart';
import '../widgets/soundneed_search_field.dart';
import '../widgets/section_spotlight.dart';
import '../widgets/soundneed_empty_state.dart';

class PlaylistsSection extends StatefulWidget {
  const PlaylistsSection({
    super.key,
    required this.player,
    required this.palette,
  });

  final MusicPlayerController player;
  final ArtworkPalette palette;

  @override
  State<PlaylistsSection> createState() => _PlaylistsSectionState();
}

class _PlaylistsSectionState extends State<PlaylistsSection> {
  final manager = PlaylistManager.instance;
  String? _selectedPlaylistId;
  bool _showLikedSongs = false;

  @override
  void initState() {
    super.initState();
    manager.initialize();
  }

  Future<void> _create() async {
    final playlist = await createPlaylistFromDialog(context);
    if (playlist != null && mounted) {
      setState(() {
        _selectedPlaylistId = playlist.id;
        _showLikedSongs = false;
      });
    }
  }

  Future<void> _rename(MusicPlaylist playlist) async {
    final name = await askPlaylistName(context, initialName: playlist.name);
    if (name != null) await manager.renamePlaylist(playlist.id, name);
  }

  Future<void> _delete(MusicPlaylist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar playlist'),
        content: Text('¿Eliminar “${playlist.name}”?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await manager.deletePlaylist(playlist.id);
      if (_selectedPlaylistId == playlist.id && mounted) {
        setState(() => _selectedPlaylistId = null);
      }
    }
  }

  void _openPlaylist(String id) {
    setState(() {
      _selectedPlaylistId = id;
      _showLikedSongs = false;
    });
  }

  void _openLikedSongs() {
    setState(() {
      _selectedPlaylistId = null;
      _showLikedSongs = true;
    });
  }

  void _showPlaylistLibrary() {
    setState(() {
      _selectedPlaylistId = null;
      _showLikedSongs = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showLikedSongs || _selectedPlaylistId != null) {
      return _PlaylistContents(
        key: ValueKey('${_showLikedSongs ? 'liked' : _selectedPlaylistId}'),
        player: widget.player,
        playlistId: _selectedPlaylistId,
        showLikedSongs: _showLikedSongs,
        onBack: _showPlaylistLibrary,
        onSelectLikedSongs: _openLikedSongs,
        onSelectPlaylist: _openPlaylist,
        onDeleted: _showPlaylistLibrary,
      );
    }

    return AnimatedBuilder(
      animation: Listenable.merge([manager, widget.player]),
      builder: (context, _) {
        final liked = _likedSongs();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            SectionSpotlight(
              eyebrow: 'TU MÚSICA',
              title: 'Tus playlists',
              subtitle:
                  '${manager.playlists.length + 1} colecciones listas para sonar',
              icon: Icons.queue_music_rounded,
              palette: widget.palette,
              action: IconButton.filledTonal(
                tooltip: 'Crear playlist',
                onPressed: _create,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  fixedSize: const Size(44, 44),
                ),
                icon: const Icon(Icons.add_rounded),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = (constraints.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 16,
                  children: [
                    SizedBox(
                      width: width,
                      child: _PlaylistTile(
                        player: widget.player,
                        title: 'Me gusta',
                        subtitle: _songCount(liked.length),
                        songs: liked,
                        icon: Icons.favorite_rounded,
                        color: const Color(0xFFF43F5E),
                        onTap: _openLikedSongs,
                      ),
                    ),
                    ...manager.playlists.map(
                      (playlist) => SizedBox(
                        width: width,
                        child: _PlaylistTile(
                          player: widget.player,
                          title: playlist.name,
                          subtitle: _songCount(playlist.songs.length),
                          songs: playlist.songs,
                          icon: Icons.queue_music_rounded,
                          onTap: () => _openPlaylist(playlist.id),
                          menu: PopupMenuButton<String>(
                            iconSize: 19,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 32,
                              height: 32,
                            ),
                            onSelected: (action) => action == 'rename'
                                ? _rename(playlist)
                                : _delete(playlist),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('Cambiar nombre'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Eliminar'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            if (manager.playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Text(
                  'Crea una playlist para organizar tu música.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60),
                ),
              ),
          ],
        );
      },
    );
  }

  List<Song> _likedSongs() {
    final result = <String, Song>{};
    for (final song in manager.likedSongs) {
      result[songKey(song)] = _canonical(song);
    }
    for (final song in widget.player.songs.where(widget.player.isFavorite)) {
      result.putIfAbsent(songKey(song), () => song);
    }
    return result.values.toList();
  }

  String _songCount(int count) =>
      'Playlist · $count ${count == 1 ? 'canción' : 'canciones'}';

  Song _canonical(Song song) {
    if (!song.isOnline) {
      for (final local in widget.player.songs) {
        if (songKey(local) == songKey(song)) return local;
      }
    }
    return song;
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required this.player,
    required this.title,
    required this.subtitle,
    required this.songs,
    required this.icon,
    required this.onTap,
    this.color,
    this.menu,
  });

  final MusicPlayerController player;
  final String title;
  final String subtitle;
  final List<Song> songs;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? const Color(0xFF8B5CF6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: const Color(0xFF1D1D2B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: accent.withValues(alpha: .22)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: PlaylistArtwork(
                    player: player,
                    songs: songs,
                    icon: icon,
                    accent: accent,
                  ),
                ),
                if (songs.isEmpty)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            accent.withValues(alpha: .75),
                            const Color(0xFF151522),
                          ],
                        ),
                      ),
                      child: Icon(icon, color: Colors.white, size: 42),
                    ),
                  ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: menu == null
                      ? const SizedBox.shrink()
                      : Material(
                          color: const Color(0xAA0B0B12),
                          shape: const CircleBorder(),
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: Center(child: menu),
                          ),
                        ),
                ),
                if (songs.isNotEmpty)
                  Positioned(
                    right: 9,
                    bottom: 9,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: accent,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 9),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
      ],
    );
  }
}

class _PlaylistContents extends StatefulWidget {
  const _PlaylistContents({
    super.key,
    required this.player,
    required this.showLikedSongs,
    required this.onBack,
    required this.onSelectLikedSongs,
    required this.onSelectPlaylist,
    required this.onDeleted,
    this.playlistId,
  });

  final MusicPlayerController player;
  final String? playlistId;
  final bool showLikedSongs;
  final VoidCallback onBack;
  final VoidCallback onSelectLikedSongs;
  final ValueChanged<String> onSelectPlaylist;
  final VoidCallback onDeleted;

  @override
  State<_PlaylistContents> createState() => _PlaylistContentsState();
}

class _PlaylistContentsState extends State<_PlaylistContents> {
  final TextEditingController _searchController = TextEditingController();
  final Map<String, String> _lookedUpArtists = {};
  final Set<String> _artistLookupsStarted = {};
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _addSongs(MusicPlaylist? playlist) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF151522),
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => _PlaylistSongPicker(
        player: widget.player,
        playlist: playlist,
        showLikedSongs: widget.showLikedSongs,
      ),
    );
  }

  Future<void> _rename(MusicPlaylist playlist) async {
    final name = await askPlaylistName(context, initialName: playlist.name);
    if (name != null) {
      await PlaylistManager.instance.renamePlaylist(playlist.id, name);
    }
  }

  Future<void> _delete(MusicPlaylist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar playlist'),
        content: Text('¿Eliminar “${playlist.name}”?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await PlaylistManager.instance.deletePlaylist(playlist.id);
      widget.onDeleted();
    }
  }

  Future<void> _downloadPlaylist(List<Song> songs) async {
    final failures = await widget.player.downloadPlaylist(songs);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failures == 0
              ? 'Descarga de la playlist completada.'
              : 'Playlist descargada con $failures ${failures == 1 ? 'error' : 'errores'}.',
        ),
      ),
    );
  }

  void _scheduleArtistLookups(List<Song> songs) {
    final pending = songs.where((song) {
      final key = songKey(song);
      return song.artist == 'Artista desconocido' &&
          !_lookedUpArtists.containsKey(key) &&
          _artistLookupsStarted.add(key);
    }).toList();
    if (pending.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final song in pending) {
        unawaited(_lookupArtist(song));
      }
    });
  }

  Future<void> _lookupArtist(Song song) async {
    final key = songKey(song);
    try {
      final results = await YouTubeAudioService.instance.search(song.title);
      final queryWords = _artistLookupWords(song.title);
      YouTubeSearchResult? best;
      var bestScore = 0.0;
      for (final result in results) {
        final resultWords = _artistLookupWords(result.title);
        if (queryWords.isEmpty || resultWords.isEmpty) continue;
        final overlap = queryWords.intersection(resultWords).length;
        final score = overlap / queryWords.length;
        if (score > bestScore) {
          best = result;
          bestScore = score;
        }
      }
      if (best == null || bestScore < .65) return;

      final metadata = await YouTubeAudioService.instance.getVideoMetadata(
        best.videoId,
      );
      final artist = metadata['artist']?.trim().isNotEmpty == true
          ? metadata['artist']!.trim()
          : best.artist.trim();
      if (artist.isEmpty ||
          artist.toLowerCase() == 'youtube' ||
          artist.toLowerCase() == '<unknown>') {
        return;
      }
      if (mounted) setState(() => _lookedUpArtists[key] = artist);
    } catch (error) {
      debugPrint(
        '[SoundNeed] No se pudo recuperar el artista de ${song.title}: $error',
      );
    }
  }

  Set<String> _artistLookupWords(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[_–—|•]'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9áéíóúüñ ]'), '')
      .split(RegExp(r'\s+'))
      .where((word) => word.length > 1)
      .toSet();

  @override
  Widget build(BuildContext context) {
    final manager = PlaylistManager.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([manager, widget.player]),
      builder: (context, _) {
        final playlist = widget.playlistId == null
            ? null
            : manager.findPlaylist(widget.playlistId!);
        final songs = widget.showLikedSongs
            ? _likedSongs(manager)
            : (playlist?.songs ?? const <Song>[]);
        _scheduleArtistLookups(songs);
        final title = widget.showLikedSongs
            ? 'Me gusta'
            : (playlist?.name ?? 'Playlist');
        final filteredSongs = _query.trim().isEmpty
            ? songs
            : songs.where((song) {
                final query = _query.toLowerCase();
                return song.title.toLowerCase().contains(query) ||
                    song.displayName.toLowerCase().contains(query) ||
                    song.artist.toLowerCase().contains(query);
              }).toList();
        final totalDuration = songs.fold<int>(
          0,
          (total, song) => total + song.duration,
        );
        final accent = widget.showLikedSongs
            ? const Color(0xFFF43F5E)
            : const Color(0xFF8B5CF6);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 128),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Volver a playlists',
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded, size: 27),
                ),
                const Spacer(),
                if (playlist != null)
                  PopupMenuButton<String>(
                    onSelected: (action) {
                      if (action == 'rename') _rename(playlist);
                      if (action == 'delete') _delete(playlist);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'rename',
                        child: Text('Cambiar nombre'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Eliminar playlist'),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 5),
            SoundNeedSearchField(
              controller: _searchController,
              hintText: 'Buscar en la playlist',
              height: 56,
              onChanged: (value) => setState(() => _query = value),
              suffix: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      style: IconButton.styleFrom(
                        foregroundColor: Colors.white70,
                        fixedSize: const Size(34, 34),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
            ),
            if (_query.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${filteredSongs.length} ${filteredSongs.length == 1 ? 'resultado' : 'resultados'}',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
            const SizedBox(height: 19),
            Center(
              child: Container(
                width: (MediaQuery.sizeOf(context).width - 48)
                    .clamp(260.0, 440.0)
                    .toDouble(),
                height: (MediaQuery.sizeOf(context).width - 48)
                    .clamp(260.0, 440.0)
                    .toDouble(),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: accent.withValues(alpha: .25)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: PlaylistArtwork(
                    player: widget.player,
                    songs: songs,
                    icon: widget.showLikedSongs
                        ? Icons.favorite_rounded
                        : Icons.queue_music_rounded,
                    accent: accent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 19),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 30,
                height: 1.05,
                fontWeight: FontWeight.w900,
                letterSpacing: -.6,
              ),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: accent.withValues(alpha: .22),
                  child: Icon(
                    widget.showLikedSongs
                        ? Icons.favorite_rounded
                        : Icons.person_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.showLikedSongs
                      ? 'Tus canciones favoritas'
                      : 'Tu playlist',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('·', style: TextStyle(color: Colors.white54)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${songs.length} ${songs.length == 1 ? 'canción' : 'canciones'} · ${_formatDuration(totalDuration)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _addSongs(playlist),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Agregar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: .16),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Builder(
                  builder: (context) {
                    final downloadableCount = songs
                        .where(
                          (song) =>
                              song.isOnline ||
                              song.isPodcast ||
                              song.uri.startsWith('http://') ||
                              song.uri.startsWith('https://'),
                        )
                        .length;
                    final isDownloading = widget.player.isDownloadingPlaylist;
                    final progress = widget.player.playlistDownloadProgress;
                    return IconButton.filledTonal(
                      tooltip: isDownloading
                          ? 'Descargando ${widget.player.playlistDownloadFinished >= widget.player.playlistDownloadTotal ? widget.player.playlistDownloadTotal : widget.player.playlistDownloadFinished + 1}/${widget.player.playlistDownloadTotal}'
                          : 'Descargar playlist',
                      onPressed:
                          songs.isEmpty ||
                              downloadableCount == 0 ||
                              isDownloading ||
                              widget.player.isDownloading
                          ? null
                          : () => _downloadPlaylist(songs),
                      style: IconButton.styleFrom(
                        fixedSize: const Size(50, 50),
                        foregroundColor: accent,
                      ),
                      icon: SizedBox(
                        width: 27,
                        height: 27,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (isDownloading)
                              SizedBox.expand(
                                child: CircularProgressIndicator(
                                  value: progress,
                                  strokeWidth: 2.5,
                                  color: accent,
                                  backgroundColor: accent.withValues(
                                    alpha: .18,
                                  ),
                                ),
                              ),
                            Icon(
                              isDownloading
                                  ? Icons.downloading_rounded
                                  : Icons.download_rounded,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  tooltip: 'Reproducir todo',
                  onPressed: songs.isEmpty
                      ? null
                      : () => widget.player.playPlaylist(songs),
                  style: IconButton.styleFrom(
                    fixedSize: const Size(58, 58),
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF11111A),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 34),
                ),
              ],
            ),
            const SizedBox(height: 19),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _PlaylistBubble(
                    label: 'Todas',
                    icon: Icons.library_music_rounded,
                    selected: false,
                    onTap: widget.onBack,
                  ),
                  _PlaylistBubble(
                    label: 'Me gusta',
                    icon: Icons.favorite_rounded,
                    selected: widget.showLikedSongs,
                    onTap: widget.onSelectLikedSongs,
                  ),
                  ...manager.playlists.map(
                    (item) => _PlaylistBubble(
                      label: item.name,
                      icon: Icons.playlist_play_rounded,
                      selected:
                          !widget.showLikedSongs &&
                          item.id == widget.playlistId,
                      onTap: () => widget.onSelectPlaylist(item.id),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 17),
            if (filteredSongs.isEmpty)
              SoundNeedEmptyState(
                icon: _query.isNotEmpty
                    ? Icons.search_off_rounded
                    : widget.showLikedSongs
                    ? Icons.favorite_border_rounded
                    : Icons.queue_music_rounded,
                title: _query.isNotEmpty
                    ? 'Sin coincidencias'
                    : widget.showLikedSongs
                    ? 'Tu colección empieza aquí'
                    : 'Esta playlist está vacía',
                message: _query.isNotEmpty
                    ? 'Prueba buscar por otro título o artista.'
                    : widget.showLikedSongs
                    ? 'Las canciones que marques con Me gusta aparecerán aquí.'
                    : 'Agrega canciones y crea una lista para cada momento.',
                accent: accent,
              )
            else
              ...filteredSongs.map((song) {
                final index = songs.indexOf(song);
                final current = widget.player.currentSong?.id == song.id;
                return Padding(
                  key: ValueKey(songKey(song)),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: const Color(0xFF171720),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                      side: BorderSide(
                        color: current
                            ? accent.withValues(alpha: .55)
                            : Colors.white.withValues(alpha: .06),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      minVerticalPadding: 10,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 2,
                      ),
                      leading: _SongArtwork(
                        player: widget.player,
                        song: song,
                        active: current,
                      ),
                      title: Text(
                        song.title.isEmpty ? song.displayName : song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        _lookedUpArtists[songKey(song)] ??
                            (song.artist == 'Artista desconocido' &&
                                    _artistLookupsStarted.contains(
                                      songKey(song),
                                    )
                                ? 'Buscando artista…'
                                : song.artist),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        if (current) {
                          selectSongOrOpenPlayer(context, widget.player, song);
                        } else {
                          widget.player.playPlaylist(songs, startIndex: index);
                        }
                      },
                      trailing: IconButton(
                        tooltip: widget.showLikedSongs
                            ? 'Quitar de Me gusta'
                            : 'Quitar de playlist',
                        icon: Icon(
                          widget.showLikedSongs
                              ? Icons.favorite
                              : Icons.remove_circle_outline,
                          color: widget.showLikedSongs
                              ? const Color(0xFFF43F5E)
                              : Colors.white70,
                        ),
                        onPressed: () async {
                          if (widget.showLikedSongs) {
                            await setSongLiked(widget.player, song, false);
                          } else if (playlist != null) {
                            await manager.removeSong(playlist.id, song);
                          }
                        },
                      ),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  List<Song> _likedSongs(PlaylistManager manager) {
    final songs = <String, Song>{};
    for (final song in manager.likedSongs) {
      songs[songKey(song)] = song;
    }
    for (final song in widget.player.songs.where(widget.player.isFavorite)) {
      songs.putIfAbsent(songKey(song), () => song);
    }
    return songs.values.toList();
  }

  String _formatDuration(int milliseconds) {
    if (milliseconds <= 0) return '0 min';
    final minutes = (milliseconds / 60000).round();
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return hours > 0 ? '$hours h $remainder min' : '$minutes min';
  }
}

class _PlaylistSongPicker extends StatefulWidget {
  const _PlaylistSongPicker({
    required this.player,
    required this.showLikedSongs,
    this.playlist,
  });

  final MusicPlayerController player;
  final MusicPlaylist? playlist;
  final bool showLikedSongs;

  @override
  State<_PlaylistSongPicker> createState() => _PlaylistSongPickerState();
}

class _PlaylistSongPickerState extends State<_PlaylistSongPicker> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _searching = false;
  List<YouTubeSearchResult> _onlineResults = const [];
  String? _searchError;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    setState(() {
      _query = value;
      _onlineResults = const [];
      _searchError = null;
      _searching = query.length >= 2;
    });
    if (query.length < 2) {
      setState(() => _searching = false);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () {
      _searchOnline(query);
    });
  }

  Future<void> _searchOnline(String query) async {
    try {
      final results = await YouTubeAudioService.instance.search(query);
      if (!mounted || query != _query.trim()) return;
      setState(() {
        _onlineResults = results;
        _searching = false;
        _searchError = results.isEmpty
            ? YouTubeAudioService.instance.lastError
            : null;
      });
    } catch (_) {
      if (!mounted || query != _query.trim()) return;
      setState(() {
        _searching = false;
        _searchError = 'No se pudo completar la búsqueda. Intenta de nuevo.';
      });
    }
  }

  Set<String> get _existingKeys {
    final manager = PlaylistManager.instance;
    final existing = widget.showLikedSongs
        ? <Song>[
            ...manager.likedSongs,
            ...widget.player.songs.where(widget.player.isFavorite),
          ]
        : (manager.findPlaylist(widget.playlist!.id)?.songs ?? const <Song>[]);
    return existing.map(songKey).toSet();
  }

  List<Song> get _localResults {
    final existing = _existingKeys;
    final query = _query.trim().toLowerCase();
    return widget.player.songs.where((song) {
      if (existing.contains(songKey(song))) return false;
      if (query.isEmpty) return true;
      return song.title.toLowerCase().contains(query) ||
          song.displayName.toLowerCase().contains(query) ||
          song.artist.toLowerCase().contains(query) ||
          song.album.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _addSong(Song song) async {
    final manager = PlaylistManager.instance;
    var added = false;
    if (widget.showLikedSongs) {
      await setSongLiked(widget.player, song, true);
      added = true;
    } else {
      added = await manager.addSong(widget.playlist!.id, song);
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added
              ? widget.showLikedSongs
                    ? 'Añadida a Me gusta'
                    : 'Añadida a ${widget.playlist!.name}'
              : 'La canción ya está en esta lista',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localSongs = _localResults;
    final onlineSongs = _onlineResults
        .map(Song.fromYouTube)
        .where((song) => !_existingKeys.contains(songKey(song)))
        .toList();
    final entries = <_SongPickerEntry>[];
    if (_query.trim().isEmpty) {
      if (localSongs.isNotEmpty) {
        entries.add(const _SongPickerEntry.section('Tu música'));
        entries.addAll(localSongs.map(_SongPickerEntry.song));
      } else {
        entries.add(
          const _SongPickerEntry.message(
            'Busca una canción o artista. También puedes agregar música de YouTube sin descargarla.',
          ),
        );
      }
    } else {
      if (localSongs.isNotEmpty) {
        entries.add(const _SongPickerEntry.section('En tu teléfono'));
        entries.addAll(localSongs.map(_SongPickerEntry.song));
      }
      if (_searching) {
        entries.add(const _SongPickerEntry.section('Buscando en YouTube…'));
      } else if (onlineSongs.isNotEmpty) {
        entries.add(const _SongPickerEntry.section('En YouTube'));
        entries.addAll(onlineSongs.map(_SongPickerEntry.song));
      } else if (!_searching && _query.trim().length >= 2) {
        entries.add(
          _SongPickerEntry.message(
            _searchError == null
                ? 'No encontramos resultados. Prueba con otro título o artista.'
                : 'La búsqueda en línea no está disponible ahora. ${_searchError!}',
          ),
        );
      }
    }

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .82,
      child: Column(
        children: [
          const SizedBox(height: 11),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 17, 12, 13),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.showLikedSongs
                        ? 'Agregar a Me gusta'
                        : 'Agregar a ${widget.playlist!.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: SoundNeedSearchField(
              controller: _searchController,
              hintText: 'Canción o artista',
              onChanged: _onQueryChanged,
              suffix: _searching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white70,
                        strokeWidth: 2,
                      ),
                    )
                  : _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpiar búsqueda',
                      onPressed: () {
                        _searchController.clear();
                        _onQueryChanged('');
                      },
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                if (entry.label != null) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 15, 20, 7),
                    child: Text(
                      entry.label!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .65),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }
                final song = entry.value;
                if (song == null) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(24, 26, 24, 16),
                    child: Center(
                      child: _searching
                          ? const CircularProgressIndicator(
                              color: Color(0xFF8B5CF6),
                            )
                          : Text(
                              entry.message!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white60),
                            ),
                    ),
                  );
                }
                return ListTile(
                  leading: _SongArtwork(
                    player: widget.player,
                    song: song,
                    active: false,
                  ),
                  title: Text(
                    song.title.isEmpty ? song.displayName : song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    song.isOnline ? 'YouTube · ${song.artist}' : song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.add_circle_outline_rounded),
                  onTap: () => _addSong(song),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SongPickerEntry {
  const _SongPickerEntry.section(this.label) : value = null, message = null;
  const _SongPickerEntry.song(this.value) : label = null, message = null;
  const _SongPickerEntry.message(this.message) : label = null, value = null;

  final String? label;
  final Song? value;
  final String? message;
}

class _PlaylistBubble extends StatelessWidget {
  const _PlaylistBubble({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? Colors.white : const Color(0xFF151522),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: .10),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.black : Colors.white70,
              ),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.black : Colors.white70,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SongArtwork extends StatefulWidget {
  const _SongArtwork({
    required this.player,
    required this.song,
    required this.active,
  });

  final MusicPlayerController player;
  final Song song;
  final bool active;

  @override
  State<_SongArtwork> createState() => _SongArtworkState();
}

class _SongArtworkState extends State<_SongArtwork> {
  late Future<Uint8List?> _artworkFuture;
  late int _artworkRevision;

  @override
  void initState() {
    super.initState();
    _artworkRevision = widget.player.artworkRevision;
    widget.player.addListener(_onPlayerChanged);
    _artworkFuture = widget.player.loadArtwork(widget.song);
  }

  @override
  void didUpdateWidget(covariant _SongArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      oldWidget.player.removeListener(_onPlayerChanged);
      widget.player.addListener(_onPlayerChanged);
      _artworkRevision = widget.player.artworkRevision;
    }
    if (oldWidget.player != widget.player ||
        songKey(oldWidget.song) != songKey(widget.song)) {
      _artworkFuture = widget.player.loadArtwork(widget.song);
    }
  }

  void _onPlayerChanged() {
    if (_artworkRevision == widget.player.artworkRevision) return;
    _artworkRevision = widget.player.artworkRevision;
    if (!mounted) return;
    setState(() {
      _artworkFuture = widget.player.loadArtwork(widget.song);
    });
  }

  @override
  void dispose() {
    widget.player.removeListener(_onPlayerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _artworkFuture,
    builder: (context, snapshot) {
      final artwork = snapshot.data;
      return Container(
        width: 50,
        height: 50,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF292936),
          borderRadius: BorderRadius.circular(10),
        ),
        child: artwork == null
            ? Icon(
                widget.active ? Icons.equalizer : Icons.music_note_rounded,
                color: Colors.white70,
              )
            : Image.memory(artwork, fit: BoxFit.cover),
      );
    },
  );
}

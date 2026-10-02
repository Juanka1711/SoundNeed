import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../music_player.dart';
import '../playlist_actions.dart';
import '../playlist_manager.dart';

class PlaylistsSection extends StatefulWidget {
  const PlaylistsSection({super.key, required this.player});

  final MusicPlayerController player;

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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
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
        player: widget.player,
        playlistId: _selectedPlaylistId,
        showLikedSongs: _showLikedSongs,
        onBack: _showPlaylistLibrary,
        onSelectLikedSongs: _openLikedSongs,
        onSelectPlaylist: _openPlaylist,
      );
    }

    return AnimatedBuilder(
      animation: Listenable.merge([manager, widget.player]),
      builder: (context, _) {
        final liked = _likedSongs();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(children: [
              const Expanded(child: Text('Tus playlists', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold))),
              IconButton(tooltip: 'Crear playlist', onPressed: _create, icon: const Icon(Icons.add_circle_outline, size: 28)),
            ]),
            const SizedBox(height: 10),
            _PlaylistTile(
              title: 'Me gusta',
              subtitle: _songCount(liked.length),
              icon: Icons.favorite,
              color: const Color(0xFFF43F5E),
              onTap: _openLikedSongs,
            ),
            ...manager.playlists.map((playlist) => _PlaylistTile(
                  title: playlist.name,
                  subtitle: _songCount(playlist.songs.length),
                  icon: Icons.playlist_play_rounded,
                  onTap: () => _openPlaylist(playlist.id),
                  menu: PopupMenuButton<String>(
                    onSelected: (action) => action == 'rename' ? _rename(playlist) : _delete(playlist),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('Cambiar nombre')),
                      PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                    ],
                  ),
                )),
            if (manager.playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Text('Crea una playlist para organizar tu música.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
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
  const _PlaylistTile({required this.title, required this.subtitle, required this.icon, required this.onTap, this.color, this.menu});

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? const Color(0xFF8B5CF6);
    return Card(
      color: const Color(0xFF1D1D2B),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(30),
        side: BorderSide(color: Colors.white.withOpacity(.07)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minVerticalPadding: 12,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        onTap: onTap,
        leading: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent.withOpacity(.9), accent.withOpacity(.42)],
            ),
          ),
          child: Icon(icon, color: Colors.white, size: 30),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ),
        trailing: menu ?? const Icon(Icons.chevron_right_rounded, color: Colors.white70),
      ),
    );
  }
}

class _PlaylistContents extends StatelessWidget {
  const _PlaylistContents({
    required this.player,
    required this.showLikedSongs,
    required this.onBack,
    required this.onSelectLikedSongs,
    required this.onSelectPlaylist,
    this.playlistId,
  });

  final MusicPlayerController player;
  final String? playlistId;
  final bool showLikedSongs;
  final VoidCallback onBack;
  final VoidCallback onSelectLikedSongs;
  final ValueChanged<String> onSelectPlaylist;

  @override
  Widget build(BuildContext context) {
    final manager = PlaylistManager.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([manager, player]),
      builder: (context, _) {
        final playlist = playlistId == null ? null : manager.findPlaylist(playlistId!);
        final songs = showLikedSongs ? _likedSongs(manager) : (playlist?.songs ?? const <Song>[]);
        final title = showLikedSongs ? 'Me gusta' : (playlist?.name ?? 'Playlist');
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
          children: [
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                    Text('${songs.length} ${songs.length == 1 ? 'canción' : 'canciones'}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Reproducir aleatorio',
                onPressed: songs.isEmpty ? null : () => player.playPlaylist(songs, shuffle: true),
                icon: const Icon(Icons.shuffle_rounded),
              ),
              IconButton(
                tooltip: 'Reproducir todo',
                onPressed: songs.isEmpty ? null : () => player.playPlaylist(songs),
                icon: const Icon(Icons.play_circle_fill_rounded, size: 30),
              ),
            ]),
            const SizedBox(height: 4),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _PlaylistBubble(
                    label: 'Todas',
                    icon: Icons.library_music_rounded,
                    selected: false,
                    onTap: onBack,
                  ),
                  _PlaylistBubble(
                    label: 'Me gusta',
                    icon: Icons.favorite_rounded,
                    selected: showLikedSongs,
                    onTap: onSelectLikedSongs,
                  ),
                  ...manager.playlists.map((item) => _PlaylistBubble(
                        label: item.name,
                        icon: Icons.playlist_play_rounded,
                        selected: !showLikedSongs && item.id == playlistId,
                        onTap: () => onSelectPlaylist(item.id),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (songs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 34),
                child: Text(
                  showLikedSongs ? 'Las canciones que marques con el corazón aparecerán aquí.' : 'Añade canciones desde el reproductor para llenar esta playlist.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60),
                ),
              )
            else
              ...songs.map((song) {
                final index = songs.indexOf(song);
                final current = player.currentSong?.id == song.id;
                return Padding(
                  key: ValueKey(songKey(song)),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: Colors.white.withOpacity(.055),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                      side: BorderSide(color: current ? Theme.of(context).colorScheme.primary.withOpacity(.55) : Colors.white.withOpacity(.07)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      minVerticalPadding: 10,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      leading: _SongArtwork(player: player, song: song, active: current),
                      title: Text(song.title.isEmpty ? song.displayName : song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(song.artist == '<unknown>' || song.artist.isEmpty ? 'Artista desconocido' : song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => player.playPlaylist(songs, startIndex: index),
                      trailing: IconButton(
                        tooltip: showLikedSongs ? 'Quitar de Me gusta' : 'Quitar de playlist',
                        icon: Icon(showLikedSongs ? Icons.favorite : Icons.remove_circle_outline, color: showLikedSongs ? const Color(0xFFF43F5E) : Colors.white70),
                        onPressed: () async {
                          if (showLikedSongs) {
                            await player.toggleFavorite(song);
                            await manager.setLikedSong(song, false);
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
    for (final song in player.songs.where(player.isFavorite)) {
      songs.putIfAbsent(songKey(song), () => song);
    }
    return songs.values.toList();
  }
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
                  color: selected ? Colors.white : Colors.white.withOpacity(.10),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: selected ? Colors.black : Colors.white70),
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
  const _SongArtwork({required this.player, required this.song, required this.active});

  final MusicPlayerController player;
  final Song song;
  final bool active;

  @override
  State<_SongArtwork> createState() => _SongArtworkState();
}

class _SongArtworkState extends State<_SongArtwork> {
  late Future<Uint8List?> _artworkFuture;

  @override
  void initState() {
    super.initState();
    _artworkFuture = widget.player.loadArtwork(widget.song);
  }

  @override
  void didUpdateWidget(covariant _SongArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (songKey(oldWidget.song) != songKey(widget.song)) {
      _artworkFuture = widget.player.loadArtwork(widget.song);
    }
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
            decoration: BoxDecoration(color: const Color(0xFF292936), borderRadius: BorderRadius.circular(10)),
            child: artwork == null
                ? Icon(widget.active ? Icons.equalizer : Icons.music_note_rounded, color: Colors.white70)
                : Image.memory(artwork, fit: BoxFit.cover),
          );
        },
      );
}

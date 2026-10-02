import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../music_player.dart';

enum MediaCollectionKind { artists, albums }

class MediaCollectionSection extends StatefulWidget {
  const MediaCollectionSection({
    super.key,
    required this.player,
    required this.songs,
    required this.kind,
    this.searchText = '',
  });

  final MusicPlayerController player;
  final List<Song> songs;
  final MediaCollectionKind kind;
  final String searchText;

  @override
  State<MediaCollectionSection> createState() =>
      _MediaCollectionSectionState();
}

class _MediaCollectionSectionState extends State<MediaCollectionSection> {
  String? _selectedGroupKey;

  bool get _isArtist => widget.kind == MediaCollectionKind.artists;
  String get _sectionTitle => _isArtist ? 'Artistas' : 'Álbumes';
  IconData get _sectionIcon =>
      _isArtist ? Icons.person_outline_rounded : Icons.album_outlined;

  @override
  Widget build(BuildContext context) {
    final groups = _makeGroups(widget.songs);
    final selected = groups.where((group) => group.key == _selectedGroupKey);
    if (_selectedGroupKey != null && selected.isNotEmpty) {
      return _buildGroupDetail(selected.first);
    }
    if (_selectedGroupKey != null && selected.isEmpty) {
      _selectedGroupKey = null;
    }

    if (widget.player.loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (widget.player.permissionDenied) {
      return _buildMessage(
        Icons.lock_outline_rounded,
        'Permiso necesario',
        'SoundNeed necesita permiso para leer la música del dispositivo.',
        button: 'Conceder permiso',
      );
    }
    if (widget.player.songs.isEmpty) {
      return _buildMessage(
        Icons.music_off_rounded,
        'No hay música',
        'Agrega archivos de música al dispositivo y actualiza la biblioteca.',
        button: 'Actualizar',
      );
    }
    if (groups.isEmpty) {
      return _buildMessage(
        Icons.search_off_rounded,
        'No encontramos ${_isArtist ? 'artistas' : 'álbumes'}',
        widget.searchText.isEmpty
            ? 'No hay información suficiente para mostrar esta sección.'
            : 'No hay coincidencias para “${widget.searchText}”.',
      );
    }

    return RefreshIndicator(
      color: Colors.white,
      backgroundColor: AppColors.card,
      onRefresh: widget.player.loadSongs,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _isArtist ? 'Tus artistas' : 'Tus álbumes',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${groups.length}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (_isArtist)
            ...groups.map(_buildArtistTile)
          else
            _buildAlbumGrid(groups),
        ],
      ),
    );
  }

  Widget _buildArtistTile(_MediaGroup group) {
    final sample = group.songs.first;
    return Padding(
      key: ValueKey(group.key),
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white.withOpacity(.045),
        borderRadius: BorderRadius.circular(26),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
          leading: _CollectionArtwork(
            player: widget.player,
            song: sample,
            circular: true,
            size: 58,
          ),
          title: Text(
            group.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(_trackCount(group.songs.length)),
          trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white60),
          onTap: () => setState(() => _selectedGroupKey = group.key),
        ),
      ),
    );
  }

  Widget _buildAlbumGrid(List<_MediaGroup> groups) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: groups.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: .76,
        ),
        itemBuilder: (context, index) {
          final group = groups[index];
          return Material(
            key: ValueKey(group.key),
            color: Colors.white.withOpacity(.045),
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => setState(() => _selectedGroupKey = group.key),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SizedBox.expand(
                        child: _CollectionArtwork(
                          player: widget.player,
                          song: group.songs.first,
                          size: null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      group.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      group.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _trackCount(group.songs.length),
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

  Widget _buildGroupDetail(_MediaGroup group) => AnimatedBuilder(
        animation: widget.player,
        builder: (context, _) {
          final songs = group.songs;
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
            children: [
              Row(
                children: [
                  _BubbleAction(
                    label: _sectionTitle,
                    icon: _sectionIcon,
                    onTap: () => setState(() => _selectedGroupKey = null),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Reproducir aleatorio',
                    onPressed: songs.isEmpty
                        ? null
                        : () => widget.player.playPlaylist(songs, shuffle: true),
                    icon: const Icon(Icons.shuffle_rounded),
                  ),
                  IconButton(
                    tooltip: 'Reproducir todo',
                    onPressed: songs.isEmpty
                        ? null
                        : () => widget.player.playPlaylist(songs),
                    icon: const Icon(Icons.play_circle_fill_rounded, size: 30),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Center(
                child: _CollectionArtwork(
                  player: widget.player,
                  song: songs.first,
                  circular: _isArtist,
                  size: 174,
                  placeholderIcon: _isArtist
                      ? Icons.person_rounded
                      : Icons.album_rounded,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                group.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Text(
                '${_isArtist ? 'Artista' : group.subtitle} · ${_trackCount(songs.length)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              ...songs.indexed.map((entry) {
                final index = entry.$1;
                final song = entry.$2;
                final isCurrent = widget.player.currentSong?.id == song.id;
                return Padding(
                  key: ValueKey('track:${song.id}:${song.uri}'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: isCurrent
                        ? Colors.white.withOpacity(.085)
                        : Colors.white.withOpacity(.035),
                    borderRadius: BorderRadius.circular(20),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      leading: _CollectionArtwork(
                        player: widget.player,
                        song: song,
                        size: 48,
                      ),
                      title: Text(
                        song.title.isEmpty ? song.displayName : song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                          color: isCurrent ? Theme.of(context).colorScheme.primary : Colors.white,
                        ),
                      ),
                      subtitle: Text(
                        song.artist == '<unknown>' || song.artist.isEmpty
                            ? 'Artista desconocido'
                            : song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        widget.player.formatDuration(song.duration),
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      onTap: () => widget.player.playPlaylist(songs, startIndex: index),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      );

  Widget _buildMessage(
    IconData icon,
    String title,
    String message, {
    String? button,
  }) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 68, color: Colors.white38),
              const SizedBox(height: 16),
              Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
              if (button != null) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: widget.player.loadSongs,
                  icon: Icon(_sectionIcon),
                  label: Text(button),
                ),
              ],
            ],
          ),
        ),
      );

  List<_MediaGroup> _makeGroups(List<Song> songs) {
    final buckets = <String, List<Song>>{};
    final titles = <String, String>{};
    final subtitles = <String, String>{};

    for (final song in songs) {
      final rawArtist = song.artist.trim();
      final artist = rawArtist.isEmpty || rawArtist == '<unknown>'
          ? 'Artista desconocido'
          : rawArtist;
      final rawAlbum = song.album.trim();
      final album = rawAlbum.isEmpty || rawAlbum == '<unknown>'
          ? 'Álbum sin nombre'
          : rawAlbum;
      final normalizedArtist = artist.toLowerCase();

      late final String key;
      late final String title;
      late final String subtitle;
      if (_isArtist) {
        key = 'artist:$normalizedArtist';
        title = artist;
        subtitle = 'Artista';
      } else {
        key = song.albumId != null && song.albumId! > 0
            ? 'album-id:${song.albumId}'
            : 'album:${album.toLowerCase()}|$normalizedArtist';
        title = album;
        subtitle = artist;
      }

      buckets.putIfAbsent(key, () => []).add(song);
      titles.putIfAbsent(key, () => title);
      subtitles.putIfAbsent(key, () => subtitle);
    }

    final groups = buckets.entries
        .map((entry) {
          final orderedSongs = List<Song>.from(entry.value)
            ..sort((a, b) {
              final aTitle = a.title.isEmpty ? a.displayName : a.title;
              final bTitle = b.title.isEmpty ? b.displayName : b.title;
              return aTitle.toLowerCase().compareTo(bTitle.toLowerCase());
            });
          return _MediaGroup(
            key: entry.key,
            title: titles[entry.key]!,
            subtitle: subtitles[entry.key]!,
            songs: orderedSongs,
          );
        })
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
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
  });

  final String key;
  final String title;
  final String subtitle;
  final List<Song> songs;
}

class _CollectionArtwork extends StatelessWidget {
  const _CollectionArtwork({
    required this.player,
    required this.song,
    required this.size,
    this.circular = false,
    this.placeholderIcon = Icons.music_note_rounded,
  });

  final MusicPlayerController player;
  final Song song;
  final double? size;
  final bool circular;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
        future: player.loadArtwork(song),
        builder: (context, snapshot) {
          final artwork = snapshot.data;
          final iconSize = (size ?? 80) * .38;
          final child = artwork == null
              ? Container(
                  color: Colors.white.withOpacity(.07),
                  alignment: Alignment.center,
                  child: Icon(placeholderIcon, color: Colors.white54, size: iconSize),
                )
              : Image.memory(artwork, fit: BoxFit.cover);
          return ClipRRect(
            borderRadius: BorderRadius.circular(circular ? 1000 : 16),
            child: size == null
                ? SizedBox.expand(child: child)
                : SizedBox(width: size, height: size, child: child),
          );
        },
      );
}

class _BubbleAction extends StatelessWidget {
  const _BubbleAction({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
        avatar: Icon(icon, size: 17),
        label: Text(label),
        onPressed: onTap,
      );
}

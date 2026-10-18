import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_colors.dart';
import '../music_player.dart';
import '../song_actions.dart';
import '../services/artwork_palette.dart';
import '../widgets/section_spotlight.dart';

class FoldersSection extends StatefulWidget {
  final MusicPlayerController player;
  final ArtworkPalette palette;

  const FoldersSection({
    super.key,
    required this.player,
    required this.palette,
  });

  @override
  State<FoldersSection> createState() => _FoldersSectionState();
}

class _FoldersSectionState extends State<FoldersSection> {
  List<Map<String, String>> _selectedFolders = const [];
  bool _loadingFolders = true;
  bool _addingFolder = false;
  bool _refreshingFolders = false;

  @override
  void initState() {
    super.initState();
    widget.player.addListener(_onPlayerChanged);
    _loadSelectedFolders();
  }

  @override
  void dispose() {
    widget.player.removeListener(_onPlayerChanged);
    super.dispose();
  }

  void _onPlayerChanged() {
    if (!mounted) return;
    setState(() {});

    final hasSoundNeedSongs = widget.player.songs.any(
      (song) => song.folderPath
          .replaceAll('\\', '/')
          .toLowerCase()
          .contains('/soundneed'),
    );
    final soundNeedAlreadySelected = _selectedFolders.any(
      (folder) => folder['name']?.toLowerCase() == 'soundneed',
    );
    if (hasSoundNeedSongs && !soundNeedAlreadySelected && !_refreshingFolders) {
      _refreshingFolders = true;
      _loadSelectedFolders().whenComplete(() => _refreshingFolders = false);
    }
  }

  Future<void> _loadSelectedFolders() async {
    final folders = await widget.player.getMusicFolders();
    if (!mounted) return;
    setState(() {
      _selectedFolders = folders;
      _loadingFolders = false;
    });
  }

  Future<void> _addFolder() async {
    if (_addingFolder) return;
    setState(() => _addingFolder = true);
    try {
      await widget.player.addMusicFolder();
      await _loadSelectedFolders();
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message ?? 'No se pudo agregar la carpeta.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo agregar la carpeta: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _addingFolder = false);
    }
  }

  Future<void> _removeFolder(String path) async {
    await widget.player.removeMusicFolder(path);
    await _loadSelectedFolders();
  }

  bool _isInsideFolder(String songFolder, String folder) {
    String normalize(String path) =>
        path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '').toLowerCase();

    final songPath = normalize(songFolder);
    final folderPath = normalize(folder);
    return songPath == folderPath || songPath.startsWith('$folderPath/');
  }

  @override
  Widget build(BuildContext context) {
    final songsByFolder = <String, List<Song>>{};
    for (final song in widget.player.songs) {
      final path = song.folderPath.trim();
      if (path.isEmpty) continue;
      songsByFolder.putIfAbsent(path, () => <Song>[]).add(song);
    }

    final folderPaths = <String>{...songsByFolder.keys};
    folderPaths.addAll(_selectedFolders.map((folder) => folder['path'] ?? ''));
    folderPaths.remove('');
    final sortedPaths = folderPaths.toList()..sort();
    final songsInFolders = songsByFolder.values.fold<int>(
      0,
      (total, songs) => total + songs.length,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SectionSpotlight(
            eyebrow: 'TU BIBLIOTECA',
            title: 'Tus carpetas',
            subtitle:
                '${sortedPaths.length} ${sortedPaths.length == 1 ? 'carpeta' : 'carpetas'} · $songsInFolders canciones',
            icon: Icons.folder_open_rounded,
            accent: const Color(0xFF6979F8),
            palette: widget.palette,
            action: FilledButton.tonalIcon(
              onPressed: _addingFolder ? null : _addFolder,
              icon: _addingFolder
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_rounded, size: 18),
              label: const Text('Añadir'),
              style: FilledButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: const StadiumBorder(),
              ),
            ),
          ),
        ),
        Expanded(
          child: _loadingFolders && sortedPaths.isEmpty
              ? Center(
                  child: CircularProgressIndicator(
                    color: widget.palette.secondary,
                  ),
                )
              : sortedPaths.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Container(
                      width: 360,
                      padding: const EdgeInsets.fromLTRB(22, 25, 22, 22),
                      decoration: BoxDecoration(
                        color: AppColors.card.withValues(alpha: .72),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: widget.palette.primary.withValues(alpha: .24),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 74,
                            height: 74,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  widget.palette.primary.withValues(alpha: .45),
                                  widget.palette.secondary.withValues(
                                    alpha: .15,
                                  ),
                                ],
                              ),
                              border: Border.all(
                                color: widget.palette.secondary.withValues(
                                  alpha: .30,
                                ),
                              ),
                            ),
                            child: Icon(
                              Icons.folder_open_rounded,
                              size: 34,
                              color: widget.palette.secondary,
                            ),
                          ),
                          const SizedBox(height: 17),
                          const Text(
                            'Tu música, a tu manera',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.25,
                            ),
                          ),
                          const SizedBox(height: 7),
                          const Text(
                            'Agrega una carpeta del dispositivo y SoundNeed organizará aquí tus canciones.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: _addingFolder ? null : _addFolder,
                            icon: const Icon(Icons.create_new_folder_rounded),
                            label: const Text('Agregar carpeta'),
                            style: FilledButton.styleFrom(
                              backgroundColor: widget.palette.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              shape: const StadiumBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: sortedPaths.length,
                  itemBuilder: (context, index) {
                    final path = sortedPaths[index];
                    final selected = _selectedFolders.any(
                      (folder) => folder['path'] == path,
                    );
                    final songs = selected
                        ? widget.player.songs
                              .where(
                                (song) =>
                                    _isInsideFolder(song.folderPath, path),
                              )
                              .toList()
                        : songsByFolder[path] ?? const <Song>[];
                    final pathParts = path
                        .split(RegExp(r'[/\\]'))
                        .where((part) => part.isNotEmpty)
                        .toList();
                    final name = pathParts.isEmpty ? path : pathParts.last;

                    return Card(
                      color: Color.lerp(
                        AppColors.card,
                        widget.palette.dark,
                        .16,
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: selected
                              ? widget.palette.primary.withValues(alpha: 0.48)
                              : Colors.white.withValues(alpha: 0.09),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ExpansionTile(
                        key: ValueKey(path),
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 5,
                        ),
                        childrenPadding: const EdgeInsets.only(bottom: 8),
                        collapsedIconColor: Colors.white54,
                        iconColor: widget.palette.secondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        collapsedShape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        leading: _buildFolderArtwork(songs, selected: selected),
                        title: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.15,
                          ),
                        ),
                        subtitle: Text(
                          '${selected ? 'Carpeta agregada' : 'Toca para explorar'} · ${songs.length} ${songs.length == 1 ? 'canción' : 'canciones'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: selected
                            ? IconButton(
                                tooltip: 'Quitar carpeta agregada',
                                onPressed: () => _removeFolder(path),
                                icon: const Icon(Icons.remove_circle_outline),
                              )
                            : null,
                        children: songs.isEmpty
                            ? const [
                                ListTile(
                                  title: Text(
                                    'No se encontraron canciones en esta carpeta.',
                                    style: TextStyle(color: Colors.white60),
                                  ),
                                ),
                              ]
                            : [
                                for (
                                  var songIndex = 0;
                                  songIndex < songs.length;
                                  songIndex++
                                )
                                  ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    leading: _buildSongArtwork(
                                      songs[songIndex],
                                    ),
                                    title: Text(
                                      songs[songIndex].title.isEmpty
                                          ? songs[songIndex].displayName
                                          : songs[songIndex].title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      songs[songIndex].artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onLongPress: () => confirmDeleteSong(
                                      context,
                                      widget.player,
                                      songs[songIndex],
                                    ),
                                    trailing: IconButton(
                                      tooltip: 'Eliminar del dispositivo',
                                      onPressed: () => confirmDeleteSong(
                                        context,
                                        widget.player,
                                        songs[songIndex],
                                      ),
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                      ),
                                    ),
                                    onTap: () => widget.player.playPlaylist(
                                      songs,
                                      startIndex: songIndex,
                                    ),
                                  ),
                              ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSongArtwork(Song song) {
    return FutureBuilder<Uint8List?>(
      future: widget.player.loadArtwork(song),
      builder: (context, snapshot) {
        final artwork = snapshot.data;
        return ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            width: 44,
            height: 44,
            child: artwork == null
                ? ColoredBox(
                    color: Colors.white.withValues(alpha: 0.07),
                    child: const Icon(
                      Icons.music_note_rounded,
                      color: Colors.white60,
                    ),
                  )
                : Image.memory(artwork, fit: BoxFit.cover),
          ),
        );
      },
    );
  }

  Widget _buildFolderArtwork(List<Song> songs, {required bool selected}) {
    if (songs.isEmpty) {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: widget.palette.primary.withValues(alpha: .11),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: widget.palette.primary.withValues(alpha: .27),
          ),
        ),
        child: Icon(
          Icons.folder_rounded,
          color: selected ? widget.palette.secondary : widget.palette.primary,
        ),
      );
    }

    Widget tile(Song song) => Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: FutureBuilder<Uint8List?>(
          future: widget.player.loadArtwork(song),
          builder: (context, snapshot) {
            final artwork = snapshot.data;
            return artwork == null
                ? ColoredBox(
                    color: Colors.white.withValues(alpha: 0.08),
                    child: const Icon(
                      Icons.music_note_rounded,
                      color: Colors.white54,
                      size: 13,
                    ),
                  )
                : Image.memory(artwork, fit: BoxFit.cover);
          },
        ),
      ),
    );

    final covers = songs.take(4).toList();
    while (covers.length < 4) {
      covers.add(songs[covers.length % songs.length]);
    }
    return Container(
      width: 52,
      height: 52,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.palette.primary.withValues(alpha: .36),
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                tile(covers[0]),
                const SizedBox(width: 2),
                tile(covers[1]),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Row(
              children: [
                tile(covers[2]),
                const SizedBox(width: 2),
                tile(covers[3]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

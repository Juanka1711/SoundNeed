import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../music_player.dart';

class FoldersSection extends StatefulWidget {
  final MusicPlayerController player;

  const FoldersSection({super.key, required this.player});

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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Carpetas de música',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _addingFolder ? null : _addFolder,
                icon: _addingFolder
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.create_new_folder_outlined),
                label: const Text('Agregar'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingFolders && sortedPaths.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : sortedPaths.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.folder_open_rounded,
                          size: 58,
                          color: Colors.white.withValues(alpha: 0.40),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'No hay carpetas con música',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Agrega una carpeta para incluir sus canciones.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white60),
                        ),
                      ],
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
                      color: Colors.white.withValues(alpha: 0.045),
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.07),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ExpansionTile(
                        key: ValueKey(path),
                        leading: Icon(
                          Icons.folder_rounded,
                          color: selected ? Colors.amberAccent : Colors.white70,
                        ),
                        title: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${songs.length} ${songs.length == 1 ? 'canción' : 'canciones'} · $path',
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
                                    leading: _buildSongArtwork(
                                      songs[songIndex],
                                    ),
                                    title: Text(
                                      songs[songIndex].title.isEmpty
                                          ? songs[songIndex].displayName
                                          : songs[songIndex].title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      songs[songIndex].artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
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
}

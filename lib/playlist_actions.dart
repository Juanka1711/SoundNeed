import 'package:flutter/material.dart';

import 'music_player.dart';
import 'playlist_manager.dart';

bool isSongLiked(MusicPlayerController player, Song song) {
  return player.isFavorite(song) ||
      PlaylistManager.instance.likedSongs.any(
        (likedSong) => songKey(likedSong) == songKey(song),
      );
}

Future<void> setSongLiked(
  MusicPlayerController player,
  Song song,
  bool liked,
) async {
  final manager = PlaylistManager.instance;
  await manager.initialize();
  await manager.setLikedSong(song, liked);
  try {
    await player.setFavorite(song, liked);
  } catch (error) {
    debugPrint('[Playlist] No se pudo sincronizar el favorito local: $error');
  }
}

Future<bool> toggleSongLiked(
  MusicPlayerController player,
  Song song,
) async {
  final liked = !isSongLiked(player, song);
  await setSongLiked(player, song, liked);
  return liked;
}

Future<String?> askPlaylistName(BuildContext context, {String? initialName}) async {
  final controller = TextEditingController(text: initialName ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF171720),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(30),
        side: BorderSide(color: Colors.white.withOpacity(.10)),
      ),
      title: Text(initialName == null ? 'Nueva playlist' : 'Cambiar nombre'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: 'Nombre (opcional)',
          filled: true,
          fillColor: const Color(0xFF242431),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(color: Colors.white.withOpacity(.12)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: const BorderSide(color: Colors.white, width: 1.5),
          ),
        ),
        onSubmitted: (_) => Navigator.pop(context, controller.text),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          ),
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

Future<MusicPlaylist?> createPlaylistFromDialog(BuildContext context) async {
  final name = await askPlaylistName(context);
  if (name == null || !context.mounted) return null;
  return PlaylistManager.instance.createPlaylist(name);
}

Future<void> addSongToPlaylist(BuildContext context, MusicPlayerController player, Song song) async {
  final manager = PlaylistManager.instance;
  await manager.initialize();
  if (!context.mounted) return;

  if (manager.playlists.length == 1) {
    final added = await manager.addSong(manager.playlists.single.id, song);
    if (context.mounted) _message(context, added ? 'Añadida a ${manager.playlists.single.name}' : 'La canción ya está en la playlist');
    return;
  }

  if (manager.playlists.isEmpty) {
    final created = await createPlaylistFromDialog(context);
    if (created == null || !context.mounted) return;
    await manager.addSong(created.id, song);
    if (context.mounted) _message(context, 'Añadida a ${created.name}');
    return;
  }

  final selected = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF1D1D2B),
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Añadir a playlist', style: TextStyle(fontWeight: FontWeight.bold))),
          ...manager.playlists.map((playlist) => ListTile(
                leading: const Icon(Icons.queue_music),
                title: Text(playlist.name),
                subtitle: Text('${playlist.songs.length} canciones'),
                onTap: () => Navigator.pop(sheetContext, playlist.id),
              )),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Crear nueva playlist'),
            onTap: () => Navigator.pop(sheetContext, '__create__'),
          ),
        ],
      ),
    ),
  );
  if (selected == null || !context.mounted) return;
  MusicPlaylist? target = manager.findPlaylist(selected);
  if (selected == '__create__') target = await createPlaylistFromDialog(context);
  if (target == null || !context.mounted) return;
  final added = await manager.addSong(target.id, song);
  if (context.mounted) _message(context, added ? 'Añadida a ${target.name}' : 'La canción ya está en la playlist');
}

void _message(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
}

import 'package:flutter/material.dart';

import 'music_player.dart';

/// Confirma y elimina una canción local del dispositivo.
Future<void> confirmDeleteSong(
  BuildContext context,
  MusicPlayerController player,
  Song song,
) async {
  if (song.isOnline || song.isPodcast || !song.uri.startsWith('content://')) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Solo puedes eliminar canciones guardadas en el dispositivo.')),
    );
    return;
  }

  final shouldDelete = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF211D2D),
      title: const Text('Eliminar canción'),
      content: Text(
        '¿Quieres eliminar “${song.title.isEmpty ? song.displayName : song.title}” del dispositivo? La eliminación es permanente y puede requerir confirmación del sistema.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Continuar'),
        ),
      ],
    ),
  );
  if (shouldDelete != true || !context.mounted) return;

  try {
    final deleted = await player.deleteSong(song);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted ? 'Canción eliminada del dispositivo.' : 'No se eliminó la canción.',
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No se pudo eliminar la canción: $error')),
    );
  }
}

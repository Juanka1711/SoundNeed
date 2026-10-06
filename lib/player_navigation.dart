import 'package:flutter/material.dart';

import 'full_player.dart';
import 'music_player.dart';

/// Reproduce una canción nueva. Si ya está seleccionada, muestra el
/// reproductor completo sin volver a iniciar la extracción.
Future<void> selectSongOrOpenPlayer(
  BuildContext context,
  MusicPlayerController player,
  Song song, {
  bool createQueue = true,
}) async {
  if (player.currentSong?.id == song.id &&
      player.currentSong?.uri == song.uri) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => FullPlayer(player: player)),
    );
    return;
  }

  await player.playSong(song, createQueue: createQueue);
}

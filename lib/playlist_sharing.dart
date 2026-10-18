import 'dart:convert';
import 'dart:io';

import 'music_player.dart';

const int maxSharedPlaylistSongs = 300;
const int maxSharedPlaylistPayloadLength = 350000;

/// Compact, versioned payload for a shareable playlist link.
/// Track tuples are [YouTube ID, title, artist, duration in ms]. Local tracks
/// carry an empty ID and are matched or searched on the receiving device.
String encodeSharedPlaylist(String name, List<Song> songs) {
  final tracks = songs
      .map(
        (song) => <Object?>[
          song.isOnline ? song.onlineVideoId : '',
          song.title.isEmpty ? song.displayName : song.title,
          song.artist,
          song.duration,
        ],
      )
      .toList(growable: false);
  final json = jsonEncode(<String, Object?>{'v': 1, 'n': name, 's': tracks});
  return base64Url.encode(gzip.encode(utf8.encode(json))).replaceAll('=', '');
}

Map<String, dynamic> decodeSharedPlaylist(String encoded) {
  if (encoded.isEmpty || encoded.length > maxSharedPlaylistPayloadLength) {
    throw const FormatException(
      'La playlist compartida supera el tamaño permitido.',
    );
  }
  final normalized = encoded.replaceAll('-', '+').replaceAll('_', '/');
  final padded = normalized.padRight((normalized.length + 3) ~/ 4 * 4, '=');
  final decoded = jsonDecode(utf8.decode(gzip.decode(base64.decode(padded))));
  if (decoded is! Map || decoded['v'] != 1 || decoded['s'] is! List) {
    throw const FormatException('El enlace no contiene una playlist válida.');
  }
  final tracks = decoded['s'] as List;
  if (tracks.isEmpty || tracks.length > maxSharedPlaylistSongs) {
    throw const FormatException(
      'La playlist compartida no tiene un tamaño válido.',
    );
  }
  for (final track in tracks) {
    if (track is! List || track.length < 3 || track[1] is! String) {
      throw const FormatException(
        'La playlist compartida contiene una canción inválida.',
      );
    }
  }
  return Map<String, dynamic>.from(decoded);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:SoundNeed/music_player.dart';
import 'package:SoundNeed/playlist_sharing.dart';

void main() {
  test('codifica y decodifica una playlist compartida', () {
    final song = Song(
      id: 1,
      title: 'Tema de prueba',
      displayName: 'Tema de prueba.mp3',
      artist: 'SoundNeed',
      album: 'Pruebas',
      albumId: null,
      duration: 180000,
      mimeType: 'audio/mpeg',
      size: 1024,
      uri: '/music/tema.mp3',
      artworkUri: '',
      isMusic: true,
    );

    final encoded = encodeSharedPlaylist('Favoritas', [song]);
    final decoded = decodeSharedPlaylist(encoded);

    expect(decoded['v'], 1);
    expect(decoded['n'], 'Favoritas');
    expect(decoded['s'], hasLength(1));
    expect((decoded['s'] as List).single[1], 'Tema de prueba');
  });
}

<<<<<<< HEAD
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
=======
// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';


void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that our counter starts at 0.
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    // Tap the '+' icon and trigger a frame.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    // Verify that our counter has incremented.
    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsOneWidget);
>>>>>>> 1f6e8dce69bd1be9392142d64d1fcaf6d7107d52
  });
}

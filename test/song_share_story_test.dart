import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:SoundNeed/song_share_story.dart';

void main() {
  const pixelPng =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/1x0AAAAASUVORK5CYII=';

  testWidgets('muestra destinos y los envía en el formato seleccionado', (
    tester,
  ) async {
    String? sentFormat;
    String? sentPackage;
    final preview = Uint8List.fromList(base64Decode(pixelPng));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongShareStoryPage(
            title: 'Tema',
            artist: 'Artista',
            preview: preview,
            onPreviewForTheme: (_) async => preview,
            onLoadTargets: (_) async => [
              <String, Object?>{
                'packageName': 'com.example.chat',
                'className': 'com.example.chat.ShareActivity',
                'label': 'ChatApp',
              },
            ],
            onShareToTarget: (format, theme, target) async {
              sentFormat = format;
              sentPackage = target['packageName'] as String;
            },
            onShareStory: (_) async {},
            onShareChat: (_) async {},
            onShareVideo: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Compartir con'), findsOneWidget);
    expect(find.text('ChatApp'), findsOneWidget);
    expect(find.text('Más'), findsOneWidget);

    await tester.tap(find.text('Vídeo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ChatApp'));
    await tester.pumpAndSettle();

    expect(sentFormat, 'video');
    expect(sentPackage, 'com.example.chat');
  });

  testWidgets('el formato Estado envía la tarjeta de estado al destino', (
    tester,
  ) async {
    String? sentFormat;
    final preview = Uint8List.fromList(base64Decode(pixelPng));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongShareStoryPage(
            title: 'Tema',
            artist: 'Artista',
            preview: preview,
            onPreviewForTheme: (_) async => preview,
            onLoadTargets: (_) async => [
              <String, Object?>{
                'packageName': 'com.example.social',
                'className': 'com.example.social.ShareActivity',
                'label': 'Red social',
              },
            ],
            onShareToTarget: (format, theme, target) async {
              sentFormat = format;
            },
            onShareStory: (_) async {},
            onShareChat: (_) async {},
            onShareVideo: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Red social'));
    await tester.pumpAndSettle();

    expect(sentFormat, 'story');
  });
}

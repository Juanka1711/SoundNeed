import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Coordinates the preview and native Android dispatch for one song share.
class ShareSessionController {
  static const MethodChannel _channel = MethodChannel('music_player/media');

  Future<Uint8List> createPreview({
    required String title,
    required String artist,
    required Uint8List artwork,
  }) async {
    final preview = await _channel.invokeMethod<Uint8List>(
      'createSongSharePreview',
      <String, Object?>{
        'title': title,
        'artist': artist,
        'artwork': artwork,
      },
    );
    if (preview == null || preview.isEmpty) {
      throw StateError('No se pudo preparar la vista previa.');
    }
    return preview;
  }

  Future<void> shareStory({
    required String title,
    required String artist,
    required String album,
    required String shareUrl,
    required Uint8List artwork,
    String deepLink = '',
    String audioSource = '',
    String videoId = '',
    int startMs = 0,
    int durationMs = 15000,
  }) => _channel.invokeMethod<void>(
    'shareSongCard',
    <String, Object?>{
      'title': title,
      'artist': artist,
      'album': album,
      'shareUrl': shareUrl,
      'artwork': artwork,
      'link': deepLink,
      'audioSource': audioSource,
      'videoId': videoId,
      'startMs': startMs,
      'durationMs': durationMs,
    },
  );

  Future<void> shareChat({
    required String title,
    required String artist,
    required String album,
    required String shareUrl,
  }) => _channel.invokeMethod<void>(
    'shareSongLink',
    <String, Object?>{
      'title': title,
      'artist': artist,
      'album': album,
      'shareUrl': shareUrl,
    },
  );

  Future<void> shareVideo({
    required String title,
    required String artist,
    required String album,
    required String shareUrl,
    required String deepLink,
    required Uint8List artwork,
    required String audioSource,
    required int startMs,
    required int durationMs,
  }) => _channel.invokeMethod<void>(
    'shareSong',
    <String, Object?>{
      'title': title,
      'artist': artist,
      'album': album,
      'link': deepLink,
      'shareUrl': shareUrl,
      'artwork': artwork,
      'audioSource': audioSource,
      'startMs': startMs,
      'durationMs': durationMs,
    },
  );
}

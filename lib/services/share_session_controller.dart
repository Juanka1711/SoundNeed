import 'package:flutter/services.dart';

/// Coordinates the preview and native Android dispatch for one song share.
class ShareSessionController {
  static const MethodChannel _channel = MethodChannel('music_player/media');

  Future<List<Map<String, Object?>>> loadTargets(String format) async {
    final raw = await _channel.invokeListMethod<Object?>(
      'getSongShareTargets',
      <String, Object?>{'format': format},
    );
    return (raw ?? const <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map((item) => item.map((key, value) => MapEntry('$key', value)))
        .cast<Map<String, Object?>>()
        .toList(growable: false);
  }

  Future<void> shareToTarget({
    required String format,
    required String packageName,
    required String className,
    required String title,
    required String artist,
    required String album,
    required String shareUrl,
    required Uint8List artwork,
    required String theme,
    String deepLink = '',
    String audioSource = '',
    String videoId = '',
    int startMs = 0,
    int durationMs = 15000,
  }) => _channel.invokeMethod<void>('shareSongToTarget', <String, Object?>{
    'format': format,
    'packageName': packageName,
    'className': className,
    'title': title,
    'artist': artist,
    'album': album,
    'shareUrl': shareUrl,
    'artwork': artwork,
    'theme': theme,
    'link': deepLink,
    'audioSource': audioSource,
    'videoId': videoId,
    'startMs': startMs,
    'durationMs': durationMs,
  });

  Future<Uint8List> createPreview({
    required String title,
    required String artist,
    required Uint8List artwork,
    String theme = 'ocean',
  }) async {
    final preview = await _channel.invokeMethod<Uint8List>(
      'createSongSharePreview',
      <String, Object?>{
        'title': title,
        'artist': artist,
        'artwork': artwork,
        'theme': theme,
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
    String theme = 'ocean',
    String deepLink = '',
    String audioSource = '',
    String videoId = '',
    int startMs = 0,
    int durationMs = 15000,
  }) => _channel.invokeMethod<void>('shareSongCard', <String, Object?>{
    'title': title,
    'artist': artist,
    'album': album,
    'shareUrl': shareUrl,
    'artwork': artwork,
    'theme': theme,
    'link': deepLink,
    'audioSource': audioSource,
    'videoId': videoId,
    'startMs': startMs,
    'durationMs': durationMs,
  });

  Future<void> shareChat({
    required String title,
    required String artist,
    required String album,
    required String shareUrl,
    required Uint8List artwork,
    String theme = 'ocean',
  }) => _channel.invokeMethod<void>('shareSongLink', <String, Object?>{
    'title': title,
    'artist': artist,
    'album': album,
    'shareUrl': shareUrl,
    'artwork': artwork,
    'theme': theme,
  });

  Future<void> shareVideo({
    required String title,
    required String artist,
    required String album,
    required String shareUrl,
    required String deepLink,
    required Uint8List artwork,
    required String audioSource,
    String videoId = '',
    required int startMs,
    required int durationMs,
    String theme = 'ocean',
  }) => _channel.invokeMethod<void>('shareSong', <String, Object?>{
    'title': title,
    'artist': artist,
    'album': album,
    'link': deepLink,
    'shareUrl': shareUrl,
    'artwork': artwork,
    'audioSource': audioSource,
    'videoId': videoId,
    'startMs': startMs,
    'durationMs': durationMs,
    'theme': theme,
  });
}

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'youtube_audio_service.dart';

/// Reproductor de música: usa YouTubeAudioService para obtener el audio
/// y just_audio para reproducirlo.
class MusicPlayerService {
  MusicPlayerService._();

  static final MusicPlayerService instance = MusicPlayerService._();

  final AudioPlayer _player = AudioPlayer();

  /// Canción actual (null si no hay ninguna).
  final ValueNotifier<YouTubeSearchResult?> currentTrack =
      ValueNotifier<YouTubeSearchResult?>(null);

  /// true mientras se obtiene el audio de YouTube.
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);

  AudioPlayer get player => _player;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  bool get isPlaying => _player.playing;

  /// Reproduce una canción. Devuelve false si falló.
  Future<bool> play(YouTubeSearchResult track) async {
    isLoading.value = true;
    currentTrack.value = track;

    try {
      final url = await YouTubeAudioService.instance.getAudioUrl(
        track.videoId,
      );

      if (url == null) {
        debugPrint('[MusicPlayer] No se pudo obtener el audio.');
        return false;
      }

      await _player.setAudioSource(AudioSource.uri(Uri.parse(url)));
      await _player.play();

      return true;
    } catch (e) {
      debugPrint('[MusicPlayer] Error reproduciendo: $e');
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> pause() => _player.pause();

  Future<void> resume() => _player.play();

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> stop() async {
    await _player.stop();
    currentTrack.value = null;
  }

  Future<void> dispose() async {
    await _player.dispose();
    YouTubeAudioService.instance.dispose();
  }
}

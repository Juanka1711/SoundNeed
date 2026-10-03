import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class SoundNeedAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<PlaybackEvent>? _playbackSub;
  StreamSubscription<SequenceState?>? _sequenceSub;

  bool _disposed = false;

  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;

  AudioPlayer get player => _player;

  SoundNeedAudioHandler() {
    _init();
  }

  void _init() {
    // Estado inicial de la MediaSession.
    playbackState.add(
      PlaybackState(
        controls: const [
          MediaControl.play,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1],
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 1.0,
      ),
    );

    // ================================================================
    // JUST_AUDIO → AUDIO_SERVICE
    // ================================================================

    _playbackSub = _player.playbackEventStream.listen(
      (event) {
        if (_disposed) return;

        _publishPlaybackState(event);
      },
      onError: (Object error, StackTrace stack) {
        if (_disposed) return;

        playbackState.add(
          playbackState.value.copyWith(
            playing: false,
            processingState: AudioProcessingState.error,
            errorMessage: error.toString(),
          ),
        );
      },
    );

    // ================================================================
    // AUDIO SOURCE → MEDIA ITEM
    // ================================================================

    _sequenceSub = _player.sequenceStateStream.listen(
      (state) {
        if (_disposed || state == null) return;

        final sequence = state.sequence;

        if (sequence.isEmpty) {
          queue.add(const []);
          return;
        }

        final items = <MediaItem>[];

        for (final source in sequence) {
          final tag = source.tag;

          if (tag is MediaItem) {
            items.add(tag);
          }
        }

        // Android recibe la cola.
        queue.add(items);

        final index = state.currentIndex;

        if (index == null ||
            index < 0 ||
            index >= sequence.length) {
          return;
        }

        final tag = sequence[index].tag;

        if (tag is MediaItem) {
          mediaItem.add(tag);
        }
      },
      onError: (Object error, StackTrace stack) {
        // No dejamos que un error de metadata destruya el handler.
      },
    );
  }

  // ================================================================
  // PUBLICAR PLAYBACK STATE
  // ================================================================

  void _publishPlaybackState(PlaybackEvent event) {
    final processingState = _mapProcessingState(
      _player.processingState,
    );

    final isPlaying = _player.playing;

    final controls = <MediaControl>[
      MediaControl.skipToPrevious,
      isPlaying ? MediaControl.pause : MediaControl.play,
      MediaControl.skipToNext,
      MediaControl.stop,
    ];

    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [
          0,
          1,
          2,
        ],
        processingState: processingState,
        playing: isPlaying,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
        updateTime: DateTime.now(),
      ),
    );
  }

  AudioProcessingState _mapProcessingState(
    ProcessingState state,
  ) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;

      case ProcessingState.loading:
        return AudioProcessingState.loading;

      case ProcessingState.buffering:
        return AudioProcessingState.buffering;

      case ProcessingState.ready:
        return AudioProcessingState.ready;

      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  // ================================================================
  // PLAY
  // ================================================================

  @override
  Future<void> play() async {
    if (_disposed) return;

    await _player.play();

    // Garantizamos que el estado que recibe audio_service
    // corresponda al estado real de just_audio.
    final event = PlaybackEvent(
      processingState: _player.processingState,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      duration: _player.duration,
      currentIndex: _player.currentIndex,
      androidAudioSessionId: null,
      updateTime: DateTime.now(),
    );

    _publishPlaybackState(event);
  }

  // ================================================================
  // PAUSE
  // ================================================================

  @override
  Future<void> pause() async {
    if (_disposed) return;

    await _player.pause();

    final event = PlaybackEvent(
      processingState: _player.processingState,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      duration: _player.duration,
      currentIndex: _player.currentIndex,
      androidAudioSessionId: null,
      updateTime: DateTime.now(),
    );

    _publishPlaybackState(event);
  }

  // ================================================================
  // STOP
  // ================================================================

  @override
  Future<void> stop() async {
    if (_disposed) return;

    await _player.stop();

    playbackState.add(
      PlaybackState(
        controls: const [
          MediaControl.play,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0],
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 1.0,
        queueIndex: null,
        updateTime: DateTime.now(),
      ),
    );
  }

  // ================================================================
  // SEEK
  // ================================================================

  @override
  Future<void> seek(Duration position) async {
    if (_disposed) return;

    await _player.seek(position);
  }

  // ================================================================
  // NEXT
  // ================================================================

  @override
  Future<void> skipToNext() async {
    if (_disposed) return;

    final callback = onSkipToNext;
    if (callback != null) {
      await callback();
    } else if (_player.hasNext) {
      await _player.seekToNext();
    }
  }

  // ================================================================
  // PREVIOUS
  // ================================================================

  @override
  Future<void> skipToPrevious() async {
    if (_disposed) return;

    final callback = onSkipToPrevious;
    if (callback != null) {
      await callback();
    } else if (_player.hasPrevious) {
      await _player.seekToPrevious();
    }
  }

  // ================================================================
  // SPEED
  // ================================================================

  @override
  Future<void> setSpeed(double speed) async {
    if (_disposed) return;

    await _player.setSpeed(speed);
  }

  // ================================================================
  // FAST FORWARD
  // ================================================================

  @override
  Future<void> fastForward() async {
    if (_disposed) return;

    final position = _player.position;
    final duration = _player.duration;

    final target = position + const Duration(seconds: 10);

    if (duration == null) {
      await _player.seek(target);
      return;
    }

    await _player.seek(
      target > duration ? duration : target,
    );
  }

  // ================================================================
  // REWIND
  // ================================================================

  @override
  Future<void> rewind() async {
    if (_disposed) return;

    final target =
        _player.position - const Duration(seconds: 10);

    await _player.seek(
      target.isNegative ? Duration.zero : target,
    );
  }

  // ================================================================
  // ANDROID TASK REMOVED
  // ================================================================

  @override
  Future<void> onTaskRemoved() async {
    // SoundNeed continúa reproduciendo.
  }

  // ================================================================
  // DISPOSE
  // ================================================================

  Future<void> disposePlayer() async {
    if (_disposed) return;

    _disposed = true;

    await _playbackSub?.cancel();
    await _sequenceSub?.cancel();

    await _player.dispose();
  }
}

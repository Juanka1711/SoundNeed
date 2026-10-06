import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

class SoundNeedAudioHandler extends BaseAudioHandler with SeekHandler {
  static const MethodChannel _widgetChannel = MethodChannel('soundneed/widget');

  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<PlaybackEvent>? _playbackSub;
  StreamSubscription<SequenceState?>? _sequenceSub;
  StreamSubscription<Duration>? _positionSub;

  bool _disposed = false;
  MediaItem? _currentMediaItem;
  String? _lastWidgetSongId;
  bool? _lastWidgetPlaying;
  final Map<String, MediaItem> _artworkOverrides = {};

  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;
  Future<void> Function()? onPlayRequested;
  Future<void> Function()? onStopRequested;

  AudioPlayer get player => _player;
  MediaItem? get currentMediaItem => _currentMediaItem;

  /// Publica inmediatamente la canción seleccionada, aunque su fuente online
  /// todavía esté resolviéndose.
  void setPendingMediaItem(MediaItem item) {
    _currentMediaItem = item;
    mediaItem.add(item);
    _lastWidgetSongId = null;
    _syncWidgetState(force: true);
    unawaited(
      _widgetChannel
          .invokeMethod<void>('updateProgress', const <String, Object?>{
            'position': 0,
            'duration': 0,
          })
          .catchError((Object error) {}),
    );
  }

  /// Fuerza al widget a reintentar la portada cuando vuelve la conexión.
  void refreshWidgetArtwork() {
    _lastWidgetSongId = null;
    _syncWidgetState(force: true);
  }

  void updateMediaItemArtwork(MediaItem item) {
    _artworkOverrides[item.id] = item;
    if (_currentMediaItem?.id == item.id) {
      _currentMediaItem = item;
      mediaItem.add(item);
      _lastWidgetSongId = null;
      _syncWidgetState(force: true);
    }
  }

  SoundNeedAudioHandler() {
    _init();
  }

  void _init() {
    // Estado inicial de la MediaSession.
    playbackState.add(
      PlaybackState(
        controls: const [MediaControl.play, MediaControl.stop],
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
        _syncWidgetState(force: true);
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

        if (index == null || index < 0 || index >= sequence.length) {
          return;
        }

        final tag = sequence[index].tag;

        if (tag is MediaItem) {
          final current = _artworkOverrides[tag.id] ?? tag;
          _currentMediaItem = current;
          mediaItem.add(current);
          _syncWidgetState(force: true);
        }
      },
      onError: (Object error, StackTrace stack) {
        // No dejamos que un error de metadata destruya el handler.
      },
    );

    // ================================================================
    // POSITION → WIDGET PROGRESS
    // ================================================================

    _positionSub = _player.positionStream.listen(
      (position) {
        if (_disposed) return;

        final duration = _player.duration;
        if (duration != null) {
          _syncWidgetProgress(position, duration);
        }
      },
      onError: (Object error, StackTrace stack) {
        // No dejamos que un error de posición destruya el handler.
      },
    );
  }

  // ================================================================
  // PUBLICAR PLAYBACK STATE
  // ================================================================

  void _publishPlaybackState(PlaybackEvent event) {
    final processingState = _mapProcessingState(_player.processingState);

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
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processingState,
        playing: isPlaying,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
        updateTime: DateTime.now(),
      ),
    );
    _syncWidgetState();
  }

  void _syncWidgetState({bool force = false}) {
    if (_disposed) return;

    final item = _currentMediaItem;
    if (item == null) return;

    final isPlaying = _player.playing;
    if (!force &&
        item.id == _lastWidgetSongId &&
        isPlaying == _lastWidgetPlaying) {
      return;
    }

    _lastWidgetSongId = item.id;
    _lastWidgetPlaying = isPlaying;

    unawaited(
      _widgetChannel
          .invokeMethod<void>('updatePlayback', <String, Object?>{
            'title': item.title,
            'artist': item.artist ?? '',
            'artUri': item.artUri?.toString() ?? '',
            'playing': isPlaying,
          })
          .catchError((Object error) {}),
    );
  }

  void _syncWidgetProgress(Duration position, Duration duration) {
    if (_disposed) return;

    unawaited(
      _widgetChannel
          .invokeMethod<void>('updateProgress', <String, Object?>{
            'position': position.inMilliseconds,
            'duration': duration.inMilliseconds,
          })
          .catchError((Object error) {}),
    );
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
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

    final callback = onPlayRequested;
    if (callback != null) {
      await callback();
      return;
    }

    if (_player.processingState == ProcessingState.completed) {
      // Una canción terminada solo puede volver a sonar desde el principio.
      if (_player.currentIndex != null && _player.currentIndex! >= 0) {
        await _player.seek(Duration.zero);
      }
    } else if (_player.processingState == ProcessingState.idle) {
      // Si el player quedó idle con una fuente cargada, conservar la posición.
      if (_player.currentIndex != null && _player.currentIndex! >= 0) {
        await _player.seek(_player.position);
      }
    }

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
    await onStopRequested?.call();
    _currentMediaItem = null;
    mediaItem.add(null);
    queue.add(const []);
    _lastWidgetSongId = null;
    _lastWidgetPlaying = false;
    unawaited(
      _widgetChannel
          .invokeMethod<void>('updatePlayback', const <String, Object?>{
            'title': '',
            'artist': '',
            'artUri': '',
            'playing': false,
          })
          .catchError((Object error) {}),
    );
    unawaited(
      _widgetChannel
          .invokeMethod<void>('updateProgress', const <String, Object?>{
            'position': 0,
            'duration': 0,
          })
          .catchError((Object error) {}),
    );

    playbackState.add(
      PlaybackState(
        controls: const [MediaControl.play],
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

    await _player.seek(target > duration ? duration : target);
  }

  // ================================================================
  // REWIND
  // ================================================================

  @override
  Future<void> rewind() async {
    if (_disposed) return;

    final target = _player.position - const Duration(seconds: 10);

    await _player.seek(target.isNegative ? Duration.zero : target);
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
    await _positionSub?.cancel();

    await _player.dispose();
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Visualizador del audio que está saliendo de la sesión de just_audio.
/// Android proporciona las bandas FFT; no se generan barras decorativas.
class AudioArtworkVisualizer extends StatefulWidget {
  const AudioArtworkVisualizer({
    super.key,
    required this.sessionIds,
    required this.initialSessionId,
    required this.isPlaying,
  });

  final Stream<int?> sessionIds;
  final int? initialSessionId;
  final bool isPlaying;

  @override
  State<AudioArtworkVisualizer> createState() => _AudioArtworkVisualizerState();
}

class _AudioArtworkVisualizerState extends State<AudioArtworkVisualizer> {
  static const _methods = MethodChannel('soundneed/visualizer');
  static const _events = EventChannel('soundneed/visualizer_data');
  static final Stream<dynamic> _eventStream =
      _events.receiveBroadcastStream().asBroadcastStream();

  StreamSubscription<dynamic>? _subscription;
  StreamSubscription<int?>? _sessionSubscription;
  int? _sessionId;
  List<double> _bands = const [];
  bool _permissionHandled = false;
  bool _started = false;
  bool _dialogVisible = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _sessionId = widget.initialSessionId;
    _sessionSubscription = widget.sessionIds.listen(_onSessionId, onError: (_) {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ready = true;
      _startIfNeeded();
    });
  }

  @override
  void didUpdateWidget(covariant AudioArtworkVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionIds != widget.sessionIds) {
      _sessionSubscription?.cancel();
      _sessionSubscription = widget.sessionIds.listen(_onSessionId, onError: (_) {});
    }
    if (oldWidget.initialSessionId != widget.initialSessionId) {
      _onSessionId(widget.initialSessionId);
    }
    if (oldWidget.isPlaying != widget.isPlaying) {
      if (widget.isPlaying) {
        _startIfNeeded();
      } else {
        _started = false;
        _bands = const [];
        _stopNative();
      }
    }
  }

  void _onSessionId(int? sessionId) {
    if (_sessionId == sessionId) return;
    _sessionId = sessionId;
    if (mounted) {
      setState(() {
        _started = false;
        _bands = const [];
      });
      _stopNative();
      _startIfNeeded();
    }
  }

  void _subscribe() {
    _subscription = _eventStream.listen((dynamic event) {
      if (!mounted || event is! List) return;
      setState(() {
        _bands = event.map((value) => (value as num).toDouble()).toList();
      });
    }, onError: (_) {});
  }

  Future<void> _startIfNeeded() async {
    final sessionId = _sessionId;
    if (!mounted ||
        !_ready ||
        !widget.isPlaying ||
        sessionId == null ||
        _started ||
        _dialogVisible) {
      return;
    }

    if (!_permissionHandled) {
      bool permissionGranted = false;
      try {
        permissionGranted =
            await _methods.invokeMethod<bool>('hasPermission') ?? false;
      } on PlatformException {
        return;
      }
      if (!mounted) return;
      if (permissionGranted) {
        _permissionHandled = true;
      }
    }

    if (!_permissionHandled) {
      _dialogVisible = true;
      final enable = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF191722),
          title: const Text('Visualizador de audio'),
          content: const Text(
            'Para dibujar las barras según la música, Android solicita el '
            'permiso de audio. SoundNeed analizará solo la reproducción de '
            'esta canción; no grabará el micrófono.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Ahora no'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      _dialogVisible = false;
      _permissionHandled = true;
      if (!mounted || enable != true) return;
    }

    try {
      final started = await _methods.invokeMethod<bool>(
        'start',
        {'sessionId': sessionId},
      );
      if (!mounted) return;
      _started = started == true;
      if (_started) setState(() {});
    } on PlatformException {
      // El permiso puede haberse rechazado o el dispositivo no admitir FFT.
    }
  }

  Future<void> _stopNative() async {
    try {
      await _methods.invokeMethod<void>('stop');
    } on PlatformException {
      // La liberación del efecto no debe interrumpir la reproducción.
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _sessionSubscription?.cancel();
    _stopNative();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_bands.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Align(
        alignment: Alignment.center,
        child: SizedBox(
          width: 30,
          height: 30,
          child: CustomPaint(painter: _SpectrumPainter(_bands)),
        ),
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  const _SpectrumPainter(this.bands);

  final List<double> bands;

  @override
  void paint(Canvas canvas, Size size) {
    if (bands.isEmpty) return;
    const count = 3;
    final gap = size.width * .14;
    final barWidth = (size.width - (gap * (count - 1))) / count;
    final baseline = size.height * .82;
    final maxHeight = size.height * .62;
    const compactBands = [3, 12, 26];

    for (var i = 0; i < count; i++) {
      final bandIndex = compactBands[i].clamp(0, bands.length - 1).toInt();
      final raw = bands[bandIndex].clamp(0.0, 1.0);
      final level = math.pow(raw, .72).toDouble();
      final height = math.max(3.0, maxHeight * level).toDouble();
      final x = (i * (barWidth + gap)).toDouble();
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, baseline - height, barWidth, height),
        Radius.circular(barWidth / 2),
      );
      final glow = Paint()
        ..color = Colors.white.withValues(alpha: .35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawRRect(rect, glow);
      canvas.drawRRect(
        rect,
        Paint()..color = Colors.white.withValues(alpha: .96),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) =>
      !identical(oldDelegate.bands, bands);
}

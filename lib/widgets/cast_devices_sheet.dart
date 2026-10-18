
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/cast_discovery_service.dart';
import 'audio_artwork_visualizer.dart';

class CastDevicesSheet extends StatefulWidget {
  final Color accentColor;
  final Color backgroundColor;
  final Future<void> Function() onTransmitCurrentSong;

  // Se conservan para no romper las llamadas existentes desde otros widgets.
  final String? currentSongTitle;
  final String? currentArtist;
  final String? currentArtworkUrl;
  final Uint8List? currentArtworkBytes;
  final Stream<int?>? audioSessionIds;
  final int? initialAudioSessionId;
  final String? activeDeviceName;
  final String? localOutputName;
  final bool isPlaying;

  const CastDevicesSheet({
    super.key,
    required this.accentColor,
    required this.backgroundColor,
    required this.onTransmitCurrentSong,
    this.currentSongTitle,
    this.currentArtist,
    this.currentArtworkUrl,
    this.currentArtworkBytes,
    this.audioSessionIds,
    this.initialAudioSessionId,
    this.activeDeviceName,
    this.localOutputName,
    this.isPlaying = false,
  });

  @override
  State<CastDevicesSheet> createState() => _CastDevicesSheetState();
}

class _CastDevicesSheetState extends State<CastDevicesSheet> {
  static const Color _surface = Color(0xFF15151D);
  static const Color _surfaceSelected = Color(0xFF1D1B18);
  static const Color _muted = Color(0xFF92929F);
  static const Color _text = Color(0xFFF0F0F5);

  Color get _gold => widget.accentColor == Colors.white
      ? const Color(0xFFD6B779)
      : widget.accentColor;

  StreamSubscription? _discoverySubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _outputSubscription;

  CastDiscoverySnapshot? _snapshot;
  CastSessionSnapshot _castSession = const CastSessionSnapshot();
  AudioOutputSnapshot _outputSnapshot = const AudioOutputSnapshot();
  List<AudioOutputRoute> _pairedBluetoothRoutes = const [];

  bool _castConnected = false;
  bool _openingPicker = false;
  bool _transmitting = false;
  bool _autoTransmitOnConnect = false;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _startDiscovery();
  }

  void _startDiscovery() {
    _discoverySubscription =
        CastDiscoveryService.instance.snapshots.listen((snapshot) {
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
    });

    _connectionSubscription =
        CastSenderService.instance.sessionChanges.listen((session) async {
      if (!mounted) return;

      setState(() {
        _castSession = session;
        _castConnected = session.connected;
      });

      if (session.connected && _autoTransmitOnConnect) {
        _autoTransmitOnConnect = false;
        await _transmit();
      }
    });

    _outputSubscription =
        AudioOutputService.instance.snapshots.listen((snapshot) {
      if (!mounted) return;
      setState(() => _outputSnapshot = snapshot);
    });

    unawaited(
      AudioOutputService.instance.getCurrent().then((snapshot) {
        if (mounted) setState(() => _outputSnapshot = snapshot);
      }).catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    _discoverySubscription?.cancel();
    _connectionSubscription?.cancel();
    _outputSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;

    setState(() => _refreshing = true);

    try {
      await CastDiscoveryService.instance.startDiscovery();

      final output = await AudioOutputService.instance.getCurrent();

      if (mounted) {
        setState(() => _outputSnapshot = output);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('No se pudieron actualizar las salidas de audio.');
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _openCastPicker() async {
    if (_openingPicker) return;

    setState(() => _openingPicker = true);
    _autoTransmitOnConnect = true;

    try {
      await CastSenderService.instance.showPicker();
    } catch (_) {
      _autoTransmitOnConnect = false;

      if (mounted) {
        _showMessage('No se pudo abrir el selector de dispositivos.');
      }
    } finally {
      if (mounted) {
        setState(() => _openingPicker = false);
      }
    }
  }

  Future<void> _transmit() async {
    if (_transmitting) return;

    setState(() => _transmitting = true);

    try {
      await widget.onTransmitCurrentSong();
    } catch (error) {
      if (mounted) {
        final details = error
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('StateError: ', '');

        _showMessage(
          details.isEmpty ? 'No se pudo iniciar Cast.' : details,
        );
      }
    } finally {
      if (mounted) setState(() => _transmitting = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF24242E),
      ),
    );
  }

  String get _songTitle {
    final remoteTitle = _castSession.title.trim();

    if (_castConnected && remoteTitle.isNotEmpty) {
      return remoteTitle;
    }

    final title = widget.currentSongTitle?.trim() ?? '';

    return title.isEmpty ? 'Sin reproducción' : title;
  }

  String get _activeName {
    if (_castConnected) {
      final remoteName = _castSession.deviceName.trim();
      return remoteName.isEmpty ? 'Dispositivo conectado' : remoteName;
    }

    final type = _outputSnapshot.selectedType.toLowerCase();
    final name = _outputSnapshot.selectedName.trim();

    if (type == 'bluetooth') {
      if (name.isEmpty || name.toLowerCase() == 'bluetooth') {
        return 'Dispositivo Bluetooth';
      }

      return name;
    }

    if (type == 'wired') {
      final lowerName = name.toLowerCase();

      if (name.isEmpty ||
          lowerName.contains('conexión por cable') ||
          lowerName.contains('conexion por cable') ||
          lowerName == 'wired' ||
          _looksLikeModelCode(name)) {
        return 'Auriculares con cable';
      }

      return name;
    }

    if (name.isNotEmpty &&
        name.toLowerCase() != 'este teléfono' &&
        name.toLowerCase() != 'this phone') {
      return name;
    }

    return 'Este teléfono';
  }

  bool get _hasSong =>
      (_castConnected && _castSession.title.trim().isNotEmpty) ||
      widget.currentSongTitle?.trim().isNotEmpty == true;

  bool get _isActuallyPlaying =>
      _castConnected ? _castSession.playing : widget.isPlaying;

  List<AudioOutputRoute> get _availableOutputRoutes {
    final connectedBluetoothNames = _outputSnapshot.routes
        .where((route) => route.type == 'bluetooth')
        .map((route) => route.name.trim().toLowerCase())
        .toSet();
    final pairedNotConnected = _pairedBluetoothRoutes.where(
      (route) => !connectedBluetoothNames.contains(route.name.trim().toLowerCase()),
    );
    return [..._outputSnapshot.routes, ...pairedNotConnected].where((route) {
      // Cuando la salida local ya está seleccionada y aparece en la
      // tarjeta principal, no hace falta duplicarla debajo.
      if (!_castConnected && route.selected) return false;

      return true;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final devices = (_snapshot?.devices ?? [])
        .where((device) => device.compatible)
        .where((device) {
          if (!_castConnected) return true;

          return device.name.trim().toLowerCase() !=
              _castSession.deviceName.trim().toLowerCase();
        }).toList();

    final routes = _availableOutputRoutes;
    final hasAlternatives = devices.isNotEmpty || routes.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(30),
        ),
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHandle(),
                const SizedBox(height: 23),
                _buildHeader(),
                const SizedBox(height: 23),

                // Dispositivo activo: siempre es el elemento principal.
                _buildSelectedDevice(),

                const SizedBox(height: 22),

                if (hasAlternatives) ...[
                  ...devices.map(_buildDiscoveredDevice),
                  ...routes.map(_buildOutputRoute),
                ] else ...[
                  _buildEmptyDevices(),
                ],

                const SizedBox(height: 17),
                _buildBluetoothBanner(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: const Color(0xFF41414B),
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: _gold.withValues(alpha: 0.24),
            ),
          ),
          child: Icon(
            Icons.graphic_eq_rounded,
            color: _gold,
            size: 25,
          ),
        ),
        const SizedBox(width: 13),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SoundNeed Connect',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.45,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Elige dónde escuchar',
                style: TextStyle(
                  color: _muted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _refreshing ? null : _refresh,
          tooltip: 'Actualizar dispositivos',
          icon: _refreshing
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _gold,
                  ),
                )
              : const Icon(
                  Icons.refresh_rounded,
                  color: _muted,
                  size: 23,
                ),
        ),
      ],
    );
  }

  Widget _buildSelectedDevice() {
    final selectedType = _outputSnapshot.selectedType.toLowerCase();

    final IconData deviceIcon = _castConnected
        ? _iconForName(_activeName)
        : selectedType == 'bluetooth' || selectedType == 'wired'
            ? _iconForOutput(_activeName, selectedType)
            : Icons.smartphone_rounded;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: _surfaceSelected,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(
          color: _gold.withValues(alpha: 0.72),
          width: 1.15,
        ),
        boxShadow: [
          BoxShadow(
            color: _gold.withValues(alpha: 0.055),
            blurRadius: 22,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _deviceIcon(
                icon: deviceIcon,
                selected: true,
                size: 59,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.35,
                      ),
                    ),
                    if (_hasSong) ...[
                      const SizedBox(height: 5),
                      _MarqueeSongTitle(
                        text: _songTitle,
                        style: TextStyle(
                          color: _gold,
                          fontSize: 12,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.audioSessionIds != null) ...[
                    AudioArtworkVisualizer(
                      sessionIds: widget.audioSessionIds!,
                      initialSessionId: widget.initialAudioSessionId,
                      isPlaying: _isActuallyPlaying && !_castConnected,
                      color: _gold,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDevices() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 18,
      ),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.045),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.devices_other_rounded,
            color: _muted.withValues(alpha: 0.9),
            size: 23,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'No hay salidas disponibles',
              style: TextStyle(
                color: _muted,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            onPressed: _refresh,
            tooltip: 'Buscar de nuevo',
            icon: Icon(
              Icons.refresh_rounded,
              color: _gold,
              size: 21,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutputRoute(AudioOutputRoute route) {
    final icon = _iconForOutput(route.name, route.type);
    final displayName = _outputRouteName(route);

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: route.selected ? null : () => _selectOutput(route),
          child: Ink(
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: route.selected ? 0.10 : 0.045),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: _gold.withValues(alpha: route.selected ? 0.42 : 0.16),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 11,
                vertical: 10,
              ),
              child: Row(
                children: [
                  _deviceIcon(
                    icon: icon,
                    selected: route.selected,
                    accented: true,
                    size: 43,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    route.selected
                        ? Icons.check_circle_rounded
                        : Icons.chevron_right_rounded,
                    color: route.selected
                        ? _gold
                        : _gold.withValues(alpha: 0.72),
                    size: 21,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _outputRouteName(AudioOutputRoute route) {
    final type = route.type.toLowerCase();
    final name = route.name.trim();
    if (type == 'phone') return 'Este teléfono';
    if (type == 'wired') return 'Auriculares con cable';
    if (type == 'bluetooth' && _looksLikeModelCode(name)) {
      return 'Auriculares inalámbricos';
    }
    return name;
  }

  bool _looksLikeModelCode(String name) =>
      RegExp(r'^(?=.*[A-Z])(?=.*\d)[A-Z0-9_-]{3,12}$')
          .hasMatch(name.toUpperCase());

  Future<void> _selectOutput(AudioOutputRoute route) async {
    try {
      await AudioOutputService.instance.select(route.id);

      final updated = await AudioOutputService.instance.getCurrent();

      if (mounted) {
        setState(() => _outputSnapshot = updated);
      }
    } catch (_) {
      _showMessage('Android no pudo cambiar la salida de audio.');
    }
  }

  Widget _buildDiscoveredDevice(CastDevice device) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: _openingPicker ? null : _openCastPicker,
          child: Ink(
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.045),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: _gold.withValues(alpha: 0.16),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 11,
                vertical: 10,
              ),
              child: Row(
                children: [
                  _deviceIcon(
                    icon: _iconForDevice(device),
                    selected: false,
                    accented: true,
                    size: 43,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _prettyProtocol(device.protocol.toString()),
                          style: const TextStyle(
                            color: Color(0xFFD6C58A),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: _gold.withValues(alpha: 0.72),
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBluetoothBanner() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _searchBluetoothDevices,
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 15,
          ),
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: 0.075),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _gold.withValues(alpha: 0.19),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.bluetooth_searching_rounded,
                  color: _gold,
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dispositivos Bluetooth',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Ver emparejados o vincular uno nuevo',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: _gold,
                size: 23,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _searchBluetoothDevices() async {
    try {
      final paired = await AudioOutputService.instance.getBondedBluetoothDevices();
      if (!mounted) return;
      setState(() => _pairedBluetoothRoutes = paired);
      if (paired.isEmpty) {
        await AudioOutputService.instance.openBluetoothSettings();
      } else {
        _showMessage('Toca un auricular de la lista para abrir Bluetooth y conectarlo.');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('No se pudieron consultar los dispositivos Bluetooth.');
      }
    }
  }

  Widget _deviceIcon({
    required IconData icon,
    required bool selected,
    bool accented = false,
    double size = 46,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: selected || accented
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _gold.withValues(alpha: selected ? 0.23 : 0.13),
                  _gold.withValues(alpha: selected ? 0.07 : 0.035),
                ],
              )
            : null,
        color: selected || accented ? null : _surface,
        border: Border.all(
          color: selected || accented
              ? _gold.withValues(alpha: selected ? 0.42 : 0.24)
              : const Color(0xFF292933),
        ),
      ),
      child: Icon(
        icon,
        color: selected || accented ? _gold : const Color(0xFFD0D0DA),
        size: size * 0.48,
      ),
    );
  }

  IconData _iconForDevice(CastDevice device) {
    final value = [
      device.name,
      device.kind.toString(),
      device.protocol.toString(),
    ].join(' ').toLowerCase();

    if (value.contains('speaker') ||
        value.contains('parlante') ||
        value.contains('altavoz') ||
        value.contains('audio')) {
      return Icons.speaker_rounded;
    }

    if (value.contains('tv') ||
        value.contains('television') ||
        value.contains('televisor') ||
        value.contains('display')) {
      return Icons.tv_rounded;
    }

    if (value.contains('bluetooth')) {
      return Icons.bluetooth_audio_rounded;
    }

    return Icons.cast_rounded;
  }

  IconData _iconForOutput(String name, String type) {
    final value = name.toLowerCase();

    if (type == 'phone') return Icons.smartphone_rounded;

    if (value.contains('airpods')) return Icons.headphones_rounded;

    if (value.contains('galaxy buds') || value.contains('buds')) {
      return Icons.earbuds_rounded;
    }

    if (value.contains('speaker') ||
        value.contains('parlante') ||
        value.contains('altavoz')) {
      return Icons.speaker_rounded;
    }

    if (type == 'bluetooth' ||
        value.contains('bluetooth') ||
        value.contains('wireless')) {
      return Icons.bluetooth_audio_rounded;
    }

    if (type == 'wired' ||
        value.contains('headphone') ||
        value.contains('audífono') ||
        value.contains('audifono') ||
        value.contains('auricular') ||
        value.contains('cable')) {
      return Icons.headphones_rounded;
    }

    return Icons.audio_file_rounded;
  }

  IconData _iconForName(String name) {
    final value = name.toLowerCase();

    if (value.contains('speaker') ||
        value.contains('parlante') ||
        value.contains('altavoz')) {
      return Icons.speaker_rounded;
    }

    if (value.contains('tv') ||
        value.contains('televisor') ||
        value.contains('television')) {
      return Icons.tv_rounded;
    }

    return Icons.cast_rounded;
  }

  String _prettyProtocol(String protocol) {
    final value = protocol.toLowerCase();

    if (value.contains('bluetooth')) return 'Bluetooth';
    if (value.contains('cast')) return 'Google Cast';
    if (value.contains('airplay')) return 'AirPlay';

    return protocol
        .replaceAll('CastProtocol.', '')
        .replaceAll('_', ' ');
  }
}

class _MarqueeSongTitle extends StatefulWidget {
  const _MarqueeSongTitle({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_MarqueeSongTitle> createState() => _MarqueeSongTitleState();
}

class _MarqueeSongTitleState extends State<_MarqueeSongTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          textDirection: Directionality.of(context),
          maxLines: 1,
        )..layout();

        if (painter.width <= constraints.maxWidth) {
          return Text(widget.text, maxLines: 1, style: widget.style);
        }

        final overflow = painter.width - constraints.maxWidth;
        _controller.duration = Duration(
          milliseconds: (2200 + overflow * 32).round(),
        );

        return ClipRect(
          child: SizedBox(
            height: painter.height,
            width: constraints.maxWidth,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) => Transform.translate(
                offset: Offset(-overflow * _controller.value, 0),
                child: child,
              ),
              child: SizedBox(
                width: painter.width,
                child: Text(
                  widget.text,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: widget.style,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/cast_discovery_service.dart';

class CastDevicesSheet extends StatefulWidget {
  final Color accentColor;
  final Color backgroundColor;
  final Future<void> Function() onTransmitCurrentSong;

  final String? currentSongTitle;
  final String? currentArtist;
  final String? currentArtworkUrl;
  final Uint8List? currentArtworkBytes;
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
    this.activeDeviceName,
    this.localOutputName,
    this.isPlaying = false,
  });

  @override
  State<CastDevicesSheet> createState() => _CastDevicesSheetState();
}

class _CastDevicesSheetState extends State<CastDevicesSheet>
    with SingleTickerProviderStateMixin {
  static const Color _surface = Color(0xFF15151D);
  static const Color _surfaceSelected = Color(0xFF1D1B18);
  static const Color _muted = Color(0xFF92929F);

  Color get _gold => widget.accentColor == Colors.white
      ? const Color(0xFFD6B779)
      : widget.accentColor;

  StreamSubscription? _discoverySubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _outputSubscription;

  CastDiscoverySnapshot? _snapshot;
  CastSessionSnapshot _castSession = const CastSessionSnapshot();
  AudioOutputSnapshot _outputSnapshot = const AudioOutputSnapshot();

  bool _castConnected = false;
  bool _openingPicker = false;
  bool _transmitting = false;
  bool _autoTransmitOnConnect = false;

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _startDiscovery();
  }

  void _startDiscovery() {
    _discoverySubscription = CastDiscoveryService.instance.snapshots.listen((
      snapshot,
    ) {
      if (!mounted) return;

      setState(() => _snapshot = snapshot);
    });

    _connectionSubscription = CastSenderService.instance.sessionChanges.listen((
      session,
    ) async {
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

    _outputSubscription = AudioOutputService.instance.snapshots.listen((
      snapshot,
    ) {
      if (mounted) setState(() => _outputSnapshot = snapshot);
    });
    unawaited(
      AudioOutputService.instance
          .getCurrent()
          .then((snapshot) {
            if (mounted) setState(() => _outputSnapshot = snapshot);
          })
          .catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    _discoverySubscription?.cancel();
    _connectionSubscription?.cancel();
    _outputSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      await CastDiscoveryService.instance.startDiscovery();
    } catch (_) {
      // No interrumpir la interfaz por un error de descubrimiento.
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
        _showMessage(details.isEmpty ? 'No se pudo iniciar Cast.' : details);
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
    if (_castConnected && remoteTitle.isNotEmpty) return remoteTitle;
    final title = widget.currentSongTitle?.trim() ?? '';
    return title.isEmpty ? 'Sin reproducción' : title;
  }

  String get _artist {
    final remoteArtist = _castSession.artist.trim();
    if (_castConnected && remoteArtist.isNotEmpty) return remoteArtist;
    final artist = widget.currentArtist?.trim() ?? '';
    return artist.isEmpty ? 'SoundNeed' : artist;
  }

  String? get _artworkUrl =>
      _castConnected && _castSession.artworkUrl.isNotEmpty
      ? _castSession.artworkUrl
      : widget.currentArtworkUrl;

  String get _activeName {
    if (_castConnected) {
      final name = _castSession.deviceName.trim();
      return name.isEmpty ? 'Dispositivo conectado' : name;
    }

    final selected = _outputSnapshot.selectedName.trim();
    return selected.isNotEmpty ? selected : 'Este teléfono';
  }

  bool get _hasSong =>
      (_castConnected && _castSession.title.trim().isNotEmpty) ||
      widget.currentSongTitle?.trim().isNotEmpty == true;

  bool get _isActuallyPlaying =>
      _castConnected ? _castSession.playing : widget.isPlaying;

  @override
  Widget build(BuildContext context) {
    final devices = (_snapshot?.devices ?? [])
        .where((device) => device.compatible)
        .where(
          (device) =>
              !_castConnected ||
              device.name.trim().toLowerCase() !=
                  _castSession.deviceName.trim().toLowerCase(),
        )
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHandle(),
              const SizedBox(height: 25),
              _buildHeader(),
              const SizedBox(height: 24),

              _buildSelectedDevice(),

              const SizedBox(height: 16),

              ...devices.map(_buildDiscoveredDevice),
              ..._availableOutputRoutes.map(_buildOutputRoute),
            ],
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
            color: const Color(0xFF191820),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFF302B22)),
          ),
          child: Icon(Icons.graphic_eq_rounded, color: _gold, size: 25),
        ),
        const SizedBox(width: 13),
        Expanded(
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
                'Salida de audio',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _refresh,
          tooltip: 'Actualizar dispositivos',
          icon: const Icon(Icons.refresh_rounded, color: _muted, size: 23),
        ),
      ],
    );
  }

  Widget _buildSelectedDevice() {
    final selectedType = _outputSnapshot.selectedType;
    final isBluetooth = !_castConnected && selectedType == 'bluetooth';
    final isWired = !_castConnected && selectedType == 'wired';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceSelected,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _gold.withValues(alpha: 0.72), width: 1.15),
        boxShadow: [
          BoxShadow(
            color: _gold.withValues(alpha: 0.055),
            blurRadius: 22,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _deviceIcon(
                icon: _castConnected
                    ? _iconForName(_activeName)
                    : isBluetooth
                    ? Icons.bluetooth_audio_rounded
                    : isWired
                    ? Icons.headphones_rounded
                    : Icons.smartphone_rounded,
                selected: true,
                size: 60,
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _castConnected
                          ? 'SoundNeed · Google Cast'
                          : isBluetooth
                          ? 'SoundNeed · Bluetooth'
                          : isWired
                          ? 'SoundNeed · Cable'
                          : 'SoundNeed · Este teléfono',
                      style: TextStyle(
                        color: _gold,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              _activeIndicator(),
            ],
          ),

          if (_hasSong) ...[
            const SizedBox(height: 17),
            Row(
              children: [
                _buildArtwork(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _songTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (_isActuallyPlaying)
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: 0.65 + _pulseController.value * 0.35,
                        child: Icon(
                          Icons.graphic_eq_rounded,
                          color: _gold,
                          size: 23,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildArtwork() {
    final url = _artworkUrl?.trim() ?? '';
    final bytes = widget.currentArtworkBytes;

    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: 43,
        height: 43,
        color: const Color(0xFF2B2930),
        child: bytes != null && bytes.isNotEmpty
            ? Image.memory(bytes, fit: BoxFit.cover)
            : url.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.music_note_rounded, color: _gold),
              )
            : Icon(Icons.music_note_rounded, color: _gold),
      ),
    );
  }

  List<AudioOutputRoute> get _availableOutputRoutes => _outputSnapshot.routes
      .where(
        (route) =>
            route.type == 'bluetooth' ||
            route.type == 'phone' ||
            route.type == 'wired',
      )
      .where((route) => !route.selected)
      .toList(growable: false);

  Widget _buildOutputRoute(AudioOutputRoute route) {
    final selected = route.selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: selected ? null : () => _selectOutput(route),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                _deviceIcon(
                  icon: switch (route.type) {
                    'bluetooth' => Icons.bluetooth_audio_rounded,
                    'wired' => Icons.headphones_rounded,
                    _ => Icons.smartphone_rounded,
                  },
                  selected: selected,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    route.type == 'phone' ? 'Este teléfono' : route.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFF0F0F5),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded, color: _gold, size: 20)
                else
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF777783),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectOutput(AudioOutputRoute route) async {
    try {
      await AudioOutputService.instance.select(route.id);
    } catch (_) {
      _showMessage('Android no pudo cambiar la salida de audio.');
    }
  }

  Widget _activeIndicator() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final opacity = 0.45 + (_pulseController.value * 0.55);

        return Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _gold.withValues(alpha: 0.10),
            border: Border.all(color: _gold.withValues(alpha: opacity)),
          ),
          child: Icon(Icons.graphic_eq_rounded, size: 19, color: _gold),
        );
      },
    );
  }

  Widget _deviceIcon({
    required IconData icon,
    required bool selected,
    double size = 46,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: selected
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF383126), Color(0xFF211E19)],
              )
            : null,
        color: selected ? null : _surface,
        border: Border.all(
          color: selected
              ? _gold.withValues(alpha: 0.32)
              : const Color(0xFF292933),
        ),
      ),
      child: Icon(
        icon,
        color: selected ? _gold : const Color(0xFFD0D0DA),
        size: size * 0.48,
      ),
    );
  }

  Widget _buildDiscoveredDevice(CastDevice device) {
    final name = device.name;
    final icon = _iconForDevice(device);
    final protocol = device.protocol.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _openingPicker ? null : _openCastPicker,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Row(
              children: [
                _deviceIcon(icon: icon, selected: false),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFF0F0F5),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _prettyProtocol(protocol),
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF777783),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
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
      return Icons.speaker_rounded;
    }

    return Icons.cast_rounded;
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

    return protocol.replaceAll('CastProtocol.', '').replaceAll('_', ' ');
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/cast_discovery_service.dart';

class CastDevicesSheet extends StatefulWidget {
  final Color accentColor;
  final Color backgroundColor;
  final Future<void> Function() onTransmitCurrentSong;

  const CastDevicesSheet({
    super.key,
    required this.accentColor,
    required this.backgroundColor,
    required this.onTransmitCurrentSong,
  });

  @override
  State<CastDevicesSheet> createState() => _CastDevicesSheetState();
}

class _CastDevicesSheetState extends State<CastDevicesSheet> {
  StreamSubscription<CastDiscoverySnapshot>? _subscription;
  StreamSubscription<bool>? _castSubscription;
  CastDiscoverySnapshot _snapshot = const CastDiscoverySnapshot(
    scanning: true,
    devices: [],
  );
  String? _error;
  bool _castConnected = false;
  bool _openingPicker = false;
  bool _transmitting = false;

  @override
  void initState() {
    super.initState();
    _subscription = CastDiscoveryService.instance.snapshots.listen(
      (snapshot) {
        if (mounted) setState(() => _snapshot = snapshot);
      },
      onError: (Object error) {
        if (mounted) {
          setState(() {
            _error = 'No se pudo buscar en la red local.';
            _snapshot = const CastDiscoverySnapshot(
              scanning: false,
              devices: [],
            );
          });
        }
      },
    );
    _castSubscription = CastSenderService.instance.connectionChanges.listen(
      (connected) {
        if (mounted) setState(() => _castConnected = connected);
      },
    );
    unawaited(_startDiscovery());
  }

  Future<void> _startDiscovery() async {
    setState(() {
      _error = null;
      _snapshot = const CastDiscoverySnapshot(scanning: true, devices: []);
    });
    try {
      await CastDiscoveryService.instance.startDiscovery();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo iniciar la búsqueda de dispositivos.';
        _snapshot = const CastDiscoverySnapshot(scanning: false, devices: []);
      });
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_castSubscription?.cancel());
    unawaited(CastDiscoveryService.instance.stopDiscovery());
    super.dispose();
  }

  Future<void> _openCastPicker() async {
    setState(() => _openingPicker = true);
    try {
      await CastSenderService.instance.showPicker();
    } catch (error) {
      _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _openingPicker = false);
    }
  }

  Future<void> _transmit() async {
    setState(() => _transmitting = true);
    try {
      await widget.onTransmitCurrentSong();
    } catch (error) {
      _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _transmitting = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message.replaceFirst('PlatformException(', '').split(')')[0])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compatible = _snapshot.devices
        .where((device) => device.compatible)
        .toList();
    final discovered = _snapshot.devices
        .where((device) => !device.compatible)
        .toList();

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.82,
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.24),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 18, 12),
              child: Row(
                children: [
                  Icon(Icons.cast, color: widget.accentColor, size: 26),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Transmitir a',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Dispositivos de tu red local',
                          style: TextStyle(color: Colors.white60, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Buscar de nuevo',
                    onPressed: _snapshot.scanning ? null : _startDiscovery,
                    icon: Icon(
                      Icons.refresh_rounded,
                      color: _snapshot.scanning
                          ? Colors.white30
                          : Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            if (_snapshot.scanning)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: widget.accentColor,
                      ),
                    ),
                    const SizedBox(width: 11),
                    const Text(
                      'Buscando dispositivos…',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _openingPicker ? null : _openCastPicker,
                    icon: _openingPicker
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cast),
                    label: Text(_castConnected ? 'Google Cast conectado' : 'Buscar dispositivos Google Cast'),
                  ),
                  if (_castConnected) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _transmitting ? null : _transmit,
                      icon: _transmitting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.play_arrow_rounded),
                      label: const Text('Transmitir canción actual'),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _error != null
                  ? ListView(
                      children: [_messageCard(Icons.wifi_off_rounded, _error!)],
                    )
                  : ListView(
                      children: [
                        if (_snapshot.permissionRequired)
                          _messageCard(
                            Icons.lock_outline_rounded,
                            'Permite a SoundNeed acceder a la red local y vuelve a buscar.',
                          ),
                        _sectionTitle('COMPATIBLES', compatible.length),
                        if (compatible.isEmpty)
                          _messageCard(
                            Icons.cast_connected_rounded,
                            _snapshot.scanning
                                ? 'Buscando dispositivos Google Cast…'
                                : 'No se detectaron servicios Google Cast en la red. Usa el selector oficial de arriba para buscar de nuevo.',
                          )
                        else
                          ...compatible.map(_deviceTile),
                        _sectionTitle('EN LA RED', discovered.length),
                        if (discovered.isEmpty && !_snapshot.scanning)
                          _messageCard(
                            Icons.devices_other_rounded,
                            'No se detectaron dispositivos que anuncien servicios de red compatibles.',
                          )
                        else
                          ...discovered.map(_deviceTile),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
              child: Text(
                _castConnected
                    ? 'Google Cast usa el reproductor estándar del televisor. La app SoundNeed personalizada requiere un receptor propio.'
                    : 'La búsqueda oficial de Google Cast aparece arriba. La lista inferior sólo informa de equipos detectados en la red.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, int count) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 18, 22, 7),
    child: Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10,
            letterSpacing: 1.15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$count',
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
      ],
    ),
  );

  Widget _messageCard(IconData icon, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 4, 18, 2),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 18),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _deviceTile(CastDevice device) => ListTile(
    dense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 1),
    leading: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(_iconFor(device.kind), color: widget.accentColor, size: 21),
    ),
    title: Text(
      device.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      '${device.kind} · ${device.protocol}\n${device.status}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.white54, height: 1.3, fontSize: 11),
    ),
    isThreeLine: true,
    trailing: Icon(
      device.compatible ? Icons.cast_rounded : Icons.info_outline_rounded,
      color: device.compatible ? widget.accentColor : Colors.white38,
      size: 19,
    ),
    onTap: device.compatible
        ? _openCastPicker
        : () => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.backgroundColor,
        title: Text(device.name, style: const TextStyle(color: Colors.white)),
        content: Text(
          '${device.kind}\n${device.protocol}\n${device.status}\n\nSoundNeed detectó este equipo en la red. La conexión requiere que el dispositivo admita un receptor compatible.',
          style: const TextStyle(color: Colors.white70, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Entendido',
              style: TextStyle(color: widget.accentColor),
            ),
          ),
        ],
      ),
    ),
  );

  IconData _iconFor(String kind) {
    final value = kind.toLowerCase();
    if (value.contains('tv') ||
        value.contains('televisor') ||
        value.contains('pantalla')) {
      return Icons.tv_rounded;
    }
    if (value.contains('audio') || value.contains('altavoz')) {
      return Icons.speaker_rounded;
    }
    if (value.contains('pc') || value.contains('ordenador')) {
      return Icons.computer_rounded;
    }
    return Icons.devices_rounded;
  }
}

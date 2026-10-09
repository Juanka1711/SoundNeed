import 'dart:async';

import 'package:flutter/services.dart';

class CastDevice {
  final String id;
  final String name;
  final String host;
  final String kind;
  final String protocol;
  final bool compatible;
  final String status;

  const CastDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.kind,
    required this.protocol,
    required this.compatible,
    required this.status,
  });

  factory CastDevice.fromMap(Map<Object?, Object?> value) => CastDevice(
    id: value['id']?.toString() ?? '',
    name: value['name']?.toString() ?? 'Dispositivo de red',
    host: value['host']?.toString() ?? '',
    kind: value['kind']?.toString() ?? 'Dispositivo de red',
    protocol: value['protocol']?.toString() ?? 'Desconocido',
    compatible: value['compatible'] == true,
    status: value['status']?.toString() ?? 'Compatibilidad por comprobar',
  );
}

class CastDiscoverySnapshot {
  final bool scanning;
  final bool permissionRequired;
  final List<CastDevice> devices;

  const CastDiscoverySnapshot({
    required this.scanning,
    required this.devices,
    this.permissionRequired = false,
  });

  factory CastDiscoverySnapshot.fromMap(Map<Object?, Object?> value) {
    final rawDevices = value['devices'];
    return CastDiscoverySnapshot(
      scanning: value['scanning'] == true,
      permissionRequired: value['permissionRequired'] == true,
      devices: rawDevices is List
          ? rawDevices
                .whereType<Map<Object?, Object?>>()
                .map(CastDevice.fromMap)
                .toList(growable: false)
          : const [],
    );
  }
}

class CastDiscoveryService {
  CastDiscoveryService._();

  static final CastDiscoveryService instance = CastDiscoveryService._();
  static const MethodChannel _methods = MethodChannel('soundneed/cast');
  static const EventChannel _events = EventChannel('soundneed/cast/events');
  static final Stream<CastDiscoverySnapshot> _snapshots = _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map(
        (event) => CastDiscoverySnapshot.fromMap(
          Map<Object?, Object?>.from(event as Map),
        ),
      )
      .asBroadcastStream();

  Stream<CastDiscoverySnapshot> get snapshots => _snapshots;

  Future<void> startDiscovery() =>
      _methods.invokeMethod<void>('startDiscovery');

  Future<void> stopDiscovery() => _methods.invokeMethod<void>('stopDiscovery');
}

class CastSenderService {
  CastSenderService._();
  static final CastSenderService instance = CastSenderService._();
  static const MethodChannel _methods = MethodChannel('soundneed/cast_sender');
  static const EventChannel _events = EventChannel('soundneed/cast/session');
  static final Stream<bool> _connections = _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => (event as Map)['connected'] == true)
      .asBroadcastStream();

  Stream<bool> get connectionChanges => _connections;

  Future<void> showPicker() => _methods.invokeMethod<void>('showPicker');

  Future<void> loadMedia({
    required String url,
    required String title,
    required String artist,
    required String artwork,
    required String contentType,
  }) => _methods.invokeMethod<void>('loadMedia', {
    'url': url,
    'title': title,
    'artist': artist,
    'artwork': artwork,
    'contentType': contentType,
  });

  Future<void> play() => _methods.invokeMethod<void>('play');
  Future<void> pause() => _methods.invokeMethod<void>('pause');
  Future<void> seek(Duration position) =>
      _methods.invokeMethod<void>('seek', {'positionMs': position.inMilliseconds});
  Future<void> stop() => _methods.invokeMethod<void>('stop');
}

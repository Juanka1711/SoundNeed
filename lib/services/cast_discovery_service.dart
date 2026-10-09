import 'dart:async';
import 'dart:typed_data';

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

class CastSessionSnapshot {
  final bool connected;
  final String deviceName;
  final bool playing;
  final bool ended;
  final String title;
  final String artist;
  final String artworkUrl;
  final String contentId;
  final int positionMs;
  final int durationMs;

  const CastSessionSnapshot({
    this.connected = false,
    this.deviceName = '',
    this.playing = false,
    this.ended = false,
    this.title = '',
    this.artist = '',
    this.artworkUrl = '',
    this.contentId = '',
    this.positionMs = 0,
    this.durationMs = 0,
  });

  factory CastSessionSnapshot.fromMap(Map<Object?, Object?> value) =>
      CastSessionSnapshot(
        connected: value['connected'] == true,
        deviceName: value['deviceName']?.toString() ?? '',
        playing: value['playing'] == true,
        ended: value['ended'] == true,
        title: value['title']?.toString() ?? '',
        artist: value['artist']?.toString() ?? '',
        artworkUrl: value['artworkUrl']?.toString() ?? '',
        contentId: value['contentId']?.toString() ?? '',
        positionMs: (value['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (value['durationMs'] as num?)?.toInt() ?? 0,
      );
}

class AudioOutputRoute {
  final String id;
  final String name;
  final String type;
  final bool selected;

  const AudioOutputRoute({
    required this.id,
    required this.name,
    required this.type,
    required this.selected,
  });

  factory AudioOutputRoute.fromMap(Map<Object?, Object?> value) =>
      AudioOutputRoute(
        id: value['id']?.toString() ?? '',
        name: value['name']?.toString() ?? 'Salida de audio',
        type: value['type']?.toString() ?? 'unknown',
        selected: value['selected'] == true,
      );
}

class AudioOutputSnapshot {
  final String selectedName;
  final String selectedType;
  final List<AudioOutputRoute> routes;

  const AudioOutputSnapshot({
    this.selectedName = 'Este teléfono',
    this.selectedType = 'phone',
    this.routes = const [],
  });

  factory AudioOutputSnapshot.fromMap(Map<Object?, Object?> value) {
    final rawRoutes = value['routes'];
    return AudioOutputSnapshot(
      selectedName: value['selectedName']?.toString() ?? 'Este teléfono',
      selectedType: value['selectedType']?.toString() ?? 'phone',
      routes: rawRoutes is List
          ? rawRoutes
                .whereType<Map<Object?, Object?>>()
                .map(AudioOutputRoute.fromMap)
                .toList(growable: false)
          : const [],
    );
  }
}

class CastSenderService {
  CastSenderService._();
  static final CastSenderService instance = CastSenderService._();
  static const MethodChannel _methods = MethodChannel('soundneed/cast_sender');
  static const EventChannel _events = EventChannel('soundneed/cast/session');
  static final Stream<CastSessionSnapshot> _sessions = _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map(
        (event) => CastSessionSnapshot.fromMap(
          Map<Object?, Object?>.from(event as Map),
        ),
      )
      .asBroadcastStream();

  Stream<CastSessionSnapshot> get sessionChanges => _sessions;

  Future<void> showPicker() => _methods.invokeMethod<void>('showPicker');

  Future<Map<String, String>> prepareLocalMedia({
    required String uri,
    required String contentType,
    Uint8List? artwork,
  }) async {
    final result = await _methods.invokeMapMethod<String, dynamic>(
      'prepareLocalMedia', {
        'uri': uri,
        'contentType': contentType,
        'artwork': artwork,
      },
    );
    final mediaUrl = result?['url']?.toString() ?? '';
    if (mediaUrl.isEmpty) {
      throw StateError('Android no devolvió la dirección del audio local.');
    }
    return result!.map((key, value) => MapEntry(key, value?.toString() ?? ''));
  }

  Future<void> loadMedia({
    required String url,
    required String title,
    required String artist,
    required String artwork,
    required String contentType,
    bool isVideo = false,
  }) => _methods.invokeMethod<void>('loadMedia', {
    'url': url,
    'title': title,
    'artist': artist,
    'artwork': artwork,
    'contentType': contentType,
    'isVideo': isVideo,
  });

  Future<void> play() => _methods.invokeMethod<void>('play');
  Future<void> pause() => _methods.invokeMethod<void>('pause');
  Future<void> seek(Duration position) => _methods.invokeMethod<void>('seek', {
    'positionMs': position.inMilliseconds,
  });
  Future<void> stop() => _methods.invokeMethod<void>('stop');
}

class AudioOutputService {
  AudioOutputService._();
  static final AudioOutputService instance = AudioOutputService._();
  static const MethodChannel _methods = MethodChannel('soundneed/audio_output');
  static const EventChannel _events = EventChannel(
    'soundneed/audio_output/events',
  );
  static final Stream<AudioOutputSnapshot> _snapshots = _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map(
        (event) => AudioOutputSnapshot.fromMap(
          Map<Object?, Object?>.from(event as Map),
        ),
      )
      .asBroadcastStream();

  Stream<AudioOutputSnapshot> get snapshots => _snapshots;

  Future<AudioOutputSnapshot> getCurrent() async {
    final result = await _methods.invokeMapMethod<Object?, Object?>(
      'getCurrent',
    );
    return AudioOutputSnapshot.fromMap(result ?? const {});
  }

  Future<void> select(String routeId) =>
      _methods.invokeMethod<void>('select', {'routeId': routeId});
}

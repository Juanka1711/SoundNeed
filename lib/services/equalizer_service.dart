import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EqualizerBand {
  const EqualizerBand({
    required this.index,
    required this.frequencyHz,
    required this.levelMb,
    required this.minimumMb,
    required this.maximumMb,
  });

  final int index;
  final int frequencyHz;
  final int levelMb;
  final int minimumMb;
  final int maximumMb;

  EqualizerBand copyWith({int? levelMb}) => EqualizerBand(
    index: index,
    frequencyHz: frequencyHz,
    levelMb: levelMb ?? this.levelMb,
    minimumMb: minimumMb,
    maximumMb: maximumMb,
  );
}

class EqualizerPreset {
  const EqualizerPreset({required this.id, required this.name});

  final int id;
  final String name;
}

/// Android audio-session equalizer shared by the full player and playback.
class EqualizerService extends ChangeNotifier {
  EqualizerService._();

  static final EqualizerService instance = EqualizerService._();
  static const _channel = MethodChannel('soundneed/equalizer');
  static const _stateKey = 'soundneed_equalizer_state_v1';
  static const soundModes = [
    'Neutro',
    'Graves',
    'Voces',
    'Agudos',
    'Auriculares',
  ];

  List<EqualizerBand> bands = const [];
  List<EqualizerPreset> presets = const [];
  bool available = false;
  bool enabled = false;
  bool loading = false;
  String? selectedPreset;
  String? error;
  int? _sessionId;
  int _bindGeneration = 0;
  Timer? _persistTimer;

  Future<void> bindSession(int? sessionId) async {
    if (_sessionId == sessionId && (available || loading)) return;
    _sessionId = sessionId;
    final generation = ++_bindGeneration;
    _persistTimer?.cancel();
    available = false;
    bands = const [];
    presets = const [];
    error = null;

    if (defaultTargetPlatform != TargetPlatform.android ||
        sessionId == null ||
        sessionId <= 0) {
      loading = false;
      notifyListeners();
      return;
    }

    loading = true;
    notifyListeners();
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>('open', {
        'sessionId': sessionId,
      });
      if (generation != _bindGeneration) return;
      if (raw == null || raw['supported'] != true) {
        available = false;
        error = 'Este dispositivo no ofrece un ecualizador compatible.';
        return;
      }

      final minimum = (raw['minimumMb'] as num?)?.toInt() ?? -1500;
      final maximum = (raw['maximumMb'] as num?)?.toInt() ?? 1500;
      bands = ((raw['bands'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) => EqualizerBand(
              index: (item['index'] as num?)?.toInt() ?? 0,
              frequencyHz: (item['frequencyHz'] as num?)?.toInt() ?? 0,
              levelMb: (item['levelMb'] as num?)?.toInt() ?? 0,
              minimumMb: minimum,
              maximumMb: maximum,
            ),
          )
          .toList(growable: false);
      presets = ((raw['presets'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) => EqualizerPreset(
              id: (item['id'] as num?)?.toInt() ?? -1,
              name: item['name']?.toString() ?? 'Preset',
            ),
          )
          .toList(growable: false);
      available = bands.isNotEmpty;
      if (!available) {
        error = 'No se encontraron bandas de ecualización.';
        return;
      }

      await _restoreSettings(generation);
    } on PlatformException catch (exception) {
      if (generation == _bindGeneration) {
        available = false;
        error =
            exception.message ??
            'No se pudo conectar el ecualizador al reproductor.';
      }
    } catch (exception) {
      if (generation == _bindGeneration) {
        available = false;
        error = 'No se pudo iniciar el ecualizador: $exception';
      }
    } finally {
      if (generation == _bindGeneration) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _restoreSettings(int generation) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_stateKey);
    if (raw == null) {
      enabled = false;
      selectedPreset = 'Personalizado';
      return;
    }

    final stored = jsonDecode(raw) as Map<String, dynamic>;
    enabled = stored['enabled'] == true;
    final presetName = stored['preset']?.toString();
    final matchingPresets = presets.where((item) => item.name == presetName);
    final preset = matchingPresets.isEmpty ? null : matchingPresets.first;
    if (preset != null) {
      final levels = await _channel.invokeListMethod<int>('usePreset', {
        'presetId': preset.id,
      });
      if (generation != _bindGeneration) return;
      selectedPreset = preset.name;
      if (levels != null) _applyReturnedLevels(levels);
    } else {
      selectedPreset = soundModes.contains(presetName)
          ? presetName
          : 'Personalizado';
      final savedBands = stored['bands'];
      if (savedBands is Map) {
        for (final band in bands) {
          final savedLevel = (savedBands['${band.frequencyHz}'] as num?)
              ?.toInt();
          if (savedLevel != null) {
            final level = savedLevel
                .clamp(band.minimumMb, band.maximumMb)
                .toInt();
            await _channel.invokeMethod<void>('setBandLevel', {
              'band': band.index,
              'levelMb': level,
            });
            if (generation != _bindGeneration) return;
            _replaceBand(band.index, level);
          }
        }
      }
    }
    await _channel.invokeMethod<void>('setEnabled', {'enabled': enabled});
  }

  Future<void> setEnabled(bool value) async {
    if (!available) return;
    try {
      await _channel.invokeMethod<void>('setEnabled', {'enabled': value});
      enabled = value;
      notifyListeners();
      await _persist();
    } on PlatformException catch (exception) {
      error = exception.message ?? 'No se pudo cambiar el ecualizador.';
      notifyListeners();
    }
  }

  Future<void> selectPreset(EqualizerPreset preset) async {
    if (!available) return;
    try {
      final levels = await _channel.invokeListMethod<int>('usePreset', {
        'presetId': preset.id,
      });
      await _channel.invokeMethod<void>('setEnabled', {'enabled': true});
      enabled = true;
      selectedPreset = preset.name;
      if (levels != null) _applyReturnedLevels(levels);
      notifyListeners();
      await _persist();
    } on PlatformException catch (exception) {
      error = exception.message ?? 'No se pudo aplicar este modo de sonido.';
      notifyListeners();
    }
  }

  Future<void> selectSoundMode(String mode) async {
    if (!available || !soundModes.contains(mode)) return;
    final levels = [
      for (final band in bands)
        _profileLevel(
          mode,
          band.frequencyHz,
        ).clamp(band.minimumMb, band.maximumMb).toInt(),
    ];
    try {
      final applied = await _channel.invokeListMethod<int>('setBandLevels', {
        'levelsMb': levels,
      });
      await _channel.invokeMethod<void>('setEnabled', {'enabled': true});
      enabled = true;
      selectedPreset = mode;
      if (applied != null) {
        _applyReturnedLevels(applied);
      } else {
        bands = [
          for (var index = 0; index < bands.length; index++)
            bands[index].copyWith(levelMb: levels[index]),
        ];
      }
      error = null;
      notifyListeners();
      await _persist();
    } on PlatformException catch (exception) {
      error = exception.message ?? 'No se pudo aplicar este modo de sonido.';
      notifyListeners();
    }
  }

  int _profileLevel(String mode, int frequencyHz) {
    switch (mode) {
      case 'Graves':
        if (frequencyHz <= 100) return 650;
        if (frequencyHz <= 250) return 400;
        if (frequencyHz <= 500) return 150;
        return 0;
      case 'Voces':
        if (frequencyHz < 250) return -100;
        if (frequencyHz <= 4000) return 350;
        if (frequencyHz <= 8000) return 100;
        return 0;
      case 'Agudos':
        if (frequencyHz <= 100) return -100;
        if (frequencyHz < 1500) return 0;
        if (frequencyHz < 4000) return 200;
        return 550;
      case 'Auriculares':
        if (frequencyHz <= 120) return 250;
        if (frequencyHz < 500) return -100;
        if (frequencyHz <= 4000) return 150;
        if (frequencyHz >= 8000) return 100;
        return 0;
      default:
        return 0;
    }
  }

  Future<void> setBandLevel(int index, int value) async {
    if (!available || index < 0 || index >= bands.length) return;
    final band = bands[index];
    final level = value.clamp(band.minimumMb, band.maximumMb).toInt();
    _replaceBand(index, level);
    selectedPreset = 'Personalizado';
    notifyListeners();
    try {
      await _channel.invokeMethod<void>('setBandLevel', {
        'band': band.index,
        'levelMb': level,
      });
      if (!enabled) {
        await _channel.invokeMethod<void>('setEnabled', {'enabled': true});
        enabled = true;
        notifyListeners();
      }
      _schedulePersist();
    } on PlatformException catch (exception) {
      error = exception.message ?? 'No se pudo ajustar esta banda.';
      notifyListeners();
    }
  }

  Future<void> reset() async {
    if (!available) return;
    try {
      final levels = await _channel.invokeListMethod<int>('reset');
      if (levels != null) {
        _applyReturnedLevels(levels);
      } else {
        bands = bands.map((band) => band.copyWith(levelMb: 0)).toList();
      }
      selectedPreset = 'Personalizado';
      notifyListeners();
      await _persist();
    } on PlatformException catch (exception) {
      error = exception.message ?? 'No se pudo reiniciar el ecualizador.';
      notifyListeners();
    }
  }

  void _replaceBand(int index, int level) {
    bands = bands
        .map(
          (band) => band.index == index ? band.copyWith(levelMb: level) : band,
        )
        .toList(growable: false);
  }

  void _applyReturnedLevels(List<int> levels) {
    bands = [
      for (var index = 0; index < bands.length; index++)
        bands[index].copyWith(
          levelMb: index < levels.length
              ? levels[index]
                    .clamp(bands[index].minimumMb, bands[index].maximumMb)
                    .toInt()
              : bands[index].levelMb,
        ),
    ];
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_persist());
    });
  }

  Future<void> _persist() async {
    final preferences = await SharedPreferences.getInstance();
    final levels = {
      for (final band in bands) '${band.frequencyHz}': band.levelMb,
    };
    await preferences.setString(
      _stateKey,
      jsonEncode({
        'enabled': enabled,
        'preset': selectedPreset,
        'bands': levels,
      }),
    );
  }

  Future<void> release() async {
    ++_bindGeneration;
    _sessionId = null;
    _persistTimer?.cancel();
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod<void>('close');
      } on PlatformException {
        // The native effect may already have been released by Android.
      }
    }
    available = false;
    bands = const [];
    presets = const [];
    loading = false;
    notifyListeners();
  }
}

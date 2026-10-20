import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum NotificationCategory {
  downloads,
  imports,
  library,
  news,
  errors,
  maintenance,
}

extension NotificationCategoryInfo on NotificationCategory {
  String get label => switch (this) {
    NotificationCategory.downloads => 'Descargas',
    NotificationCategory.imports => 'Importaciones',
    NotificationCategory.library => 'Biblioteca',
    NotificationCategory.news => 'Novedades',
    NotificationCategory.errors => 'Atención',
    NotificationCategory.maintenance => 'Mantenimiento',
  };

  IconData get icon => switch (this) {
    NotificationCategory.downloads => Icons.download_done_rounded,
    NotificationCategory.imports => Icons.playlist_add_rounded,
    NotificationCategory.library => Icons.library_music_rounded,
    NotificationCategory.news => Icons.auto_awesome_rounded,
    NotificationCategory.errors => Icons.error_outline_rounded,
    NotificationCategory.maintenance => Icons.build_circle_outlined,
  };
}

enum NotificationPriority { low, normal, high }

enum NotificationStatus { ongoing, completed, failed }

@immutable
class NotificationNavigationRequest {
  const NotificationNavigationRequest({
    required this.destination,
    this.notificationId,
  });

  final String destination;
  final String? notificationId;
}

/// Generic notification event contract. Remote push adapters can publish the
/// same draft later without coupling SoundNeed to a push provider.
class NotificationDraft {
  const NotificationDraft({
    required this.category,
    required this.title,
    required this.description,
    this.deduplicationKey,
    this.eventType = 'general',
    this.destination,
    this.priority = NotificationPriority.normal,
    this.status = NotificationStatus.completed,
    this.progress,
    this.metadata = const <String, Object?>{},
  });

  final NotificationCategory category;
  final String title;
  final String description;
  final String? deduplicationKey;
  final String eventType;
  final String? destination;
  final NotificationPriority priority;
  final NotificationStatus status;
  final int? progress;
  final Map<String, Object?> metadata;
}

abstract interface class NotificationEventSource {
  Stream<NotificationDraft> get events;
}

@immutable
class SoundNeedNotification {
  const SoundNeedNotification({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
    required this.isRead,
    required this.eventType,
    required this.priority,
    required this.status,
    required this.metadata,
    this.deduplicationKey,
    this.destination,
    this.progress,
  });

  final String id;
  final String? deduplicationKey;
  final NotificationCategory category;
  final String title;
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isRead;
  final String eventType;
  final String? destination;
  final NotificationPriority priority;
  final NotificationStatus status;
  final int? progress;
  final Map<String, Object?> metadata;

  bool get isOngoing => status == NotificationStatus.ongoing;

  SoundNeedNotification copyWith({
    String? title,
    String? description,
    DateTime? updatedAt,
    bool? isRead,
    String? eventType,
    NotificationStatus? status,
    int? progress,
    bool clearProgress = false,
    Map<String, Object?>? metadata,
  }) => SoundNeedNotification(
    id: id,
    deduplicationKey: deduplicationKey,
    category: category,
    title: title ?? this.title,
    description: description ?? this.description,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isRead: isRead ?? this.isRead,
    eventType: eventType ?? this.eventType,
    destination: destination,
    priority: priority,
    status: status ?? this.status,
    progress: clearProgress ? null : progress ?? this.progress,
    metadata: metadata ?? this.metadata,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'deduplicationKey': deduplicationKey,
    'category': category.name,
    'title': title,
    'description': description,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'isRead': isRead,
    'eventType': eventType,
    'destination': destination,
    'priority': priority.name,
    'status': status.name,
    'progress': progress,
    'metadata': metadata,
  };

  factory SoundNeedNotification.fromJson(Map<String, Object?> json) {
    T parseEnum<T extends Enum>(List<T> values, String key, T fallback) =>
        values.firstWhere(
          (value) => value.name == json[key],
          orElse: () => fallback,
        );

    final now = DateTime.now();
    final createdMs = json['createdAt'] as int?;
    final updatedMs = json['updatedAt'] as int?;
    final metadata = json['metadata'];
    return SoundNeedNotification(
      id: json['id'] as String? ?? '',
      deduplicationKey: json['deduplicationKey'] as String?,
      category: parseEnum(
        NotificationCategory.values,
        'category',
        NotificationCategory.library,
      ),
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      createdAt: createdMs == null
          ? now
          : DateTime.fromMillisecondsSinceEpoch(createdMs),
      updatedAt: updatedMs == null
          ? now
          : DateTime.fromMillisecondsSinceEpoch(updatedMs),
      isRead: json['isRead'] as bool? ?? false,
      eventType: json['eventType'] as String? ?? 'general',
      destination: json['destination'] as String?,
      priority: parseEnum(
        NotificationPriority.values,
        'priority',
        NotificationPriority.normal,
      ),
      status: parseEnum(
        NotificationStatus.values,
        'status',
        NotificationStatus.completed,
      ),
      progress: json['progress'] as int?,
      metadata: metadata is Map
          ? metadata.map((key, value) => MapEntry('$key', value))
          : const <String, Object?>{},
    );
  }
}

/// Persistent in-app notification history and Android notification gateway.
class NotificationService extends ChangeNotifier {
  NotificationService({
    SharedPreferences? preferences,
    MethodChannel channel = const MethodChannel('soundneed/notifications'),
    EventChannel? navigationChannel = const EventChannel(
      'soundneed/notification_navigation',
    ),
    DateTime Function()? clock,
  }) : _preferences = preferences,
       _channel = channel,
       _navigationChannel = navigationChannel,
       _clock = clock ?? DateTime.now;

  static final NotificationService instance = NotificationService();

  static const _historyKey = 'soundneed.general_notifications.history.v1';
  static const _categorySettingsKey =
      'soundneed.general_notifications.categories.v1';
  static const _destinationRoutes = <String>{
    'home',
    'songs',
    'playlists',
    'notifications',
    'settings',
  };
  static const _retention = Duration(days: 90);
  static const _maximumRecords = 300;

  static bool isValidDestination(String destination) =>
      _destinationRoutes.contains(destination);

  static String stableDeduplicationKey(String prefix, String value) =>
      '$prefix:${_stableInt(value).toRadixString(16)}';

  SharedPreferences? _preferences;
  final MethodChannel _channel;
  final EventChannel? _navigationChannel;
  final DateTime Function() _clock;
  final List<SoundNeedNotification> _records = [];
  final Map<NotificationCategory, bool> _categorySettings = {};
  final List<String> _diagnostics = [];
  final StreamController<NotificationNavigationRequest> _navigationRequests =
      StreamController<NotificationNavigationRequest>.broadcast();
  StreamSubscription<Object?>? _nativeNavigationSubscription;
  StreamSubscription<NotificationDraft>? _eventSourceSubscription;
  List<NotificationNavigationRequest> _pendingNavigation = [];
  bool _initialized = false;
  bool _isLoading = false;
  Future<void>? _initialization;
  String? _error;
  int _idCounter = 0;

  List<SoundNeedNotification> get records =>
      List<SoundNeedNotification>.unmodifiable(_records);
  List<String> get diagnostics => List<String>.unmodifiable(_diagnostics);
  Stream<NotificationNavigationRequest> get navigationRequests =>
      _navigationRequests.stream;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get unreadCount => _records.where((item) => !item.isRead).length;

  SoundNeedNotification? findById(String id) {
    for (final record in _records) {
      if (record.id == id) return record;
    }
    return null;
  }

  SoundNeedNotification? findByNotificationId(String id) {
    final directMatch = findById(id);
    if (directMatch != null) return directMatch;
    final numericId = int.tryParse(id);
    if (numericId == null) return null;
    for (final record in _records) {
      if (_stableInt(record.id) == numericId) return record;
    }
    return null;
  }

  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _preferences ??= await SharedPreferences.getInstance();
      await _loadHistory();
      _loadCategorySettings();
      _purgeExpired();
      await _persist();
      try {
        await _channel.invokeMethod<bool>('initialize');
      } catch (error, stackTrace) {
        _diagnose(
          'No se pudieron preparar los canales Android',
          error,
          stackTrace,
        );
      }
      _nativeNavigationSubscription ??= _navigationChannel
          ?.receiveBroadcastStream()
          .listen(
            handleNativeNavigation,
            onError: (Object error, StackTrace stack) {
              _diagnose(
                'Error en la navegación de notificaciones',
                error,
                stack,
              );
            },
          );
      _initialized = true;
    } catch (error, stackTrace) {
      _error = error.toString();
      _diagnose(
        'No se pudo cargar el historial de notificaciones',
        error,
        stackTrace,
      );
    } finally {
      _isLoading = false;
      _initialization = null;
      notifyListeners();
    }
  }

  Future<void> retryInitialization() async {
    _initialized = false;
    await initialize();
  }

  Future<SoundNeedNotification?> publish(
    NotificationDraft draft, {
    bool resetReadState = true,
  }) async {
    await initialize();
    final title = draft.title.trim();
    if (title.isEmpty) {
      _diagnose('Se descartó un aviso sin título');
      return null;
    }

    final now = _clock();
    final key = draft.deduplicationKey?.trim().isNotEmpty == true
        ? draft.deduplicationKey!.trim()
        : null;
    final existingIndex = key == null
        ? -1
        : _records.indexWhere((item) => item.deduplicationKey == key);
    final previous = existingIndex >= 0 ? _records[existingIndex] : null;
    final id = previous?.id ?? _createId(key, now);
    final destination = _validDestination(draft.destination);
    final record = SoundNeedNotification(
      id: id,
      deduplicationKey: key,
      category: draft.category,
      title: title,
      description: draft.description.trim(),
      createdAt: previous?.createdAt ?? now,
      updatedAt: now,
      isRead: previous != null && !resetReadState ? previous.isRead : false,
      eventType: draft.eventType,
      destination: destination,
      priority: draft.priority,
      status: draft.status,
      progress: draft.progress?.clamp(0, 100),
      metadata: _safeMetadata(draft.metadata),
    );

    if (existingIndex >= 0) {
      _records[existingIndex] = record;
    } else {
      _records.insert(0, record);
    }
    _records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _purgeExpired();
    await _persist();
    notifyListeners();
    await _syncAndroid(record);
    return record;
  }

  Future<void> markRead(String id, {bool isRead = true}) async {
    final index = _records.indexWhere((item) => item.id == id);
    if (index < 0 || _records[index].isRead == isRead) return;
    _records[index] = _records[index].copyWith(
      isRead: isRead,
      updatedAt: _clock(),
    );
    _records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _persist();
    notifyListeners();
  }

  Future<void> markAllRead() async {
    final now = _clock();
    var changed = false;
    for (var index = 0; index < _records.length; index++) {
      if (!_records[index].isRead) {
        _records[index] = _records[index].copyWith(
          isRead: true,
          updatedAt: now,
        );
        changed = true;
      }
    }
    if (!changed) return;
    await _persist();
    notifyListeners();
  }

  Future<void> delete(String id) async {
    final index = _records.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final record = _records.removeAt(index);
    await _persist();
    notifyListeners();
    await _cancelAndroid(record);
  }

  Future<void> cancelByDeduplicationKey(String key) async {
    final index = _records.indexWhere((item) => item.deduplicationKey == key);
    if (index >= 0) await delete(_records[index].id);
  }

  Future<void> deleteAll() async {
    final previous = List<SoundNeedNotification>.of(_records);
    _records.clear();
    await _persist();
    notifyListeners();
    for (final record in previous) {
      await _cancelAndroid(record);
    }
  }

  bool isCategoryEnabled(NotificationCategory category) =>
      _categorySettings[category] ?? true;

  Future<void> setCategoryEnabled(
    NotificationCategory category,
    bool enabled,
  ) async {
    await initialize();
    _categorySettings[category] = enabled;
    final encoded = <String, bool>{
      for (final entry in _categorySettings.entries)
        entry.key.name: entry.value,
    };
    await _preferences?.setString(_categorySettingsKey, jsonEncode(encoded));
    if (!enabled) {
      for (final record in _records.where(
        (item) => item.category == category,
      )) {
        await _cancelAndroid(record);
      }
    }
    notifyListeners();
  }

  Future<bool> areSystemNotificationsEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('areEnabled') ?? false;
    } catch (error, stackTrace) {
      _diagnose(
        'No se pudo consultar el permiso de Android',
        error,
        stackTrace,
      );
      return false;
    }
  }

  Future<void> requestSystemPermission() async {
    try {
      await _channel.invokeMethod<Object?>('requestPermission');
    } catch (error, stackTrace) {
      _diagnose(
        'No se pudo gestionar el permiso de Android',
        error,
        stackTrace,
      );
    }
  }

  Future<void> openSystemNotificationSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } catch (error, stackTrace) {
      _diagnose(
        'No se pudieron abrir los ajustes de Android',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  NotificationNavigationRequest? takePendingNavigation() {
    if (_pendingNavigation.isEmpty) return null;
    final destination = _pendingNavigation.first;
    _pendingNavigation = _pendingNavigation.skip(1).toList();
    return destination;
  }

  void attachEventSource(NotificationEventSource source) {
    _eventSourceSubscription?.cancel();
    _eventSourceSubscription = source.events.listen(
      (draft) => unawaited(publish(draft)),
      onError: (Object error, StackTrace stackTrace) {
        _diagnose('Error en una fuente de notificaciones', error, stackTrace);
      },
    );
  }

  Future<void> disposeService() async {
    await _nativeNavigationSubscription?.cancel();
    await _eventSourceSubscription?.cancel();
    await _navigationRequests.close();
  }

  Future<void> _loadHistory() async {
    final encoded = _preferences?.getString(_historyKey);
    _records.clear();
    if (encoded == null || encoded.isEmpty) return;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List)
        throw const FormatException('Formato de historial inválido');
      for (final value in decoded) {
        if (value is Map) {
          final record = SoundNeedNotification.fromJson(
            value.map((key, item) => MapEntry('$key', item)),
          );
          if (record.id.isNotEmpty && record.title.isNotEmpty)
            _records.add(record);
        }
      }
      _records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (error, stackTrace) {
      _diagnose('Historial inválido; se iniciará uno nuevo', error, stackTrace);
      _records.clear();
    }
  }

  void _loadCategorySettings() {
    _categorySettings
      ..clear()
      ..addEntries(
        NotificationCategory.values.map((category) {
          var enabled = true;
          final raw = _preferences?.getString(_categorySettingsKey);
          if (raw != null) {
            try {
              final settings = jsonDecode(raw);
              if (settings is Map && settings[category.name] is bool) {
                enabled = settings[category.name] as bool;
              }
            } catch (error, stackTrace) {
              _diagnose(
                'Preferencias de categorías inválidas',
                error,
                stackTrace,
              );
            }
          }
          return MapEntry(category, enabled);
        }),
      );
  }

  Future<void> _syncAndroid(SoundNeedNotification record) async {
    if (!isCategoryEnabled(record.category)) return;
    try {
      final shown = await _channel.invokeMethod<bool>('show', <String, Object?>{
        'id': _stableInt(record.id),
        'recordId': record.id,
        'category': record.category.name,
        'title': record.title,
        'description': record.description,
        'priority': record.priority.index,
        'destination': record.destination,
        'ongoing': record.isOngoing,
        'progress': record.progress,
      });
      if (shown != true) _diagnose('Android no mostró el aviso ${record.id}');
    } catch (error, stackTrace) {
      _diagnose('Error al mostrar el aviso ${record.id}', error, stackTrace);
    }
  }

  Future<void> _cancelAndroid(SoundNeedNotification record) async {
    try {
      await _channel.invokeMethod<void>('cancel', <String, Object?>{
        'id': _stableInt(record.id),
      });
    } catch (error, stackTrace) {
      _diagnose('Error al cancelar el aviso ${record.id}', error, stackTrace);
    }
  }

  @visibleForTesting
  void handleNativeNavigation(Object? value) {
    if (value is! Map) return;
    final destination = _validDestination(value['destination']?.toString());
    if (destination == null) {
      _diagnose('Se ignoró una ruta de notificación inválida');
      return;
    }
    final rawId = value['id']?.toString().trim();
    final request = NotificationNavigationRequest(
      destination: destination,
      notificationId: rawId == null || rawId.isEmpty ? null : rawId,
    );
    if (_navigationRequests.hasListener) {
      _navigationRequests.add(request);
    } else {
      _pendingNavigation.add(request);
    }
  }

  Future<void> _persist() async {
    try {
      await _preferences?.setString(
        _historyKey,
        jsonEncode(_records.map((record) => record.toJson()).toList()),
      );
      _error = null;
    } catch (error, stackTrace) {
      _error = error.toString();
      _diagnose('No se pudo guardar el historial', error, stackTrace);
    }
  }

  void _purgeExpired() {
    final now = _clock();
    final cutoff = now.subtract(_retention);
    final interruptedCutoff = now.subtract(const Duration(hours: 24));
    for (var index = 0; index < _records.length; index++) {
      final record = _records[index];
      if (record.isOngoing && record.updatedAt.isBefore(interruptedCutoff)) {
        final interrupted = record.copyWith(
          title: 'Operación interrumpida',
          description: 'SoundNeed se cerró antes de completar esta operación.',
          updatedAt: now,
          isRead: false,
          eventType: 'operation_interrupted',
          status: NotificationStatus.failed,
          clearProgress: true,
        );
        _records[index] = interrupted;
        unawaited(_syncAndroid(interrupted));
      }
    }
    final expired = _records
        .where((record) => record.updatedAt.isBefore(cutoff))
        .toList();
    _records.removeWhere((record) => expired.contains(record));
    for (final record in expired) {
      unawaited(_cancelAndroid(record));
    }
    if (_records.length > _maximumRecords) {
      final completed = _records.where((record) => !record.isOngoing).toList()
        ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      for (final record in completed.take(_records.length - _maximumRecords)) {
        _records.remove(record);
        unawaited(_cancelAndroid(record));
      }
    }
  }

  String _createId(String? key, DateTime now) {
    if (key != null) return 'dedupe-${_stableInt(key)}';
    _idCounter++;
    return 'event-${now.microsecondsSinceEpoch}-$_idCounter';
  }

  static int _stableInt(String value) {
    var hash = 0x811c9dc5;
    for (final unit in utf8.encode(value)) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  static String? _validDestination(String? destination) =>
      destination != null && _destinationRoutes.contains(destination)
      ? destination
      : null;

  static Map<String, Object?> _safeMetadata(Map<String, Object?> source) =>
      Map<String, Object?>.unmodifiable(
        Map<String, Object?>.fromEntries(
          source.entries
              .where(
                (entry) =>
                    entry.key.length <= 64 &&
                    (entry.value == null ||
                        entry.value is String ||
                        entry.value is num ||
                        entry.value is bool),
              )
              .take(24)
              .map((entry) => MapEntry(entry.key, entry.value)),
        ),
      );

  void _diagnose(String message, [Object? error, StackTrace? stackTrace]) {
    final entry = error == null ? message : '$message: $error';
    _diagnostics.add(entry);
    if (_diagnostics.length > 100) _diagnostics.removeAt(0);
    debugPrint('[NotificationService] $entry');
    if (stackTrace != null) debugPrint('$stackTrace');
  }
}

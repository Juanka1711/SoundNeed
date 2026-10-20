import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:SoundNeed/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences preferences;
  late MethodChannel channel;
  final nativeCalls = <String>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
    channel = const MethodChannel('soundneed/notifications/test');
    nativeCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call.method);
          if (call.method == 'show') return true;
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  NotificationService service({DateTime Function()? clock}) =>
      NotificationService(
        preferences: preferences,
        channel: channel,
        navigationChannel: null,
        clock: clock,
      );

  test('deduplica, actualiza estado y conserva el historial', () async {
    final now = DateTime.utc(2026, 10, 20, 12);
    final firstService = service(clock: () => now);
    final started = await firstService.publish(
      const NotificationDraft(
        deduplicationKey: 'download:track-7',
        category: NotificationCategory.downloads,
        title: 'Descargando',
        description: 'Tema',
        eventType: 'download_started',
        destination: 'songs',
        status: NotificationStatus.ongoing,
      ),
    );
    await firstService.markRead(started!.id);
    final updated = await firstService.publish(
      const NotificationDraft(
        deduplicationKey: 'download:track-7',
        category: NotificationCategory.downloads,
        title: 'Descarga completada',
        description: 'Tema guardado',
        eventType: 'download_completed',
        destination: 'songs',
        status: NotificationStatus.completed,
        progress: 100,
      ),
      resetReadState: false,
    );

    expect(updated!.id, started.id);
    expect(firstService.records, hasLength(1));
    expect(updated.status, NotificationStatus.completed);
    expect(updated.isRead, isTrue);

    final restored = service(clock: () => now);
    await restored.initialize();
    expect(restored.records, hasLength(1));
    expect(restored.records.single.title, 'Descarga completada');
    expect(restored.records.single.isRead, isTrue);
    await restored.markRead(updated.id, isRead: false);
    expect(restored.unreadCount, 1);
  });

  test('guarda eventos aunque Android no pueda mostrarlos', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call.method);
          if (call.method == 'show') {
            throw PlatformException(code: 'notifications_disabled');
          }
          return true;
        });
    final notificationService = service();

    final record = await notificationService.publish(
      const NotificationDraft(
        category: NotificationCategory.errors,
        title: 'Importación fallida',
        description: 'Revisa el enlace.',
        eventType: 'playlist_import_failed',
        destination: 'playlists',
        priority: NotificationPriority.high,
        status: NotificationStatus.failed,
      ),
    );

    expect(record, isNotNull);
    expect(notificationService.records, hasLength(1));
    expect(notificationService.diagnostics, isNotEmpty);
    expect(
      preferences.getString('soundneed.general_notifications.history.v1'),
      isNotNull,
    );
  });

  test('filtra destinos de navegación no permitidos', () async {
    final notificationService = service();
    await notificationService.initialize();

    notificationService.handleNativeNavigation(<String, Object?>{
      'destination': 'songs',
    });
    notificationService.handleNativeNavigation(<String, Object?>{
      'destination': 'https://invalid.example',
    });

    expect(notificationService.takePendingNavigation(), 'songs');
    expect(notificationService.takePendingNavigation(), isNull);
    expect(notificationService.diagnostics, isNotEmpty);
  });

  test(
    'la petición de permiso solo se envía cuando el usuario la solicita',
    () async {
      final notificationService = service();
      await notificationService.initialize();
      expect(nativeCalls, isNot(contains('requestPermission')));

      await notificationService.requestSystemPermission();

      expect(nativeCalls, contains('requestPermission'));
    },
  );

  test(
    'eliminar un registro cancela también su notificación Android',
    () async {
      final notificationService = service();
      final record = await notificationService.publish(
        const NotificationDraft(
          deduplicationKey: 'import:one',
          category: NotificationCategory.imports,
          title: 'Importada',
          description: 'Lista guardada',
        ),
      );
      nativeCalls.clear();

      await notificationService.delete(record!.id);

      expect(notificationService.records, isEmpty);
      expect(nativeCalls, contains('cancel'));
    },
  );

  test('retiene eventos recientes y descarta los vencidos', () async {
    var now = DateTime.utc(2026, 1, 1);
    final firstService = service(clock: () => now);
    await firstService.publish(
      const NotificationDraft(
        category: NotificationCategory.library,
        title: 'Antigua',
        description: '',
      ),
    );
    now = now.add(const Duration(days: 80));
    await firstService.publish(
      const NotificationDraft(
        category: NotificationCategory.library,
        title: 'Reciente',
        description: '',
      ),
    );
    now = now.add(const Duration(days: 20));
    final restored = service(clock: () => now);
    await restored.initialize();

    expect(restored.records.map((record) => record.title), ['Reciente']);
  });

  test('persiste preferencias de categoría y no publica en Android al desactivarla', () async {
    final notificationService = service();
    await notificationService.initialize();
    await notificationService.setCategoryEnabled(
      NotificationCategory.news,
      false,
    );
    final callCount = nativeCalls.where((call) => call == 'show').length;
    await notificationService.publish(
      const NotificationDraft(
        category: NotificationCategory.news,
        title: 'Novedad',
        description: 'Evento de prueba',
      ),
    );

    expect(notificationService.records, hasLength(1));
    expect(nativeCalls.where((call) => call == 'show').length, callCount);
    final restored = service();
    await restored.initialize();
    expect(restored.isCategoryEnabled(NotificationCategory.news), isFalse);
  });
}

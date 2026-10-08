import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Avisos locales (sin servidor): temporizador de frío y ofertas que caducan.
/// En web y en plataformas sin soporte no hace nada (los avisos in-app siguen funcionando).
class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static bool _asked = false;

  static bool get _supported =>
      !kIsWeb &&
      {
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }.contains(defaultTargetPlatform);

  static Future<void> init() async {
    if (!_supported || _ready) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(
        tz.getLocation('Europe/Madrid'),
      ); // app solo para España
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestSoundPermission: false,
        requestBadgePermission: false,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: darwin,
          macOS: darwin,
          linux: LinuxInitializationSettings(defaultActionName: 'Abrir'),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notifier.init falló: $e');
    }
  }

  /// Pide permiso la primera vez que hace falta (no al arrancar).
  static Future<void> _ensurePermission() async {
    if (!_ready || _asked) return;
    _asked = true;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, sound: true);
      await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, sound: true);
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'multimarket',
      'Avisos de MultiMarket',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    macOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    linux: LinuxNotificationDetails(),
  );

  /// Notificación inmediata (avisos de otros miembros recibidos con la app abierta).
  static Future<void> now(int id, String title, String body) async {
    if (!_ready) return;
    await _ensurePermission();
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: _details,
      );
    } catch (e) {
      debugPrint('Notifier.now falló: $e');
    }
  }

  static Future<void> schedule(
    int id,
    String title,
    String body,
    DateTime at,
  ) async {
    if (!_ready || !at.isAfter(DateTime.now())) return;
    await _ensurePermission();
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(at, tz.local),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Notifier.schedule falló: $e');
    }
  }

  static Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  static Future<void> cancel(int id) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }
}

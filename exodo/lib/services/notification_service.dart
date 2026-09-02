// ═══════════════════════════════════════════════════════════════════════════════
// NOTIFICATION SERVICE — Avisos en segundo plano
// ───────────────────────────────────────────────────────────────────────────────
// Hoy: "Ver respuesta de Éxodo" cuando una generación larga termina con la app
// en background (el usuario salió a hacer otra cosa; Éxodo siguió escribiendo).
// Mañana: actualización lista para instalar (UpdateService).
// Requiere permiso POST_NOTIFICATIONS (Android 13+): se pide la primera vez
// que se va a mostrar un aviso, no al arrancar.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _permissionGranted = false;

  Future<void> initialize({void Function(String? payload)? onTap}) async {
    if (_initialized) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      const androidInit =
          AndroidInitializationSettings('exodo_notification_icon');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        InitializationSettings(
          android: androidInit,
          iOS: iosInit,
        ),
        onDidReceiveNotificationResponse: (response) {
          if (onTap != null) onTap(response.payload);
        },
      );
      _initialized = true;
      // Android 13+ POST_NOTIFICATIONS: NO se solicita aquí. initialize()
      // corre en background antes del primer frame y sin una actividad en
      // primer plano, por lo que el diálogo del sistema no llega a mostrarse
      // (causa de "las notificaciones no salen" en instalaciones limpias).
      // El permiso se pide en el primer frame visible desde main.dart vía
      // ensurePermission().
    } catch (_) {}
  }

  /// Pide el permiso justo antes de notificar (Android 13+/iOS). No bloquea:
  /// si el usuario aún no lo concede, simplemente no hay notificación visible.
  Future<bool> ensurePermission() async {
    if (!_initialized) await initialize();
    if (_permissionGranted) return true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final granted = await android.requestNotificationsPermission();
        _permissionGranted = granted ?? false;
        return _permissionGranted;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        final granted =
            await ios.requestPermissions(alert: true, badge: true, sound: true);
        _permissionGranted = granted ?? false;
        return _permissionGranted;
      }
    } catch (_) {}
    return false;
  }

  /// Notificación con el logo de la app y un cuerpo ya localizado por el
  /// llamador ("Ver respuesta de Éxodo"). El tap abre la app (intent por
  /// defecto de la activity principal — no requiere payload extra).
  /// [Fix LG V60 #3] `title` permite "Éxodo ha respondido" con preview.
  Future<void> showReplyReady({
    required String body,
    String? title,
    int id = 1001,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (!await ensurePermission()) return;
    try {
      const androidDetails = AndroidNotificationDetails(
        'exodo_replies',
        'Respuestas de Éxodo',
        channelDescription: 'Avisa cuando una respuesta terminó de escribirse en segundo plano',
        importance: Importance.high,
        priority: Priority.high,
        // Logo oficial Behavior AI
        icon: 'exodo_notification_icon',
        largeIcon: DrawableResourceAndroidBitmap('logo_behavior'),
        color: Color(0xFFC9933A),
        showWhen: true,
      );
      const iosDetails = DarwinNotificationDetails();
      await _plugin.show(
        id,
        title ?? 'Éxodo',
        body,
        const NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
      );
    } catch (_) {}
  }

  /// Notificación de actualización lista (canal silencioso: la descarga ya
  /// fue silenciosa, este aviso es la única interrupción).
  Future<void> showUpdateReady({
    required String title,
    required String body,
    String? payload,
    int id = 1002,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (!await ensurePermission()) return;
    try {
      const androidDetails = AndroidNotificationDetails(
        'exodo_updates',
        'Actualizaciones de Éxodo',
        channelDescription: 'Avisa cuando una nueva versión terminó de descargarse',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: 'exodo_notification_icon',
        largeIcon: DrawableResourceAndroidBitmap('logo_behavior'),
        color: Color(0xFFC9933A),
      );
      const iosDetails = DarwinNotificationDetails();
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
        payload: payload,
      );
    } catch (_) {}
  }
}

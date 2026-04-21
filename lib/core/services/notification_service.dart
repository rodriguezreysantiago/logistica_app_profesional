import 'dart:io';
import 'package:flutter/material.dart'; 
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    // CONFIGURACIÓN ANDROID
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // CONFIGURACIÓN IOS (DARWIN)
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // CONFIGURACIÓN LINUX / WINDOWS
    const LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(defaultActionName: 'Open');

    // Se agrega 'const' aquí para optimizar la creación del objeto
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
      linux: initializationSettingsLinux,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        debugPrint("NOTIFICACIÓN TOCADA EN: ${details.payload}");
      },
    );

    // PERMISOS ESPECÍFICOS PARA ANDROID 13+
    if (Platform.isAndroid) {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  /// NOTIFICACIÓN PARA EL CHOFER (Vencimientos)
  static Future<void> mostrarAlertaVencimiento({
    required int id,
    required String titulo,
    required String mensaje,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'vencimientos_canal',
      'Alertas de Vencimientos',
      channelDescription: 'Notificaciones sobre documentos próximos a vencer',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      styleInformation: BigTextStyleInformation(''), 
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true, 
        presentBadge: true, 
        presentSound: true,
      ),
    );

    await _notificationsPlugin.show(id, titulo, mensaje, platformDetails, payload: 'vencimiento');
  }

  /// NOTIFICACIÓN PARA EL ADMIN (Nuevos Trámites)
  static Future<void> mostrarAvisoAdmin({
    required String chofer,
    required String documento,
  }) async {
    // Agregamos 'const' a los detalles de Android para limpiar los avisos del linter
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'admin_canal',
      'Avisos Administrativos',
      channelDescription: 'Notificaciones sobre nuevas revisiones pendientes',
      importance: Importance.max,
      priority: Priority.high,
      color: Color(0xFF1A3A5A), 
      ledColor: Color(0xFFFF9800),
      ledOnMs: 1000,
      ledOffMs: 500,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true, 
        presentSound: true,
      ),
    );

    await _notificationsPlugin.show(
      999, 
      "Nueva Revisión Pendiente",
      "$chofer subió: $documento",
      platformDetails,
      payload: 'admin_revision',
    );
  }
}
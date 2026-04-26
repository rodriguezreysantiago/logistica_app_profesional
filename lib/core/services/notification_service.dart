import 'dart:io';
import 'package:flutter/foundation.dart'; 
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

    // ✅ MENTOR: Blindaje Web perfecto. 
    if (!kIsWeb && Platform.isAndroid) {
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
    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'vencimientos_canal',
      'Alertas de Vencimientos',
      channelDescription: 'Notificaciones sobre documentos próximos a vencer',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      color: Colors.orangeAccent, // ✅ MENTOR: Branding aplicado al ícono
      styleInformation: BigTextStyleInformation(mensaje), 
    );

    NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
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
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'admin_canal',
      'Avisos Administrativos',
      channelDescription: 'Notificaciones sobre nuevas revisiones pendientes',
      importance: Importance.max,
      priority: Priority.high,
      color: Colors.greenAccent, // ✅ MENTOR: Alerta verde para cosas nuevas a aprobar
      ledColor: Colors.greenAccent,
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

    // ID dinámico para que no se pisen
    final int idDinamico = DateTime.now().millisecondsSinceEpoch.remainder(100000);

    await _notificationsPlugin.show(
      idDinamico, 
      "Nueva Revisión Pendiente",
      "$chofer subió: $documento",
      platformDetails,
      payload: 'admin_revision',
    );
  }
}
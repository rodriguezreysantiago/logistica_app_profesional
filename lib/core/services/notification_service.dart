import 'dart:io';
import 'dart:async'; // ✅ MENTOR: Necesario para el StreamController
import 'package:flutter/foundation.dart'; 
import 'package:flutter/material.dart'; 
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  
  // ✅ MEJORA PRO: Stream para manejar la navegación al tocar notificaciones
  static final StreamController<String?> selectNotificationStream = StreamController<String?>.broadcast();

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

    // CONFIGURACIÓN LINUX
    const LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(defaultActionName: 'Open');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
      linux: initializationSettingsLinux,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        debugPrint("NOTIFICACIÓN TOCADA CON PAYLOAD: ${details.payload}");
        // ✅ MEJORA PRO: Emitimos el payload para que el main.dart pueda navegar a la pantalla correcta
        selectNotificationStream.add(details.payload);
      },
    );

    // ✅ CORRECCIÓN CRÍTICA (Bug Fix Web)
    // Debemos verificar kIsWeb de forma aislada PRIMERO.
    // Si es Web, salimos del método para que Platform.isAndroid NUNCA se ejecute.
    if (kIsWeb) return; 

    // Ahora es seguro usar Platform.isAndroid
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
    // Si la app está en la web, local_notifications no funciona. Salimos silenciosamente.
    if (kIsWeb) return; 

    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'vencimientos_canal',
      'Alertas de Vencimientos',
      channelDescription: 'Notificaciones sobre documentos próximos a vencer',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      color: Colors.orangeAccent, 
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

    // Payload 'vencimiento' será atrapado por el StreamController
    await _notificationsPlugin.show(id, titulo, mensaje, platformDetails, payload: 'vencimiento');
  }

  /// NOTIFICACIÓN PARA EL ADMIN (Nuevos Trámites)
  static Future<void> mostrarAvisoAdmin({
    required String chofer,
    required String documento,
  }) async {
    if (kIsWeb) return;

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'admin_canal',
      'Avisos Administrativos',
      channelDescription: 'Notificaciones sobre nuevas revisiones pendientes',
      importance: Importance.max,
      priority: Priority.high,
      color: Colors.greenAccent, 
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

    final int idDinamico = DateTime.now().millisecondsSinceEpoch.remainder(100000);

    await _notificationsPlugin.show(
      idDinamico, 
      "Nueva Revisión Pendiente",
      "$chofer subió: $documento",
      platformDetails,
      payload: 'admin_revision',
    );
  }

  // ✅ MEJORA PRO: Método de limpieza para evitar fugas de memoria
  static void dispose() {
    selectNotificationStream.close();
  }
}
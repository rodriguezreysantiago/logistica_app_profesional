import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
import 'core/services/prefs_service.dart';
import 'core/services/notification_service.dart';

import 'core/routes/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';

// Pantalla inicial
import 'ui/screens/login_screen.dart';

// ✅ MEJORA PRO: Clave global para poder navegar desde fuera del árbol de widgets
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ==========================================================================
  // 1. CAPTURADOR GLOBAL DE ERRORES ASÍNCRONOS
  // ==========================================================================
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint("🚨 [ERROR GLOBAL ASÍNCRONO]: $error");
    return true; 
  };

  // ==========================================================================
  // 2. CAPTURADOR GLOBAL DE ERRORES DE UI
  // ==========================================================================
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint("🚨 [ERROR GLOBAL FLUTTER]: ${details.exception}");
  };

  // Inicialización de servicios críticos
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint("🔥 Firebase conectado correctamente");
  } catch (e) {
    debugPrint("🚨 Error crítico al iniciar Firebase: $e");
  }

  await PrefsService.init();
  await NotificationService.init();

  runApp(const LogisticaApp());
}

// Convertimos a StatefulWidget para poder escuchar el Stream de notificaciones
class LogisticaApp extends StatefulWidget {
  const LogisticaApp({super.key});

  @override
  State<LogisticaApp> createState() => _LogisticaAppState();
}

class _LogisticaAppState extends State<LogisticaApp> {

  @override
  void initState() {
    super.initState();
    // ✅ MEJORA PRO: Escuchamos cuando el usuario toca una notificación
    NotificationService.selectNotificationStream.stream.listen((String? payload) {
      if (payload == null) return;
      
      debugPrint("Navegando vía notificación al payload: $payload");
      
      // Verificamos que el navegador esté listo
      if (navigatorKey.currentState != null) {
        if (payload == 'vencimiento') {
          // ✅ CORRECCIÓN: Usando la constante correcta de tu AppRoutes
          navigatorKey.currentState!.pushNamed(AppRoutes.misVencimientos); 
        } else if (payload == 'admin_revision') {
          navigatorKey.currentState!.pushNamed(AppRoutes.adminRevisiones);
        }
      }
    });
  }

  @override
  void dispose() {
    // Limpieza de memoria
    NotificationService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, // ✅ Inyectamos la clave global aquí
      title: AppTexts.appName,
      debugShowCheckedModeBanner: false,

      // ==========================================================================
      // 3. INTERCEPTOR DE UI: REEMPLAZO DE LA PANTALLA GRIS DE LA MUERTE
      // ==========================================================================
      builder: (context, widget) {
        ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
          return Scaffold(
            backgroundColor: AppTheme.darkTheme.scaffoldBackgroundColor,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(30.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 70),
                    const SizedBox(height: 20),
                    const Text(
                      "Algo no salió como esperábamos",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Se ha registrado el error para el equipo de soporte.",
                      style: TextStyle(fontSize: 14, color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(8)
                      ),
                      child: Text(
                        errorDetails.exceptionAsString(),
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        };
        return widget!;
      },

      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      supportedLocales: const [
        Locale('es', 'AR'),
      ],

      locale: const Locale('es', 'AR'),

      theme: AppTheme.darkTheme,

      initialRoute: PrefsService.isLoggedIn
          ? AppRoutes.home
          : AppRoutes.login,

      routes: {
        AppRoutes.login: (_) => const LoginScreen(),
      },

      onGenerateRoute: AppRouter.generateRoute,
      onUnknownRoute: AppRouter.unknownRoute,
    );
  }
}
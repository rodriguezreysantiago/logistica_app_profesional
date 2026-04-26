import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
import 'core/services/prefs_service.dart'; 
import 'core/services/notification_service.dart'; 

// Pantallas de inicio y menú
import 'ui/screens/login_screen.dart';
import 'ui/screens/main_panel.dart';

// Pantallas de usuario
import 'ui/screens/user_mi_equipo_screen.dart';
import 'ui/screens/user_mi_perfil_screen.dart';
import 'ui/screens/user_mis_vencimientos_screen.dart'; 

// Pantallas de administrador
import 'ui/screens/admin_panel_screen.dart';             
import 'ui/screens/admin_personal_lista_screen.dart';  
import 'ui/screens/admin_vehiculos_lista_screen.dart'; 
import 'ui/screens/admin_vencimientos_menu_screen.dart'; 
import 'ui/screens/admin_revisiones_screen.dart'; 
import 'ui/screens/admin_reports_screen.dart'; 

// Pantallas de auditoría
import 'ui/screens/admin_vencimientos_choferes_screen.dart';
import 'ui/screens/admin_vencimientos_chasis_screen.dart';
import 'ui/screens/admin_vencimientos_acoplados_screen.dart';

void main() async {
  // Asegura que los bindings de Flutter estén listos antes de ejecutar código nativo
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint("🔥 Firebase conectado correctamente");
  } catch (e) {
    debugPrint("🚨 Error crítico al iniciar Firebase: $e");
  }

  // ✅ MENTOR: Excelente práctica inicializar servicios clave antes del runApp
  await PrefsService.init();          
  await NotificationService.init();   

  runApp(const LogisticaApp());
}

class LogisticaApp extends StatelessWidget {
  const LogisticaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'S.M.A.R.T. Logística',
      debugShowCheckedModeBanner: false,
      
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'AR'),
      ],
      locale: const Locale('es', 'AR'),
      
      // ✅ MENTOR: Aquí inyectamos el "Cerebro Visual" moderno
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF09141F), // Azul noche profundo
        colorScheme: const ColorScheme.dark(
          primary: Colors.greenAccent,
          secondary: Colors.orangeAccent,
          surface: Color(0xFF132538), // Color base para tarjetas y campos
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: Colors.white),
          iconTheme: IconThemeData(color: Colors.greenAccent),
        ),
        // Centralizamos el diseño de todos los campos de texto
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF132538),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.greenAccent, width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.redAccent, width: 1)),
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
        ),
        // Centralizamos el diseño de los botones principales
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.greenAccent,
            foregroundColor: Colors.black,
            elevation: 6,
            shadowColor: Colors.greenAccent.withAlpha(100), // Resplandor neón
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ),

      initialRoute: PrefsService.isLoggedIn ? '/home' : '/',
      
      routes: {
        '/': (context) => const LoginScreen(),
      },
      
      // Manejo de rutas dinámicas con paso de argumentos
      onGenerateRoute: (settings) {
        MaterialPageRoute buildRoute(Widget screen) => MaterialPageRoute(
          builder: (_) => screen, 
          settings: settings
        );

        switch (settings.name) {
          case '/home':
            final args = settings.arguments as Map<String, dynamic>?;
            return buildRoute(MainPanel(
              dni: args?['dni'] ?? PrefsService.dni,
              nombre: args?['nombre'] ?? PrefsService.nombre,
              rol: args?['rol'] ?? PrefsService.rol,
            ));
          case '/perfil':
            return buildRoute(UserMiPerfilScreen(dni: settings.arguments as String? ?? PrefsService.dni));
          case '/equipo':
            return buildRoute(UserMiEquipoScreen(dniUser: settings.arguments as String? ?? PrefsService.dni));
          case '/mis_vencimientos':
            return buildRoute(UserMisVencimientosScreen(dniUser: settings.arguments as String? ?? PrefsService.dni));
          case '/admin_panel':
            return buildRoute(const AdminPanelScreen());
          case '/admin_personal_lista':
            return buildRoute(const AdminPersonalListaScreen());
          case '/admin_vehiculos_lista':
            return buildRoute(const AdminVehiculosListaScreen());
          case '/admin_vencimientos_menu':
            return buildRoute(const AdminVencimientosMenuScreen());
          case '/admin_revisiones':
            return buildRoute(const AdminRevisionesScreen());
          case '/admin_reportes':
            return buildRoute(const AdminReportsScreen());
          case '/vencimientos_choferes':
            return buildRoute(const AdminVencimientosChoferesScreen());
          case '/vencimientos_chasis':
            return buildRoute(const AdminVencimientosChasisScreen());
          case '/vencimientos_acoplados':
            return buildRoute(const AdminVencimientosAcopladosScreen());
          default:
            return null; 
        }
      },
      
      // ✅ MENTOR: Simplificamos la pantalla de error para que herede el tema global
      onUnknownRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text("Ruta No Encontrada")),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.broken_image_outlined, color: Colors.white24, size: 80),
                  const SizedBox(height: 20),
                  const Text("La pantalla solicitada no existe o fue movida.", style: TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false),
                    child: const Text("VOLVER AL INICIO"),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
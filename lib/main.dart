import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
import 'core/services/prefs_service.dart'; 
import 'core/services/notification_service.dart'; 
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

// Pantallas de auditoría
import 'ui/screens/admin_vencimientos_choferes_screen.dart';
import 'ui/screens/admin_vencimientos_chasis_screen.dart';
import 'ui/screens/admin_vencimientos_acoplados_screen.dart';

void main() async {
  // 1. Vincula el motor de Flutter al sistema operativo (Android/iOS/PC)
  // Es fundamental que esto esté antes de cualquier plugin.
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Inicialización de Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint("🔥 Firebase conectado correctamente");
  } catch (e) {
    debugPrint("🚨 Error crítico al iniciar Firebase: $e");
  }

  // 3. Inicialización de servicios (Carga de memoria local y notificaciones)
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
      
      // Localización al español (Argentina)
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'AR'),
      ],
      locale: const Locale('es', 'AR'),
      
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A3A5A),
          primary: const Color(0xFF1A3A5A),
          secondary: Colors.orangeAccent,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Color(0xFF1A3A5A),
          foregroundColor: Colors.white,
        ),
      ),

      // LÓGICA DE AUTO-LOGUEO
      initialRoute: PrefsService.isLoggedIn ? '/home' : '/',
      
      routes: {
        '/': (context) => const LoginScreen(),
      },
      
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
    );
  }
}
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
import 'core/services/prefs_service.dart'; 
import 'core/services/notification_service.dart'; 
import 'ui/screens/login_screen.dart';
import 'ui/screens/main_panel.dart';

// Importaciones de pantallas de usuario
import 'ui/screens/user_mi_equipo_screen.dart';
import 'ui/screens/user_mi_perfil_screen.dart';
import 'ui/screens/user_mis_vencimientos_screen.dart'; 

// Importaciones de pantallas de administrador
import 'ui/screens/admin_panel_screen.dart';           
import 'ui/screens/admin_personal_lista_screen.dart';  
import 'ui/screens/admin_vehiculos_lista_screen.dart'; 
import 'ui/screens/admin_vencimientos_menu_screen.dart'; 
import 'ui/screens/admin_revisiones_screen.dart'; 

// Importaciones de pantallas de auditoría
import 'ui/screens/admin_vencimientos_choferes_screen.dart';
import 'ui/screens/admin_vencimientos_chasis_screen.dart';
import 'ui/screens/admin_vencimientos_acoplados_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicialización de Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // --- INICIALIZAMOS LOS SERVICIOS LOCALES ---
  await PrefsService.init();          // Persistencia de sesión
  await NotificationService.init();   // Plugin de notificaciones locales

  runApp(const LogisticaApp());
}

class LogisticaApp extends StatelessWidget {
  const LogisticaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'S.M.A.R.T. Logística',
      debugShowCheckedModeBanner: false,
      
      // Configuración de idiomas para calendarios y formatos de fecha
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'AR'), // Español Argentina
        Locale('es', 'ES'), // Español estándar
      ],
      locale: const Locale('es', 'AR'),
      
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A3A5A),
          primary: const Color(0xFF1A3A5A),
          secondary: Colors.orangeAccent,
        ),
        // Estilo global para botones y tarjetas para mantener la estética SMART
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),

      // --- LÓGICA DE RUTA INICIAL ---
      // Si ya está logueado, va directo al MainPanel, sino al Login
      initialRoute: PrefsService.isLoggedIn ? '/home' : '/',
      
      routes: {
        '/': (context) => const LoginScreen(),
      },
      
      onGenerateRoute: (settings) {
        // --- RUTAS COMUNES ---
        
        if (settings.name == '/home') {
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute(
            builder: (context) => MainPanel(
              dni: args?['dni'] ?? PrefsService.dni,
              nombre: args?['nombre'] ?? PrefsService.nombre,
              rol: args?['rol'] ?? PrefsService.rol,
            ),
          );
        }

        if (settings.name == '/perfil') {
          final dni = settings.arguments as String? ?? PrefsService.dni;
          return MaterialPageRoute(
            builder: (context) => UserMiPerfilScreen(dni: dni),
          );
        }

        if (settings.name == '/equipo') {
          final dni = settings.arguments as String? ?? PrefsService.dni;
          return MaterialPageRoute(
            builder: (context) => UserMiEquipoScreen(dniUser: dni),
          );
        }

        if (settings.name == '/mis_vencimientos') {
          final dni = settings.arguments as String? ?? PrefsService.dni;
          return MaterialPageRoute(
            builder: (context) => UserMisVencimientosScreen(dniUser: dni),
          );
        }

        // --- RUTAS ADMINISTRADOR ---

        if (settings.name == '/admin_panel') {
          return MaterialPageRoute(
            builder: (context) => const AdminPanelScreen(),
          );
        }

        if (settings.name == '/admin_personal_lista') {
          return MaterialPageRoute(
            builder: (context) => const AdminPersonalListaScreen(),
          );
        }

        if (settings.name == '/admin_vehiculos_lista') {
          return MaterialPageRoute(
            builder: (context) => const AdminVehiculosListaScreen(),
          );
        }

        if (settings.name == '/admin_vencimientos_menu') {
          return MaterialPageRoute(
            builder: (context) => const AdminVencimientosMenuScreen(),
          );
        }

        if (settings.name == '/admin_revisiones') {
          return MaterialPageRoute(
            builder: (context) => const AdminRevisionesScreen(),
          );
        }

        // --- RUTAS DE AUDITORÍA (Nuevas pantallas corregidas hoy) ---

        if (settings.name == '/vencimientos_choferes') {
          return MaterialPageRoute(
            builder: (context) => const AdminVencimientosChoferesScreen(),
          );
        }

        if (settings.name == '/vencimientos_chasis') {
          return MaterialPageRoute(
            builder: (context) => const AdminVencimientosChasisScreen(),
          );
        }

        if (settings.name == '/vencimientos_acoplados') {
          return MaterialPageRoute(
            builder: (context) => const AdminVencimientosAcopladosScreen(),
          );
        }

        return null; 
      },
    );
  }
}
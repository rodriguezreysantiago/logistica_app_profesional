import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
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

// --- NUEVAS IMPORTACIONES (AUDITORÍA) ---
import 'ui/screens/admin_vencimientos_choferes_screen.dart';
import 'ui/screens/admin_vencimientos_chasis_screen.dart';
import 'ui/screens/admin_vencimientos_acoplados_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
      
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A3A5A)),
      ),

      initialRoute: '/',
      routes: {
        '/': (context) => const LoginScreen(),
      },
      
      onGenerateRoute: (settings) {
        // --- RUTAS COMUNES ---
        
        if (settings.name == '/home') {
          final args = settings.arguments as Map<String, dynamic>? ?? {};
          return MaterialPageRoute(
            builder: (context) => MainPanel(
              dni: args['dni'] ?? '',
              nombre: args['nombre'] ?? 'Usuario',
              rol: args['rol'] ?? 'USER',
            ),
          );
        }

        if (settings.name == '/perfil') {
          final dni = settings.arguments as String? ?? '';
          return MaterialPageRoute(
            builder: (context) => UserMiPerfilScreen(dni: dni),
          );
        }

        if (settings.name == '/equipo') {
          final dni = settings.arguments as String? ?? '';
          return MaterialPageRoute(
            builder: (context) => UserMiEquipoScreen(dniUser: dni),
          );
        }

        if (settings.name == '/mis_vencimientos') {
          final dni = settings.arguments as String? ?? '';
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

        // --- NUEVAS RUTAS DE AUDITORÍA REGISTRADAS ---

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
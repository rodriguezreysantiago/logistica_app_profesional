import 'package:flutter/material.dart';

import '../services/prefs_service.dart';

import '../../ui/widgets/auth_guard.dart';
import '../../ui/widgets/role_guard.dart';

import '../../ui/screens/main_panel.dart';

import '../../ui/screens/user_mi_equipo_screen.dart';
import '../../ui/screens/user_mi_perfil_screen.dart';
import '../../ui/screens/user_mis_vencimientos_screen.dart';

import '../../ui/screens/admin_panel_screen.dart';
import '../../ui/screens/admin_personal_lista_screen.dart';
import '../../ui/screens/admin_vehiculos_lista_screen.dart';
import '../../ui/screens/admin_vencimientos_menu_screen.dart';
import '../../ui/screens/admin_revisiones_screen.dart';
import '../../ui/screens/admin_reports_screen.dart';

import '../../ui/screens/admin_vencimientos_choferes_screen.dart';
import '../../ui/screens/admin_vencimientos_chasis_screen.dart';
import '../../ui/screens/admin_vencimientos_acoplados_screen.dart';

class AppRouter {
  static Widget _proteger(Widget child) {
    return AuthGuard(child: child);
  }

  static Widget _protegerAdmin(Widget child) {
    return AuthGuard(
      child: RoleGuard(
        child: child,
      ),
    );
  }

  static MaterialPageRoute _buildRoute(
    Widget screen,
    RouteSettings settings,
  ) {
    return MaterialPageRoute(
      builder: (_) => screen,
      settings: settings,
    );
  }

  static Route<dynamic>? generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/home':
        final args = settings.arguments as Map<String, dynamic>?;

        return _buildRoute(
          _proteger(
            MainPanel(
              dni: args?['dni'] ?? PrefsService.dni,
              nombre: args?['nombre'] ?? PrefsService.nombre,
              rol: args?['rol'] ?? PrefsService.rol,
            ),
          ),
          settings,
        );

      case '/perfil':
        return _buildRoute(
          _proteger(
            UserMiPerfilScreen(
              dni: settings.arguments as String? ?? PrefsService.dni,
            ),
          ),
          settings,
        );

      case '/equipo':
        return _buildRoute(
          _proteger(
            UserMiEquipoScreen(
              dniUser: settings.arguments as String? ?? PrefsService.dni,
            ),
          ),
          settings,
        );

      case '/mis_vencimientos':
        return _buildRoute(
          _proteger(
            UserMisVencimientosScreen(
              dniUser: settings.arguments as String? ?? PrefsService.dni,
            ),
          ),
          settings,
        );

      case '/admin_panel':
        return _buildRoute(
          _protegerAdmin(const AdminPanelScreen()),
          settings,
        );

      case '/admin_personal_lista':
        return _buildRoute(
          _protegerAdmin(const AdminPersonalListaScreen()),
          settings,
        );

      case '/admin_vehiculos_lista':
        return _buildRoute(
          _protegerAdmin(const AdminVehiculosListaScreen()),
          settings,
        );

      case '/admin_vencimientos_menu':
        return _buildRoute(
          _protegerAdmin(const AdminVencimientosMenuScreen()),
          settings,
        );

      case '/admin_revisiones':
        return _buildRoute(
          _protegerAdmin(const AdminRevisionesScreen()),
          settings,
        );

      case '/admin_reportes':
        return _buildRoute(
          _protegerAdmin(const AdminReportsScreen()),
          settings,
        );

      case '/vencimientos_choferes':
        return _buildRoute(
          _protegerAdmin(const AdminVencimientosChoferesScreen()),
          settings,
        );

      case '/vencimientos_chasis':
        return _buildRoute(
          _protegerAdmin(const AdminVencimientosChasisScreen()),
          settings,
        );

      case '/vencimientos_acoplados':
        return _buildRoute(
          _protegerAdmin(const AdminVencimientosAcopladosScreen()),
          settings,
        );

      default:
        return null;
    }
  }

  static Route<dynamic> unknownRoute(RouteSettings settings) {
    return MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: const Text("Ruta no encontrada"),
        ),
        body: Center(
          child: ElevatedButton(
            onPressed: () {
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/',
                (_) => false,
              );
            },
            child: const Text("VOLVER"),
          ),
        ),
      ),
    );
  }
}
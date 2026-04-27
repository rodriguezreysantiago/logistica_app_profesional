import 'package:flutter/material.dart';

import '../services/prefs_service.dart';
import '../constants/app_constants.dart'; // ✅ MEJORA PRO: Importamos las constantes

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
  // ✅ MEJORA PRO: Constructor privado para evitar que alguien haga AppRouter()
  AppRouter._();

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
      // ✅ MEJORA PRO: Reemplazo absoluto de Strings mágicos por Constantes Fuertes
      case AppRoutes.home:
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

      case AppRoutes.perfil:
        return _buildRoute(
          _proteger(
            UserMiPerfilScreen(
              dni: settings.arguments as String? ?? PrefsService.dni,
            ),
          ),
          settings,
        );

      case AppRoutes.equipo:
        return _buildRoute(
          _proteger(
            UserMiEquipoScreen(
              dniUser: settings.arguments as String? ?? PrefsService.dni,
            ),
          ),
          settings,
        );

      case AppRoutes.misVencimientos:
        return _buildRoute(
          _proteger(
            UserMisVencimientosScreen(
              dniUser: settings.arguments as String? ?? PrefsService.dni,
            ),
          ),
          settings,
        );

      case AppRoutes.adminPanel:
        return _buildRoute(
          _protegerAdmin(const AdminPanelScreen()),
          settings,
        );

      case AppRoutes.adminPersonalLista:
        return _buildRoute(
          _protegerAdmin(const AdminPersonalListaScreen()),
          settings,
        );

      case AppRoutes.adminVehiculosLista:
        return _buildRoute(
          _protegerAdmin(const AdminVehiculosListaScreen()),
          settings,
        );

      case AppRoutes.adminVencimientosMenu:
        return _buildRoute(
          _protegerAdmin(const AdminVencimientosMenuScreen()),
          settings,
        );

      case AppRoutes.adminRevisiones:
        return _buildRoute(
          _protegerAdmin(const AdminRevisionesScreen()),
          settings,
        );

      case AppRoutes.adminReportes:
        return _buildRoute(
          _protegerAdmin(const AdminReportsScreen()),
          settings,
        );

      case AppRoutes.vencimientosChoferes:
        return _buildRoute(
          _protegerAdmin(const AdminVencimientosChoferesScreen()),
          settings,
        );

      case AppRoutes.vencimientosChasis:
        return _buildRoute(
          _protegerAdmin(const AdminVencimientosChasisScreen()),
          settings,
        );

      case AppRoutes.vencimientosAcoplados:
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
          // ✅ MEJORA PRO: Uso de constante de texto para consistencia
          title: const Text(AppTexts.rutaNoEncontrada), 
        ),
        body: Center(
          child: ElevatedButton(
            onPressed: () {
              Navigator.of(context).pushNamedAndRemoveUntil(
                AppRoutes.login, // ✅ Manda seguro a la constante de login
                (_) => false,
              );
            },
            child: const Text("VOLVER AL INICIO"),
          ),
        ),
      ),
    );
  }
}
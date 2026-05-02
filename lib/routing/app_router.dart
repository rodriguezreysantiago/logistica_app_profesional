import 'package:flutter/material.dart';

import '../features/sync_dashboard/screens/sync_dashboard_screen.dart'; // ✅ OK (ahora se usa)

import '../core/services/prefs_service.dart';
import '../core/services/capabilities.dart';
import '../core/constants/app_constants.dart';

import '../shared/widgets/guards/auth_guard.dart';
import '../shared/widgets/guards/role_guard.dart';

import '../features/home/screens/main_panel.dart';

import '../features/vehicles/screens/user_mi_equipo_screen.dart';
import '../features/employees/screens/user_mi_perfil_screen.dart';
import '../features/expirations/screens/user_mis_vencimientos_screen.dart';

import '../features/admin_dashboard/screens/admin_shell.dart';
import '../features/admin_dashboard/screens/admin_estado_bot_screen.dart';
import '../features/admin_dashboard/screens/admin_volvo_alertas_screen.dart';
import '../features/employees/screens/admin_personal_lista_screen.dart';
import '../features/vehicles/screens/admin_vehiculos_lista_screen.dart';
import '../features/vehicles/screens/admin_mantenimiento_screen.dart';
import '../features/expirations/screens/admin_vencimientos_menu_screen.dart';
import '../features/revisions/screens/admin_revisiones_screen.dart';
import '../features/reports/screens/admin_reports_screen.dart';

import '../features/expirations/screens/admin_vencimientos_choferes_screen.dart';
import '../features/expirations/screens/admin_vencimientos_chasis_screen.dart';
import '../features/expirations/screens/admin_vencimientos_acoplados_screen.dart';
import '../features/expirations/screens/admin_vencimientos_calendario_screen.dart';

class AppRouter {
  AppRouter._();

  static Widget _proteger(Widget child) {
    return AuthGuard(child: child);
  }

  static Widget _protegerAdmin(Widget child) {
    // Cambio: antes pedíamos rol literal ADMIN. Ahora pedimos la
    // capability `verPanelAdmin` — la tienen ADMIN y SUPERVISOR. Cada
    // pantalla del panel oculta los tiles que el rol no puede usar
    // (ver admin_panel_screen).
    return AuthGuard(
      child: RoleGuard(
        requiredCapability: Capability.verPanelAdmin,
        child: child,
      ),
    );
  }

  /// Para pantallas reservadas EXCLUSIVAMENTE a ADMIN (ej. Sync
  /// Dashboard, Gestión de roles). Usá esta en vez de `_protegerAdmin`
  /// cuando ni siquiera SUPERVISOR debe entrar.
  static Widget _protegerSoloAdmin(Widget child) {
    return AuthGuard(
      child: RoleGuard(
        requiredRole: AppRoles.admin,
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

      // ================= HOME =================
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

      // ================= USER =================
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

      // ================= ADMIN =================
      // Shell con NavigationRail/BottomNav que contiene todas las secciones admin.
      // La AdminPanelScreen original se renderiza como sección "Inicio" del shell.
      case AppRoutes.adminPanel:
        return _buildRoute(
          _protegerAdmin(const AdminShell()),
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

      case AppRoutes.vencimientosCalendario:
        return _buildRoute(
          _protegerAdmin(const AdminVencimientosCalendarioScreen()),
          settings,
        );

      // ================= 🔥 NUEVO: SYNC DASHBOARD =================
      // Restringido a ADMIN (no SUPERVISOR): muestra info técnica de
      // sincronización y operaciones potencialmente disruptivas. Los
      // supervisores no la necesitan para su día a día.
      case AppRoutes.syncDashboard:
        return _buildRoute(
          _protegerSoloAdmin(const SyncDashboardScreen()),
          settings,
        );

      // ================= MANTENIMIENTO PREVENTIVO =================
      // Lista de tractores ordenados por urgencia de service
      // (basado en `serviceDistance` que viene del API Volvo).
      case AppRoutes.adminMantenimiento:
        return _buildRoute(
          _protegerAdmin(const AdminMantenimientoScreen()),
          settings,
        );

      // ================= ALERTAS VOLVO =================
      // Tablero de eventos del Vehicle Alerts API (IDLING, OVERSPEED,
      // DISTANCE_ALERT, PTO, TELL_TALE, ALARM, etc.) populado por la
      // scheduled function `volvoAlertasPoller` cada 5 min.
      case AppRoutes.adminVolvoAlertas:
        return _buildRoute(
          _protegerAdmin(const AdminVolvoAlertasScreen()),
          settings,
        );

      // ================= ESTADO DEL BOT =================
      // Dashboard en vivo del bot Node.js de WhatsApp. Lee de
      // BOT_HEALTH/main que el bot escribe cada 60s.
      case AppRoutes.adminEstadoBot:
        return _buildRoute(
          _protegerAdmin(const AdminEstadoBotScreen()),
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
          title: const Text(AppTexts.rutaNoEncontrada),
        ),
        body: Center(
          child: ElevatedButton(
            onPressed: () {
              Navigator.of(context).pushNamedAndRemoveUntil(
                AppRoutes.login,
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
import 'package:flutter/material.dart';
import '../../core/services/prefs_service.dart';
import '../../core/constants/app_constants.dart'; // ✅ MEJORA PRO: Acceso a rutas y roles

class AdminGuard extends StatelessWidget {
  final Widget child;

  const AdminGuard({
    super.key,
    required this.child,
  });

  bool get _isAdmin {
    // ✅ MEJORA PRO: Comparación robusta usando constantes centralizadas
    return PrefsService.rol.trim().toUpperCase() == AppRoles.admin;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      // ✅ MEJORA PRO: Redirección segura usando constantes
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;

        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.home,
          (route) => false,
        );
      });

      // Retornamos un cargador vacío mientras se procesa la salida
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Si es admin, dejamos pasar al widget solicitado
    return child;
  }
}
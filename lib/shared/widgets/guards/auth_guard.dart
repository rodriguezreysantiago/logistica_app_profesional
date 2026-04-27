import 'package:flutter/material.dart';
import '../../../core/services/prefs_service.dart';
import '../../../core/constants/app_constants.dart'; // ✅ MEJORA PRO: Uso de rutas centralizadas

class AuthGuard extends StatelessWidget {
  final Widget child;

  const AuthGuard({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Verificamos el estado de la sesión en SharedPreferences
    if (!PrefsService.isLoggedIn) {
      
      // ✅ REDIRECCIÓN SEGURA: Usamos addPostFrameCallback para esperar a que 
      // el frame termine de construirse antes de disparar la navegación.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;

        // ✅ MEJORA PRO: Referencia a la constante AppRoutes.login en lugar de '/'
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.login,
          (route) => false,
        );
      });

      // Pantalla de transición limpia mientras se redirige
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Si hay sesión activa, permitimos el acceso al contenido
    return child;
  }
}
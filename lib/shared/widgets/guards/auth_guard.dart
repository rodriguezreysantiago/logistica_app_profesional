import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/prefs_service.dart';

/// Guard que protege rutas autenticadas.
///
/// Hoy verifica DOS cosas (cualquiera que falle redirige al login):
/// 1. `PrefsService.isLoggedIn` — flag local que escribimos al login.
/// 2. `FirebaseAuth.instance.currentUser != null` — el token JWT
///    todavía es válido (lo refresca Firebase Auth automáticamente).
///
/// Esto cubre el caso donde el cliente cerró la app hace mucho tiempo
/// y Firebase invalidó la sesión: aunque las prefs locales digan que
/// estaba logueado, sin token activo no puede leer Firestore (las
/// rules requieren `request.auth.uid`).
class AuthGuard extends StatelessWidget {
  final Widget child;

  const AuthGuard({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final hasLocalSession = PrefsService.isLoggedIn;
    final hasFirebaseSession = FirebaseAuth.instance.currentUser != null;

    // Si quedó desincronizado (típico: token Firebase expiró pero las
    // prefs siguen marcadas), limpiamos las prefs antes de redirigir
    // para que el próximo login arranque de cero.
    if (hasLocalSession && !hasFirebaseSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await PrefsService.clear();
      });
    }

    if (!hasLocalSession || !hasFirebaseSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.login,
          (route) => false,
        );
      });

      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Sesión sana (local + Firebase): permitimos el contenido.
    return child;
  }
}

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/prefs_service.dart';
import '../../../core/services/capabilities.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/utils/app_feedback.dart';

/// Guard de pantallas que requieren un rol o capability específicos.
///
/// Modos de uso:
///
/// **Por capability (preferido)** — chequea si el rol del usuario tiene
/// el permiso indicado. Mejor que `requiredRole` porque no depende del
/// nombre exacto del rol (ej. tanto SUPERVISOR como ADMIN tienen
/// `verPanelAdmin`):
///
/// ```dart
/// RoleGuard(
///   requiredCapability: Capability.verPanelAdmin,
///   child: AdminShell(),
/// )
/// ```
///
/// **Por rol literal (legacy)** — solo deja pasar al rol exacto. Útil
/// cuando una pantalla la usa exclusivamente un rol y no queremos que
/// otros roles con la misma capability entren:
///
/// ```dart
/// RoleGuard(requiredRole: AppRoles.admin, child: ...)
/// ```
///
/// Si se pasan ambos, prevalece `requiredCapability`.
class RoleGuard extends StatelessWidget {
  final Widget child;
  final String requiredRole;
  final Capability? requiredCapability;

  const RoleGuard({
    super.key,
    required this.child,
    this.requiredRole = AppRoles.admin,
    this.requiredCapability,
  });

  @override
  Widget build(BuildContext context) {
    final String dni = PrefsService.dni;
    final String localRole = PrefsService.rol.trim().toUpperCase();

    // 1. PRIMER FILTRO: Si ni siquiera tiene DNI en memoria, afuera.
    if (dni.isEmpty) {
      return _denegarAcceso(context, "Sesión no válida");
    }

    // Helper local: ¿el rol dado satisface el requerimiento?
    bool autoriza(String rol) {
      if (requiredCapability != null) {
        return Capabilities.can(rol, requiredCapability!);
      }
      return rol.toUpperCase() == requiredRole.toUpperCase();
    }

    // 2. OPTIMIZACIÓN UX: Si el rol en memoria ya autoriza, mostramos
    // la pantalla inmediatamente sin esperar a Firestore.
    if (autoriza(localRole)) {
      return child;
    }

    // 3. SEGUNDO FILTRO (SEGURIDAD): Validamos contra Firestore por si
    // hubo cambios de permisos.
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection(AppCollections.empleados)
          .doc(dni)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return _denegarAcceso(context, "Usuario no encontrado en el sistema");
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final String rolActual =
            (data['ROL'] ?? '').toString().trim().toUpperCase();

        if (!autoriza(rolActual)) {
          return _denegarAcceso(
              context, "No tenés permisos para esta sección");
        }

        return child;
      },
    );
  }

  Widget _denegarAcceso(BuildContext context, String mensaje) {
    // Usamos addPostFrameCallback para no disparar la navegación en medio del build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;

      AppFeedback.error(context, mensaje);

      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.home, // ✅ MEJORA: Ruta centralizada
        (_) => false,
      );
    });

    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/capabilities.dart';
import '../../../core/services/prefs_service.dart';
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
    final user = FirebaseAuth.instance.currentUser;
    final String dni = PrefsService.dni;

    // 1. PRIMER FILTRO: sin sesion activa, afuera.
    if (user == null || dni.isEmpty) {
      return _denegarAcceso(context, "Sesión no válida");
    }

    // Helper local: ¿el rol dado satisface el requerimiento?
    bool autoriza(String rol) {
      if (requiredCapability != null) {
        return Capabilities.can(rol, requiredCapability!);
      }
      return rol.toUpperCase() == requiredRole.toUpperCase();
    }

    // CRITICO (auditoria 2026-05-18): la fuente de verdad es el JWT
    // (custom claims firmados por Firebase) — NO `PrefsService.rol`,
    // que vive en secure storage del device y un atacante con Frida
    // / device rooteado podia setearlo a "ADMIN" y "verse" el panel
    // (las acciones reales las atajan las rules, pero la UI no debe
    // habilitar tiles a los que no se tiene derecho).
    //
    // getIdTokenResult(false) usa el token cacheado localmente por
    // Firebase Auth — no hace network call salvo que este por
    // expirar. Latencia tipica < 50ms.
    return FutureBuilder<IdTokenResult>(
      future: user.getIdTokenResult(),
      builder: (context, tokenSnap) {
        if (tokenSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (tokenSnap.hasError || !tokenSnap.hasData) {
          return _denegarAcceso(context, "Sesión expirada");
        }
        final jwtRole = (tokenSnap.data?.claims?['rol'] ?? '')
            .toString()
            .trim()
            .toUpperCase();

        // Si el JWT autoriza, dejamos pasar de inmediato. Si no
        // autoriza, igualmente verificamos contra Firestore (defense
        // in depth: si el JWT esta corrupto o expirado).
        if (jwtRole.isNotEmpty && autoriza(jwtRole)) {
          return child;
        }

        // 2. SEGUNDO FILTRO (defensa): Validamos contra Firestore por
        // si el JWT quedo desactualizado (cambio de rol reciente
        // pendiente de propagacion). Tambien chequeamos ACTIVO — un
        // empleado dado de baja cuya sesion todavia esta caliente
        // no debe pasar (auditoria 2026-05-18).
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection(AppCollections.empleados)
              .doc(dni)
              .get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return _denegarAcceso(
                  context, "Usuario no encontrado en el sistema");
            }
            final data = snapshot.data!.data() as Map<String, dynamic>;
            // ACTIVO check (default true si falta el campo).
            if (data['ACTIVO'] == false) {
              return _denegarAcceso(
                  context, "Usuario inactivo. Contactá al admin.");
            }
            final String rolActual =
                (data['ROL'] ?? '').toString().trim().toUpperCase();
            if (!autoriza(rolActual)) {
              return _denegarAcceso(
                  context, "No tenés permisos para esta sección");
            }
            return child;
          },
        );
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
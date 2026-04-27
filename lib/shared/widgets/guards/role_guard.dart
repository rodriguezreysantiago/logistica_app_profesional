import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/prefs_service.dart';
import '../../../core/constants/app_constants.dart';

class RoleGuard extends StatelessWidget {
  final Widget child;
  final String requiredRole;

  const RoleGuard({
    super.key,
    required this.child,
    this.requiredRole = AppRoles.admin, // ✅ MEJORA: Usamos la constante por defecto
  });

  @override
  Widget build(BuildContext context) {
    final String dni = PrefsService.dni;
    final String localRole = PrefsService.rol.trim().toUpperCase();

    // 1. PRIMER FILTRO: Si ni siquiera tiene DNI en memoria, afuera.
    if (dni.isEmpty) {
      return _denegarAcceso(context, "Sesión no válida");
    }

    // 2. OPTIMIZACIÓN UX: Si el rol en memoria ya coincide, mostramos la pantalla
    // inmediatamente para que no haya "parpadeo" de carga.
    if (localRole == requiredRole.toUpperCase()) {
      return child;
    }

    // 3. SEGUNDO FILTRO (SEGURIDAD): Validamos contra Firestore por si hubo cambios de permisos.
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection(AppCollections.empleados) // ✅ MEJORA: Colección centralizada
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
        final String rolActual = (data['ROL'] ?? '').toString().trim().toUpperCase();

        // Si el rol en la base de datos no coincide con el requerido
        if (rolActual != requiredRole.toUpperCase()) {
          return _denegarAcceso(context, "No tenés permisos para esta sección");
        }

        // Si todo está bien, permitimos el acceso
        return child;
      },
    );
  }

  Widget _denegarAcceso(BuildContext context, String mensaje) {
    // Usamos addPostFrameCallback para no disparar la navegación en medio del build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensaje, style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );

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
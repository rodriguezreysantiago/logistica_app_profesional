import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/prefs_service.dart';

class RoleGuard extends StatelessWidget {
  final Widget child;
  final String requiredRole;

  const RoleGuard({
    super.key,
    required this.child,
    this.requiredRole = 'ADMIN',
  });

  @override
  Widget build(BuildContext context) {
    final String dni = PrefsService.dni;

    if (dni.isEmpty) {
      return _denegarAcceso(context);
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('EMPLEADOS')
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
          return _denegarAcceso(context);
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final String rolActual =
            (data['ROL'] ?? '').toString().trim().toUpperCase();

        if (rolActual != requiredRole.toUpperCase()) {
          return _denegarAcceso(context);
        }

        return child;
      },
    );
  }

  Widget _denegarAcceso(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No tenés permisos para acceder a esta sección'),
          backgroundColor: Colors.redAccent,
        ),
      );

      Navigator.of(context).pushNamedAndRemoveUntil(
        '/home',
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
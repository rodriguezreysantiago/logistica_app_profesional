import 'package:flutter/material.dart';
import '../../core/services/prefs_service.dart';

class AdminGuard extends StatelessWidget {
  final Widget child;

  const AdminGuard({
    super.key,
    required this.child,
  });

  bool get _isAdmin {
    return PrefsService.rol.trim().toUpperCase() == 'ADMIN';
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;

        Navigator.of(context).pushNamedAndRemoveUntil(
          '/home',
          (route) => false,
        );
      });

      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return child;
  }
}
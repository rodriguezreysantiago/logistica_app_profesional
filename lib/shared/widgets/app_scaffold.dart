import 'package:flutter/material.dart';

import 'app_shell_context.dart';

/// Scaffold unificado con fondo de imagen + overlay oscuro.
/// Reemplaza el patrón repetido de Stack con Positioned.fill + Image.asset.
///
/// Uso típico:
/// ```
/// AppScaffold(
///   title: 'Gestión de Flota',
///   actions: [IconButton(...)],
///   floatingActionButton: FloatingActionButton(...),
///   body: ListView(...),
/// );
/// ```
///
/// **Modo embebido (shell):** si la pantalla está dentro de un shell de
/// navegación (ej: AdminShell con NavigationRail), AppScaffold detecta
/// el [AppShellContext] y solo renderiza el body + FAB. El AppBar y
/// el fondo decorado los pone el shell.
///
/// Si la pantalla NO debe tener el fondo decorado (ej: pantallas internas
/// de visor/preview), pasar `showBackground: false`.
class AppScaffold extends StatelessWidget {
  final String? title;
  final List<Widget>? actions;
  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final PreferredSizeWidget? bottom;
  final Widget? leading;
  final bool showBackground;
  final bool centerTitle;
  final Color? overlayColor;

  const AppScaffold({
    super.key,
    this.title,
    this.actions,
    required this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottom,
    this.leading,
    this.showBackground = true,
    this.centerTitle = true,
    this.overlayColor,
  });

  @override
  Widget build(BuildContext context) {
    final isEmbedded = AppShellContext.of(context);

    // Si estamos dentro de un shell, solo devolvemos el body + FAB.
    // El shell se encarga del AppBar, fondo, navegación y SafeArea.
    if (isEmbedded) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        // El bottom (TabBar etc.) lo respetamos en modo embedded:
        // si la pantalla lo necesita, lo ponemos arriba del body.
        body: bottom != null
            ? Column(
                children: [
                  bottom!,
                  Expanded(child: body),
                ],
              )
            : body,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
      );
    }

    // Modo normal (full screen, sin shell): comportamiento original.
    final effectiveOverlay =
        overlayColor ?? Colors.black.withAlpha(200);

    return Scaffold(
      extendBodyBehindAppBar: showBackground,
      appBar: AppBar(
        title: title != null
            ? Text(
                title!,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              )
            : null,
        leading: leading,
        actions: actions,
        centerTitle: centerTitle,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        bottom: bottom,
      ),
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      body: showBackground
          ? Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/fondo_login.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                    ),
                  ),
                ),
                Positioned.fill(child: Container(color: effectiveOverlay)),
                SafeArea(child: body),
              ],
            )
          : SafeArea(child: body),
    );
  }
}

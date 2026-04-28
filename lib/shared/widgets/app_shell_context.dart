import 'package:flutter/material.dart';

/// Indica a sus descendientes si están renderizándose dentro de un shell
/// de navegación (ej: [AdminShell] con NavigationRail).
///
/// Las pantallas (envueltas en `AppScaffold`) leen este contexto para
/// decidir si renderizar su propio chrome (AppBar + fondo) o si dejarlo
/// para el shell.
///
/// Uso típico (en el shell):
/// ```dart
/// AppShellContext(
///   isEmbedded: true,
///   child: AdminVehiculosListaScreen(),
/// );
/// ```
///
/// Uso típico (en una pantalla):
/// ```dart
/// final embedded = AppShellContext.of(context);
/// if (embedded) {
///   // Renderizamos solo el body, sin chrome
/// }
/// ```
class AppShellContext extends InheritedWidget {
  /// True si la pantalla descendiente está dentro de un shell.
  final bool isEmbedded;

  const AppShellContext({
    super.key,
    required this.isEmbedded,
    required super.child,
  });

  /// Obtiene el flag desde cualquier descendiente.
  /// Devuelve `false` si no hay un AppShellContext arriba en el árbol.
  static bool of(BuildContext context) {
    final widget =
        context.dependOnInheritedWidgetOfExactType<AppShellContext>();
    return widget?.isEmbedded ?? false;
  }

  @override
  bool updateShouldNotify(AppShellContext oldWidget) =>
      oldWidget.isEmbedded != isEmbedded;
}

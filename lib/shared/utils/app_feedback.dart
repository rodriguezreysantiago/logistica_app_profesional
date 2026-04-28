import 'package:flutter/material.dart';

/// Helper centralizado para mostrar SnackBars con paleta y duración
/// consistentes en toda la app.
///
/// Antes cada pantalla armaba su `SnackBar` con `Colors.green`,
/// `Colors.greenAccent`, `Colors.redAccent`, etc. de forma ad-hoc, lo
/// que producía tonos ligeramente distintos y duraciones inconsistentes.
/// Esto unifica todo en cuatro variantes semánticas:
///
/// - **success**: acción guardada (verde)
/// - **error**: algo falló (rojo)
/// - **warning**: atención sin error (naranja)
/// - **info**: aviso neutro (azul)
///
/// Cada variante incluye un ícono al inicio para que el mensaje sea
/// reconocible antes de leerlo.
///
/// Uso típico (con BuildContext):
/// ```dart
/// AppFeedback.success(context, 'Chofer creado');
/// AppFeedback.error(context, 'No se pudo guardar: $e');
/// ```
///
/// Uso cuando capturaste el messenger antes de un await (recomendado
/// para evitar `use_build_context_synchronously`):
/// ```dart
/// final messenger = ScaffoldMessenger.of(context);
/// await algoLargo();
/// AppFeedback.successOn(messenger, 'Listo');
/// ```
class AppFeedback {
  AppFeedback._();

  // Paleta semántica. Todas las pantallas que necesiten estos colores
  // (badges, bordes, etc.) deberían referenciar estas constantes en vez
  // de hardcodear `Colors.green` / `Colors.redAccent`.
  static const Color colorSuccess = Color(0xFF2E7D32); // green 800
  static const Color colorError = Color(0xFFD32F2F);   // red 700
  static const Color colorWarning = Color(0xFFEF6C00); // orange 800
  static const Color colorInfo = Color(0xFF1565C0);    // blue 800

  static const Duration _durationDefault = Duration(seconds: 3);
  static const Duration _durationLong = Duration(seconds: 5);

  // ---------------------------------------------------------------------------
  // CON BuildContext — caso 90% del tiempo
  // ---------------------------------------------------------------------------

  static void success(BuildContext context, String mensaje) =>
      successOn(ScaffoldMessenger.of(context), mensaje);

  static void error(BuildContext context, String mensaje) =>
      errorOn(ScaffoldMessenger.of(context), mensaje);

  static void warning(BuildContext context, String mensaje) =>
      warningOn(ScaffoldMessenger.of(context), mensaje);

  static void info(BuildContext context, String mensaje) =>
      infoOn(ScaffoldMessenger.of(context), mensaje);

  // ---------------------------------------------------------------------------
  // CON ScaffoldMessengerState — para casos post-await donde el context
  // ya no es seguro y conviene tener capturado el messenger antes.
  // ---------------------------------------------------------------------------

  static void successOn(ScaffoldMessengerState messenger, String mensaje) {
    messenger.showSnackBar(_build(
      mensaje: mensaje,
      icono: Icons.check_circle_outline,
      color: colorSuccess,
    ));
  }

  static void errorOn(ScaffoldMessengerState messenger, String mensaje) {
    messenger.showSnackBar(_build(
      mensaje: mensaje,
      icono: Icons.error_outline,
      color: colorError,
      duration: _durationLong, // los errores conviene leerlos
    ));
  }

  static void warningOn(ScaffoldMessengerState messenger, String mensaje) {
    messenger.showSnackBar(_build(
      mensaje: mensaje,
      icono: Icons.warning_amber_rounded,
      color: colorWarning,
      duration: _durationLong,
    ));
  }

  static void infoOn(ScaffoldMessengerState messenger, String mensaje) {
    messenger.showSnackBar(_build(
      mensaje: mensaje,
      icono: Icons.info_outline,
      color: colorInfo,
    ));
  }

  // ---------------------------------------------------------------------------
  // INTERNAL
  // ---------------------------------------------------------------------------

  static SnackBar _build({
    required String mensaje,
    required IconData icono,
    required Color color,
    Duration? duration,
  }) {
    return SnackBar(
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      duration: duration ?? _durationDefault,
      content: Row(
        children: [
          Icon(icono, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              mensaje,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

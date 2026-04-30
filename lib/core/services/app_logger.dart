import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Logger de errores y eventos de la app.
///
/// Encapsula la decisión de a dónde va cada cosa según la plataforma:
///
/// - **Android / iOS**: a Firebase Crashlytics, que en producción manda
///   las trazas al panel de Anthropic Cloud para que el admin vea qué
///   crasheó y a quién. En debug, Crashlytics no reporta — solo
///   `debugPrint`.
/// - **Windows / Web / desktop**: Crashlytics no tiene plugin para esas
///   plataformas, así que caemos a `debugPrint`. La app sigue
///   funcionando — solo se pierde la captura remota.
///
/// Esta clase es SEGURA de llamar antes de `Firebase.initializeApp()`:
/// si Firebase todavía no se inicializó, el `FirebaseCrashlytics.instance`
/// va a fallar y nosotros lo capturamos silenciosamente. Al peor caso,
/// el evento solo va al `debugPrint`.
class AppLogger {
  AppLogger._();

  /// Indica si Crashlytics está disponible en la plataforma actual.
  /// Aplica a Android e iOS — para Web, Windows, Linux y macOS hoy
  /// el plugin no soporta nada.
  static bool get _crashlyticsDisponible {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Inicialización opcional: en mobile, conecta los handlers globales
  /// de Flutter (`FlutterError.onError`, `PlatformDispatcher.onError`)
  /// directo a Crashlytics. Llamar después de `Firebase.initializeApp`.
  ///
  /// Si la app corre en Web/Windows, esto es no-op.
  static Future<void> init() async {
    if (!_crashlyticsDisponible) return;
    try {
      // En debug NO enviamos para no contaminar el panel con errores
      // que vemos en consola de todas formas.
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(!kDebugMode);
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;
      // Errores asíncronos no atrapados (ej. dentro de un `Future`).
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } catch (e) {
      debugPrint('AppLogger.init falló (continuamos sin Crashlytics): $e');
    }
  }

  /// Reporta un error capturado manualmente. Pensado para `try/catch`
  /// en flujos críticos donde el error no detiene la app pero querés
  /// enterarte.
  ///
  /// [fatal]: si es `true`, en Crashlytics se cuenta como crash. Default
  /// `false` — la mayoría de errores controlados son informativos.
  static void recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) {
    debugPrint('🚨 [${fatal ? 'FATAL' : 'ERROR'}]'
        '${reason != null ? ' $reason —' : ''} $error');
    if (!_crashlyticsDisponible) return;
    try {
      FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        reason: reason,
        fatal: fatal,
      );
    } catch (e) {
      debugPrint('AppLogger.recordError no pudo enviar a Crashlytics: $e');
    }
  }

  /// Log informativo (no error). Aparece como breadcrumb en el próximo
  /// crash de Crashlytics, útil para reconstruir el contexto.
  static void log(String mensaje) {
    debugPrint('ℹ️  $mensaje');
    if (!_crashlyticsDisponible) return;
    try {
      FirebaseCrashlytics.instance.log(mensaje);
    } catch (_) {
      // ignore: no queremos que un log informativo bloquee al caller.
    }
  }
}

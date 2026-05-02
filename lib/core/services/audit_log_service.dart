import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Servicio de bitácora de acciones del admin.
///
/// Cada vez que un admin hace algo que cambia el estado del negocio
/// (alta/baja/modificación de chofer o unidad, aprobación de trámite,
/// desvinculación de equipo, etc.) registramos un documento en la
/// colección `AUDITORIA_ACCIONES`. Pensado para responder preguntas
/// como "¿quién desvinculó este equipo?" tres semanas después.
///
/// **Arquitectura (2026-04-29 noche)**: ya no escribe Firestore directo
/// desde el cliente. Llama a la Cloud Function callable `auditLogWrite`
/// que valida server-side que el caller sea ADMIN (custom claim del
/// JWT) y escribe a `AUDITORIA_ACCIONES` con `admin_dni` y
/// `admin_nombre` tomados del token, no del cliente. Eso permite:
///   - Cerrar la rule de `AUDITORIA_ACCIONES` con `write: if false`
///     (solo Admin SDK escribe).
///   - Garantizar que el admin no puede falsificar el `admin_dni` ni la
///     `accion` (la function valida la accion contra una whitelist).
///
/// Llamada por HTTPS directo con [Dio] — el plugin `cloud_functions`
/// no anda en Windows desktop, así que replicamos el protocolo callable
/// manualmente igual que en `AuthService`.
///
/// Diseño:
/// - **Fire-and-forget**: el `registrar` se llama después del write
///   principal y nunca debe bloquear el flujo del admin. Si la function
///   falla acá, lo logueamos con `debugPrint` y seguimos. La acción
///   real ya pasó.
/// - **No se usa para autorización**: las reglas de negocio no dependen
///   de este log. Es solo histórico.
///
/// Estructura del documento (escrita por la function):
/// ```
/// {
///   accion: 'DESVINCULAR_EQUIPO' | 'CREAR_CHOFER' | ...,  // tipo
///   entidad: 'EMPLEADOS' | 'VEHICULOS' | 'REVISIONES',
///   entidad_id: '12345678' (DNI o patente o doc id),
///   detalles: { campo libre con metadata },
///   admin_dni: '20000000',       // ← request.auth.uid en server
///   admin_nombre: 'Pérez Juan',  // ← request.auth.token.nombre
///   timestamp: serverTimestamp(),
/// }
/// ```
///
/// Uso:
/// ```dart
/// await AuditLog.registrar(
///   accion: AuditAccion.desvincularEquipo,
///   entidad: 'EMPLEADOS',
///   entidadId: dni,
///   detalles: {'campo': 'VEHICULO', 'unidad_anterior': 'ABC123'},
/// );
/// ```
class AuditLog {
  AuditLog._();

  /// URL del callable. Mismo patrón que AuthService/volvoProxy.
  static const String _endpoint =
      'https://southamerica-east1-coopertrans-movil.cloudfunctions.net/auditLogWrite';

  /// Dio compartido entre llamadas. Lo dejamos lazy para no inicializarlo
  /// si el admin nunca dispara una acción auditable (ej. solo lee).
  static Dio? _dio;
  static Dio get _http => _dio ??= Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          // Timeout corto: la audit es fire-and-forget, no queremos
          // tener al admin esperando si el server está lento. El
          // network ya falló si tardamos más de 8s.
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

  /// Registra una acción. Nunca lanza — captura cualquier error y lo
  /// loguea para que el flujo del caller no se interrumpa por el audit.
  static Future<void> registrar({
    required AuditAccion accion,
    required String entidad,
    String? entidadId,
    Map<String, dynamic>? detalles,
  }) async {
    try {
      // Si no hay sesión activa, no tiene sentido auditar — la function
      // rechazaría con permission-denied igual. Salimos silencioso.
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint(
            'AuditLog skip: sin sesión Firebase (acción=${accion.codigo})');
        return;
      }

      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        debugPrint('AuditLog skip: sin idToken (acción=${accion.codigo})');
        return;
      }

      final response = await _http.post<Map<String, dynamic>>(
        _endpoint,
        data: {
          // Protocolo callable: payload va envuelto en `data`.
          'data': {
            'accion': accion.codigo,
            'entidad': entidad,
            if (entidadId != null && entidadId.isNotEmpty)
              'entidadId': entidadId,
            if (detalles != null && detalles.isNotEmpty) 'detalles': detalles,
          },
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          // No tiramos exception por status code — manejamos el error
          // manualmente abajo y logueamos.
          validateStatus: (_) => true,
          responseType: ResponseType.json,
        ),
      );

      if (response.statusCode == null || response.statusCode! >= 400) {
        // No relanzamos — la audit es fire-and-forget. Logueamos para
        // diagnóstico en Crashlytics/console.
        final err = response.data?['error'] as Map<String, dynamic>?;
        debugPrint(
          'AuditLog falló (${response.statusCode}) '
          'accion=${accion.codigo}: ${err?['message'] ?? 'sin mensaje'}',
        );
      }
    } catch (e) {
      debugPrint('AuditLog excepción (no bloqueante): $e');
    }
  }
}

/// Enumera los tipos de acción que se auditan, para que el admin no
/// invente strings y rompa búsquedas posteriores.
///
/// **Nota**: cualquier nuevo caso que se agregue acá hay que sumarlo
/// también en la whitelist `AUDIT_ACCIONES_PERMITIDAS` del callable
/// `auditLogWrite` en `functions/src/index.ts`. Sin eso, la function
/// rechaza la acción con `invalid-argument`.
enum AuditAccion {
  // ---- Personal ----
  crearChofer('CREAR_CHOFER'),
  editarChofer('EDITAR_CHOFER'),
  cambiarFotoPerfil('CAMBIAR_FOTO_PERFIL'),
  reemplazarPapelChofer('REEMPLAZAR_PAPEL_CHOFER'),

  // ---- Flota ----
  crearVehiculo('CREAR_VEHICULO'),
  editarVehiculo('EDITAR_VEHICULO'),
  cambiarFotoVehiculo('CAMBIAR_FOTO_VEHICULO'),

  // ---- Asignaciones ----
  asignarEquipo('ASIGNAR_EQUIPO'),
  desvincularEquipo('DESVINCULAR_EQUIPO'),

  // ---- Revisiones ----
  aprobarRevision('APROBAR_REVISION'),
  rechazarRevision('RECHAZAR_REVISION'),

  // ---- Alertas Volvo ----
  marcarAlertaVolvoAtendida('MARCAR_ALERTA_VOLVO_ATENDIDA');

  final String codigo;
  const AuditAccion(this.codigo);
}

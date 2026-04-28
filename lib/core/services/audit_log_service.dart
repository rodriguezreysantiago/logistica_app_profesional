import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'prefs_service.dart';

/// Servicio de bitácora de acciones del admin.
///
/// Cada vez que un admin hace algo que cambia el estado del negocio
/// (alta/baja/modificación de chofer o unidad, aprobación de trámite,
/// desvinculación de equipo, etc.) registramos un documento en la
/// colección `AUDITORIA_ACCIONES`. Pensado para responder preguntas
/// como "¿quién desvinculó este equipo?" tres semanas después.
///
/// Diseño:
/// - **Fire-and-forget**: el `registrar` se llama después del write
///   principal y nunca debe bloquear el flujo del admin. Si Firestore
///   falla acá, lo logueamos con `debugPrint` y seguimos. La acción
///   real ya pasó.
/// - **Sin lectura previa**: nunca consultamos Firestore para construir
///   el audit log. Toda la info viene del caller + PrefsService.
/// - **No se usa para autorización**: las reglas de negocio no dependen
///   de este log. Es solo histórico.
///
/// Estructura del documento:
/// ```
/// {
///   accion: 'DESVINCULAR_EQUIPO' | 'CREAR_CHOFER' | ...,  // tipo
///   entidad: 'EMPLEADOS' | 'VEHICULOS' | 'REVISIONES' | ...,
///   entidad_id: '12345678' (DNI o patente o doc id),
///   detalles: { campo libre con metadata },
///   admin_dni: '20000000',
///   admin_nombre: 'Pérez Juan',
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

  static const String _coleccion = 'AUDITORIA_ACCIONES';

  /// Registra una acción. Nunca lanza — captura cualquier error y lo
  /// loguea para que el flujo del caller no se interrumpa por el audit.
  static Future<void> registrar({
    required AuditAccion accion,
    required String entidad,
    String? entidadId,
    Map<String, dynamic>? detalles,
  }) async {
    try {
      await FirebaseFirestore.instance.collection(_coleccion).add({
        'accion': accion.codigo,
        'entidad': entidad,
        if (entidadId != null && entidadId.isNotEmpty)
          'entidad_id': entidadId,
        if (detalles != null && detalles.isNotEmpty) 'detalles': detalles,
        'admin_dni': PrefsService.dni,
        'admin_nombre': PrefsService.nombre,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('AuditLog falló (no bloqueante): $e');
    }
  }
}

/// Enumera los tipos de acción que se auditan, para que el admin no
/// invente strings y rompa búsquedas posteriores.
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
  rechazarRevision('RECHAZAR_REVISION');

  final String codigo;
  const AuditAccion(this.codigo);
}

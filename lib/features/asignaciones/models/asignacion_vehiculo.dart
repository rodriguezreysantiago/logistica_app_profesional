import 'package:cloud_firestore/cloud_firestore.dart';

/// Doc en `ASIGNACIONES_VEHICULO`. Cada uno representa el período en
/// que un chofer manejó una unidad. La asignación activa actualmente
/// es la que tiene `hasta == null`.
///
/// Los campos `_nombre` son **snapshots**: se guardan tal cual en el
/// momento del cambio para que el historial no quede vacío si más
/// adelante se borra/renombra un chofer o un admin.
class AsignacionVehiculo {
  /// Doc id auto-generado por Firestore.
  final String id;

  /// Patente del vehículo. Mismo formato que se usa como doc id en
  /// `VEHICULOS` (ej: "ABC123" o "AB123CD").
  final String vehiculoId;

  /// DNI del chofer. Mismo formato que doc id en `EMPLEADOS`.
  final String choferDni;

  /// Snapshot del nombre del chofer al momento de la asignación.
  /// Puede ser null si no se conocía al cambiar.
  final String? choferNombre;

  /// Inicio del período de asignación.
  final DateTime desde;

  /// Fin del período. `null` = asignación todavía activa.
  final DateTime? hasta;

  /// DNI del admin/supervisor que disparó el cambio.
  final String asignadoPorDni;

  /// Snapshot del nombre del admin/supervisor.
  final String? asignadoPorNombre;

  /// Texto libre opcional (ej. "rotación semanal", "vacaciones del titular",
  /// "service en taller"). Útil para entender el motivo a posteriori.
  final String? motivo;

  const AsignacionVehiculo({
    required this.id,
    required this.vehiculoId,
    required this.choferDni,
    required this.choferNombre,
    required this.desde,
    required this.hasta,
    required this.asignadoPorDni,
    required this.asignadoPorNombre,
    required this.motivo,
  });

  /// `true` si la asignación es la actualmente vigente (sin `hasta`).
  bool get esActiva => hasta == null;

  /// Días que duró la asignación. Si todavía está activa, calcula contra
  /// el momento de la consulta.
  int diasDuracion() {
    final fin = hasta ?? DateTime.now();
    return fin.difference(desde).inDays;
  }

  factory AsignacionVehiculo.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return AsignacionVehiculo.fromMap(doc.id, doc.data());
  }

  /// Parsea desde un map crudo + id. Útil para tests sin Firestore real
  /// (no requiere instanciar `DocumentSnapshot`, que es sealed).
  factory AsignacionVehiculo.fromMap(String id, Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    return AsignacionVehiculo(
      id: id,
      vehiculoId: (d['vehiculo_id'] ?? '').toString(),
      choferDni: (d['chofer_dni'] ?? '').toString(),
      choferNombre: d['chofer_nombre']?.toString(),
      desde: (d['desde'] as Timestamp?)?.toDate() ?? DateTime.now(),
      hasta: (d['hasta'] as Timestamp?)?.toDate(),
      asignadoPorDni: (d['asignado_por_dni'] ?? '').toString(),
      asignadoPorNombre: d['asignado_por_nombre']?.toString(),
      motivo: d['motivo']?.toString(),
    );
  }
}

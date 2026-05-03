import 'package:cloud_firestore/cloud_firestore.dart';

/// Doc en `ASIGNACIONES_ENGANCHE`. Cada uno representa el período en
/// que un enganche (batea, tolva, bivuelco, tanque) estuvo enganchado
/// a un tractor. La asignación activa actualmente es la que tiene
/// `hasta == null`.
///
/// Espejo conceptual de [AsignacionVehiculo] (chofer↔tractor) pero
/// para la relación tractor↔enganche.
///
/// **Por qué existe:** sin este registro temporal, no se puede
/// calcular cuántos km recorrió una cubierta de enganche. La cubierta
/// está en el enganche, pero los km los recorre el tractor — y un
/// enganche puede pasar por varios tractores en su vida útil. Para
/// reconstruir los km de la cubierta hay que sumar los km de cada
/// tractor durante el período que tuvo el enganche enganchado.
///
/// Los campos `_nombre` son **snapshots**: se guardan tal cual en el
/// momento del cambio para que el historial no quede vacío si más
/// adelante se borra/renombra una unidad o un admin.
class AsignacionEnganche {
  /// Doc id auto-generado por Firestore.
  final String id;

  /// Patente del enganche. Mismo formato que se usa como doc id en
  /// `VEHICULOS` para los enganches (ej: "BAT123").
  final String engancheId;

  /// Patente del tractor al que está enganchado. Mismo formato que doc
  /// id en `VEHICULOS` para tractores (ej: "ABC123").
  final String tractorId;

  /// Snapshot del modelo del tractor al momento del enganchamiento.
  /// Útil para historial visual ("estuvo en VOLVO FH 540"). Puede ser
  /// `null` si no se conocía al cambiar.
  final String? tractorModelo;

  /// Inicio del período de enganchamiento.
  final DateTime desde;

  /// Fin del período. `null` = asignación todavía activa.
  final DateTime? hasta;

  /// DNI del admin/supervisor que disparó el cambio.
  final String asignadoPorDni;

  /// Snapshot del nombre del admin/supervisor.
  final String? asignadoPorNombre;

  /// Texto libre opcional (ej. "rotación de carga", "viaje a Mendoza").
  final String? motivo;

  const AsignacionEnganche({
    required this.id,
    required this.engancheId,
    required this.tractorId,
    required this.tractorModelo,
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

  factory AsignacionEnganche.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return AsignacionEnganche.fromMap(doc.id, doc.data());
  }

  /// Parsea desde un map crudo + id. Útil para tests sin Firestore real
  /// (no requiere instanciar `DocumentSnapshot`, que es sealed).
  factory AsignacionEnganche.fromMap(String id, Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    return AsignacionEnganche(
      id: id,
      engancheId: (d['enganche_id'] ?? '').toString(),
      tractorId: (d['tractor_id'] ?? '').toString(),
      tractorModelo: d['tractor_modelo']?.toString(),
      desde: (d['desde'] as Timestamp?)?.toDate() ?? DateTime.now(),
      hasta: (d['hasta'] as Timestamp?)?.toDate(),
      asignadoPorDni: (d['asignado_por_dni'] ?? '').toString(),
      asignadoPorNombre: d['asignado_por_nombre']?.toString(),
      motivo: d['motivo']?.toString(),
    );
  }
}

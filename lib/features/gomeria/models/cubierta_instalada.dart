import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/posiciones.dart';

/// Registro temporal inmutable de una instalación de cubierta en una
/// posición. Espejo conceptual de `AsignacionVehiculo` (chofer↔tractor)
/// pero para cubierta↔posición.
///
/// La instalación activa (la cubierta está actualmente en esa posición)
/// tiene `hasta == null`. Cuando se retira, se cierra (`hasta = now`,
/// `kmUnidadAlRetirar` y `kmRecorridos` calculados).
///
/// **Cálculo de km recorridos** (al cerrar):
/// - Tractor: `kmUnidadAlRetirar - kmUnidadAlInstalar` directo (los
///   km del tractor salen de Volvo via `VEHICULOS.KM_ACTUAL`).
/// - Enganche: cruzar con `ASIGNACIONES_ENGANCHE` (qué tractores
///   tuvieron el enganche en este período) y sumar los km de cada
///   tractor durante su sub-período. La lógica vive en `GomeriaService`.
class CubiertaInstalada {
  final String id;

  /// FK al doc en CUBIERTAS.
  final String cubiertaId;

  /// Snapshot del código legible de la cubierta (ej. "CUB-0042").
  /// Para listados sin join.
  final String cubiertaCodigo;

  /// Patente del tractor o enganche donde se instaló.
  final String unidadId;

  final TipoUnidadCubierta unidadTipo;

  /// Código de posición (ej. "DIR_IZQ", "ENG2_DER_INT"). Se mapea a
  /// `PosicionCubierta` con `posicionPorCodigo[posicion]`.
  final String posicion;

  /// Cantidad de vidas que tenía la cubierta AL INSTALAR. Útil para
  /// reportes ("cuánto duraron las cubiertas en su 1ra vida vs 2da").
  final int vidaAlInstalar;

  /// Inicio de la instalación.
  final DateTime desde;

  /// Fin de la instalación (= retiro). `null` = activa.
  final DateTime? hasta;

  /// Km del odómetro de la unidad (tractor o enganche) al instalar.
  /// Para tractor: `VEHICULOS.KM_ACTUAL` al momento de instalar.
  /// Para enganche: este valor representa el "punto cero" del cálculo
  /// — los km recorridos por la cubierta se calculan con cruce contra
  /// ASIGNACIONES_ENGANCHE (no con el odómetro del enganche, que no
  /// existe).
  final double? kmUnidadAlInstalar;

  /// Km del odómetro al retirar. `null` = aún instalada.
  final double? kmUnidadAlRetirar;

  /// Km recorridos por la cubierta durante esta instalación. `null`
  /// hasta que se retire. Para tractor: diff directa. Para enganche:
  /// suma cruzada con ASIGNACIONES_ENGANCHE.
  final double? kmRecorridos;

  /// DNI del supervisor de gomería que registró la instalación.
  final String instaladoPorDni;
  final String? instaladoPorNombre;

  /// DNI del supervisor que registró el retiro (`null` si activa).
  final String? retiradoPorDni;
  final String? retiradoPorNombre;

  /// Texto libre opcional (ej. "rotación", "reemplazo por pinchazo").
  final String? motivo;

  const CubiertaInstalada({
    required this.id,
    required this.cubiertaId,
    required this.cubiertaCodigo,
    required this.unidadId,
    required this.unidadTipo,
    required this.posicion,
    required this.vidaAlInstalar,
    required this.desde,
    required this.hasta,
    required this.kmUnidadAlInstalar,
    required this.kmUnidadAlRetirar,
    required this.kmRecorridos,
    required this.instaladoPorDni,
    required this.instaladoPorNombre,
    required this.retiradoPorDni,
    required this.retiradoPorNombre,
    required this.motivo,
  });

  bool get esActiva => hasta == null;

  /// Días que duró la instalación. Si activa, contra ahora.
  int diasDuracion() {
    final fin = hasta ?? DateTime.now();
    return fin.difference(desde).inDays;
  }

  /// Posición tipada (resuelta del campo `posicion` string).
  PosicionCubierta? get posicionTipada => posicionPorCodigo[posicion];

  factory CubiertaInstalada.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      CubiertaInstalada.fromMap(doc.id, doc.data());

  factory CubiertaInstalada.fromMap(String id, Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    return CubiertaInstalada(
      id: id,
      cubiertaId: (d['cubierta_id'] ?? '').toString(),
      cubiertaCodigo: (d['cubierta_codigo'] ?? '').toString(),
      unidadId: (d['unidad_id'] ?? '').toString(),
      unidadTipo: d['unidad_tipo'] == 'ENGANCHE'
          ? TipoUnidadCubierta.enganche
          : TipoUnidadCubierta.tractor,
      posicion: (d['posicion'] ?? '').toString(),
      vidaAlInstalar: (d['vida_al_instalar'] as num?)?.toInt() ?? 1,
      desde: (d['desde'] as Timestamp?)?.toDate() ?? DateTime.now(),
      hasta: (d['hasta'] as Timestamp?)?.toDate(),
      kmUnidadAlInstalar: (d['km_unidad_al_instalar'] as num?)?.toDouble(),
      kmUnidadAlRetirar: (d['km_unidad_al_retirar'] as num?)?.toDouble(),
      kmRecorridos: (d['km_recorridos'] as num?)?.toDouble(),
      instaladoPorDni: (d['instalado_por_dni'] ?? '').toString(),
      instaladoPorNombre: d['instalado_por_nombre']?.toString(),
      retiradoPorDni: d['retirado_por_dni']?.toString(),
      retiradoPorNombre: d['retirado_por_nombre']?.toString(),
      motivo: d['motivo']?.toString(),
    );
  }
}

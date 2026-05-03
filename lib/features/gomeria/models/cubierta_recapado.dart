import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/posiciones.dart';

/// Evento de recapado — 1 doc por cada vez que una cubierta se manda
/// al proveedor de recapado.
///
/// Ciclo de vida del doc:
/// 1. Se crea con `fechaEnvio`, `proveedor`, `fechaRetorno = null` y
///    `resultado = null`. La cubierta pasa a estado `EN_RECAPADO`.
/// 2. Cuando vuelve, el supervisor completa `fechaRetorno`, `resultado`
///    (RECIBIDA o DESCARTADA_POR_PROVEEDOR), `costo` y `notas`. La
///    cubierta pasa a `EN_DEPOSITO` (con vidas++) o `DESCARTADA`.
class CubiertaRecapado {
  final String id;

  /// FK al doc en CUBIERTAS.
  final String cubiertaId;

  /// Snapshot del código legible (ej. "CUB-0042").
  final String cubiertaCodigo;

  /// Cuántas vidas TENDRÁ la cubierta si vuelve recibida (vida actual + 1).
  /// Útil para reportar "cuántas recapadas se hicieron este mes" sin
  /// mirar el detalle de cada cubierta.
  final int vidaRecapado;

  /// Nombre del proveedor de recapado (ej. "Recauchutados Sur").
  final String proveedor;

  final DateTime fechaEnvio;

  /// `null` = aún en proceso (no volvió).
  final DateTime? fechaRetorno;

  /// Costo en pesos (opcional, el supervisor puede no saberlo al
  /// recibir). Usado para reportes de costo por km.
  final double? costo;

  /// `null` mientras está en proceso. Setear al cerrar.
  final ResultadoRecapado? resultado;

  /// Texto libre — observaciones del proveedor o del supervisor.
  final String? notas;

  /// DNI del supervisor que envió la cubierta a recapar.
  final String enviadoPorDni;
  final String? enviadoPorNombre;

  /// DNI del supervisor que registró el cierre (`null` si en proceso).
  final String? cerradoPorDni;
  final String? cerradoPorNombre;

  const CubiertaRecapado({
    required this.id,
    required this.cubiertaId,
    required this.cubiertaCodigo,
    required this.vidaRecapado,
    required this.proveedor,
    required this.fechaEnvio,
    required this.fechaRetorno,
    required this.costo,
    required this.resultado,
    required this.notas,
    required this.enviadoPorDni,
    required this.enviadoPorNombre,
    required this.cerradoPorDni,
    required this.cerradoPorNombre,
  });

  bool get enProceso => fechaRetorno == null;

  /// Días que tardó el recapado. Si en proceso, contra ahora.
  int diasEnRecapado() {
    final fin = fechaRetorno ?? DateTime.now();
    return fin.difference(fechaEnvio).inDays;
  }

  factory CubiertaRecapado.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      CubiertaRecapado.fromMap(doc.id, doc.data());

  factory CubiertaRecapado.fromMap(String id, Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    return CubiertaRecapado(
      id: id,
      cubiertaId: (d['cubierta_id'] ?? '').toString(),
      cubiertaCodigo: (d['cubierta_codigo'] ?? '').toString(),
      vidaRecapado: (d['vida_recapado'] as num?)?.toInt() ?? 2,
      proveedor: (d['proveedor'] ?? '').toString(),
      fechaEnvio: (d['fecha_envio'] as Timestamp?)?.toDate() ?? DateTime.now(),
      fechaRetorno: (d['fecha_retorno'] as Timestamp?)?.toDate(),
      costo: (d['costo'] as num?)?.toDouble(),
      resultado: ResultadoRecapado.fromCodigo(d['resultado']?.toString()),
      notas: d['notas']?.toString(),
      enviadoPorDni: (d['enviado_por_dni'] ?? '').toString(),
      enviadoPorNombre: d['enviado_por_nombre']?.toString(),
      cerradoPorDni: d['cerrado_por_dni']?.toString(),
      cerradoPorNombre: d['cerrado_por_nombre']?.toString(),
    );
  }
}

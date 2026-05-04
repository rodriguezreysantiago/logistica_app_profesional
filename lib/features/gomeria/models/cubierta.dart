import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/posiciones.dart';

/// Cubierta individual — 1 doc por cubierta física en el inventario.
/// Cada cubierta tiene un `codigo` legible (CUB-XXXX) que la identifica
/// y se puede etiquetar físicamente con un sticker o QR.
class Cubierta {
  /// Doc id auto-generado por Firestore.
  final String id;

  /// Código legible para humanos (ej. "CUB-0042"). Único en el sistema,
  /// generado por contador en `META/cubiertas_counter`. Permite buscar
  /// rápido en la app y referenciar en planillas físicas.
  final String codigo;

  /// FK al doc en CUBIERTAS_MODELOS. Determina marca/modelo/medida/
  /// tipo_uso/km_esperado/recapable.
  final String modeloId;

  /// Snapshot del modelo al crear la cubierta. Permite mostrar
  /// "Bridgestone R268 295/80R22.5 — Tracción" sin join extra. Si la
  /// marca cambia de nombre o se borra, este snapshot lo preserva.
  final String modeloEtiqueta;

  /// Tipo de uso heredado del modelo. Replicado acá para queries
  /// rápidas ("dame todas las cubiertas TRACCION en depósito") sin
  /// join contra CUBIERTAS_MODELOS.
  final TipoUsoCubierta tipoUso;

  final EstadoCubierta estado;

  /// Cantidad de vidas que tuvo la cubierta. Arranca en 1 (nueva) y
  /// se incrementa con cada recapado RECIBIDA. Ej: 3 = ya tuvo 2
  /// recapados.
  final int vidas;

  /// Km acumulados desde que la cubierta entró al sistema (suma de
  /// todas sus instalaciones cerradas). Útil para reportes de
  /// duración total.
  final double kmAcumulados;

  /// Texto libre del operador (ej. "marca de pinchazo en lateral",
  /// "comprada en oferta de mayo 2026").
  final String? observaciones;

  /// Precio de compra de la cubierta nueva en pesos. Opcional — se
  /// captura al alta. Habilita el cálculo de costo por km
  /// (`precioCompra + Σ recapados.costo) / kmAcumulados`).
  final double? precioCompra;

  /// Cuándo se cargó la cubierta al sistema.
  final DateTime? creadoEn;

  const Cubierta({
    required this.id,
    required this.codigo,
    required this.modeloId,
    required this.modeloEtiqueta,
    required this.tipoUso,
    required this.estado,
    required this.vidas,
    required this.kmAcumulados,
    required this.observaciones,
    required this.precioCompra,
    required this.creadoEn,
  });

  /// `true` si esta cubierta puede mandarse a recapar AHORA. Solo
  /// EN_DEPOSITO porque el service rechaza cualquier otro estado — antes
  /// retornaba `true` también para INSTALADA y la UI ofrecía opciones
  /// que después fallaban al guardar. El service además valida
  /// `CUBIERTAS_MODELOS.recapable` antes de permitir el envío.
  bool get puedeRecaparse => estado == EstadoCubierta.enDeposito;

  factory Cubierta.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Cubierta.fromMap(doc.id, doc.data());

  // Equality por id — necesario para DropdownButtonFormField en los
  // diálogos de instalar / mandar a recapar (ver nota en CubiertaMarca).
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Cubierta && other.id == id;

  @override
  int get hashCode => id.hashCode;

  factory Cubierta.fromMap(String id, Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    return Cubierta(
      id: id,
      codigo: (d['codigo'] ?? '').toString(),
      modeloId: (d['modelo_id'] ?? '').toString(),
      modeloEtiqueta: (d['modelo_etiqueta'] ?? '').toString(),
      tipoUso: TipoUsoCubierta.fromCodigo(d['tipo_uso']?.toString()) ??
          TipoUsoCubierta.traccion,
      estado: EstadoCubierta.fromCodigo(d['estado']?.toString()) ??
          EstadoCubierta.enDeposito,
      vidas: (d['vidas'] as num?)?.toInt() ?? 1,
      kmAcumulados: (d['km_acumulados'] as num?)?.toDouble() ?? 0,
      observaciones: d['observaciones']?.toString(),
      precioCompra: (d['precio_compra'] as num?)?.toDouble(),
      creadoEn: (d['creado_en'] as Timestamp?)?.toDate(),
    );
  }
}

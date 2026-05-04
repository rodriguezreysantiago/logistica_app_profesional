import 'package:cloud_firestore/cloud_firestore.dart';

/// Proveedor de recapado. ABM desde la app por SUPERVISOR/ADMIN. Cada
/// proveedor que se usa en `CUBIERTAS_RECAPADOS.proveedor` tiene un
/// doc acá — evita que typos rompan los reportes ("Recauchutados Sur"
/// vs "RECAUCHUTADOS SUR" vs "Rec. Sur").
///
/// Soft-delete con `activo: false` — no eliminar para no romper
/// referencias de envíos históricos.
class CubiertaProveedor {
  final String id;
  final String nombre;
  final bool activo;

  const CubiertaProveedor({
    required this.id,
    required this.nombre,
    required this.activo,
  });

  factory CubiertaProveedor.fromDoc(
          DocumentSnapshot<Map<String, dynamic>> doc) =>
      CubiertaProveedor.fromMap(doc.id, doc.data());

  factory CubiertaProveedor.fromMap(String id, Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    return CubiertaProveedor(
      id: id,
      nombre: (d['nombre'] ?? '').toString(),
      activo: d['activo'] is bool ? d['activo'] as bool : true,
    );
  }

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'activo': activo,
      };

  // Equality por id — mismo motivo que CubiertaMarca: el dropdown de
  // proveedor en el dialog "Mandar a recapar" pierde la selección sin
  // esto cuando el StreamBuilder hace rebuild.
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CubiertaProveedor && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

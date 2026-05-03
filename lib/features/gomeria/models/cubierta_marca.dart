import 'package:cloud_firestore/cloud_firestore.dart';

/// Marca de cubierta. ABM desde la app por ADMIN. Soft-delete con
/// `activo: false` — no eliminar físicamente para no romper referencias
/// históricas en cubiertas ya cargadas con esa marca.
class CubiertaMarca {
  final String id;
  final String nombre;
  final bool activo;

  const CubiertaMarca({
    required this.id,
    required this.nombre,
    required this.activo,
  });

  factory CubiertaMarca.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      CubiertaMarca.fromMap(doc.id, doc.data());

  factory CubiertaMarca.fromMap(String id, Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    return CubiertaMarca(
      id: id,
      nombre: (d['nombre'] ?? '').toString(),
      activo: d['activo'] is bool ? d['activo'] as bool : true,
    );
  }

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'activo': activo,
      };

  // Equality por id — necesario para que los DropdownButtonFormField
  // mantengan la selección entre rebuilds del StreamBuilder. Sin esto,
  // cada snapshot del stream genera instancias nuevas y el dropdown
  // pierde la selección porque Dart compara por identidad por default.
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CubiertaMarca && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

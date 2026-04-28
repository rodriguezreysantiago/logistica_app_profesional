import 'package:cloud_firestore/cloud_firestore.dart';

/// Servicio de operaciones sobre la colección `EMPLEADOS`.
///
/// Centraliza las operaciones de lectura/escritura para el feature
/// de empleados. Las pantallas de admin usan estos métodos directamente
/// o vía componentes (`_Actualizar`).
class EmpleadoService {
  final FirebaseFirestore _db;

  EmpleadoService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  static const String _collection = 'EMPLEADOS';

  // ===========================================================================
  // ACTUALIZACIÓN DE CAMPOS
  // ===========================================================================

  /// Actualiza un único campo de un empleado.
  Future<void> actualizarCampo({
    required String dni,
    required String campo,
    required dynamic valor,
  }) async {
    try {
      await _db.collection(_collection).doc(dni).update({campo: valor});
    } catch (e) {
      throw Exception('Error al actualizar $campo: $e');
    }
  }

  /// Actualiza varios campos en una sola escritura.
  Future<void> actualizarCampos({
    required String dni,
    required Map<String, dynamic> data,
  }) async {
    await _db.collection(_collection).doc(dni).update(data);
  }

  // ===========================================================================
  // PAGINACIÓN
  // ===========================================================================

  /// Trae empleados paginados, ordenados por NOMBRE.
  /// Pasar [lastDocument] para traer la siguiente página.
  Future<QuerySnapshot> getPaginados({
    required int limit,
    DocumentSnapshot? lastDocument,
  }) async {
    Query query =
        _db.collection(_collection).orderBy('NOMBRE').limit(limit);

    if (lastDocument != null) {
      query = query.startAfterDocument(lastDocument);
    }

    return await query.get();
  }
}

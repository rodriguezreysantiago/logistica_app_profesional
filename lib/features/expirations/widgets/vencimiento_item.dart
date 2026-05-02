/// Modelo de un item de vencimiento para auditoría.
///
/// Representa un vencimiento puntual de un documento (RTO, Licencia, etc.)
/// asociado a un empleado o vehículo. Las pantallas de auditoría producen
/// listas de estos items y los renderizan con [VencimientoItemCard].
class VencimientoItem {
  /// ID del documento Firestore (DNI para EMPLEADOS, patente para VEHICULOS).
  final String docId;

  /// Colección Firestore: 'EMPLEADOS' o 'VEHICULOS'.
  final String coleccion;

  /// Texto principal de la card (ej: "JUAN PÉREZ" o "TRACTOR - AB123CD").
  final String titulo;

  /// Nombre legible del documento (ej: "Licencia", "RTO", "Seguro").
  final String tipoDoc;

  /// Sufijo del campo en Firestore. Se usa para construir
  /// `VENCIMIENTO_$campoBase` y `ARCHIVO_$campoBase`.
  /// Ej: "LICENCIA_DE_CONDUCIR", "RTO", "SEGURO".
  final String campoBase;

  /// Fecha de vencimiento como string (formato YYYY-MM-DD).
  final String fecha;

  /// Días restantes hasta el vencimiento.
  /// - Negativo: ya venció.
  /// - 0..N: faltan N días.
  /// - `null`: el campo en Firestore tenía un valor pero no se pudo
  ///   parsear (fecha corrupta). El item igual aparece en las
  ///   auditorías y se pinta como inválido para no silenciarlo.
  final int? dias;

  /// URL del archivo adjunto en Storage (si lo hay).
  final String? urlArchivo;

  /// Subcarpeta en Storage para subir el nuevo archivo.
  /// Ej: 'EMPLEADOS_DOCS' o 'VEHICULOS_DOCS'.
  final String storagePath;

  const VencimientoItem({
    required this.docId,
    required this.coleccion,
    required this.titulo,
    required this.tipoDoc,
    required this.campoBase,
    required this.fecha,
    required this.dias,
    required this.urlArchivo,
    required this.storagePath,
  });
}

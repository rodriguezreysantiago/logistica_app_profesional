import 'package:flutter/material.dart';

/// Definición de un vencimiento que se controla en un vehículo.
///
/// Cada [VencimientoSpec] mapea un control documental a sus dos campos
/// en Firestore: la fecha de vencimiento y la URL del archivo
/// (foto/PDF) que respalda esa fecha.
///
/// Mantener TODOS los vencimientos en `AppVencimientos` permite que
/// agregar uno nuevo (ej. "habilitación de cargas peligrosas") sea una
/// sola edición acá; las pantallas de admin/chofer iteran la lista y
/// generan tiles automáticamente.
class VencimientoSpec {
  /// Texto que se ve en la UI (ej. "RTO / VTV", "Extintor Cabina").
  final String etiqueta;

  /// Nombre del campo en Firestore donde se guarda la fecha. Convención:
  /// `VENCIMIENTO_<NOMBRE>`.
  final String campoFecha;

  /// Nombre del campo en Firestore donde se guarda la URL del archivo.
  /// Convención: `ARCHIVO_<NOMBRE>`. El sistema de revisiones depende
  /// de esta convención (replaceAll('VENCIMIENTO_', 'ARCHIVO_')).
  final String campoArchivo;

  /// Ícono que se muestra al lado de la etiqueta en algunos contextos.
  final IconData icono;

  const VencimientoSpec({
    required this.etiqueta,
    required this.campoFecha,
    required this.campoArchivo,
    required this.icono,
  });
}

class AppVencimientos {
  AppVencimientos._();

  /// Vencimientos que se controlan en cada TRACTOR/CHASIS.
  ///
  /// Para sumar uno nuevo (ej. matafuegos por carga, habilitación CNRT),
  /// agregar otro [VencimientoSpec] acá. Las pantallas de admin y chofer
  /// se actualizan solas.
  static const List<VencimientoSpec> tractor = [
    VencimientoSpec(
      etiqueta: 'RTO / VTV',
      campoFecha: 'VENCIMIENTO_RTO',
      campoArchivo: 'ARCHIVO_RTO',
      icono: Icons.assignment_turned_in,
    ),
    VencimientoSpec(
      etiqueta: 'Póliza Seguro',
      campoFecha: 'VENCIMIENTO_SEGURO',
      campoArchivo: 'ARCHIVO_SEGURO',
      icono: Icons.security,
    ),
    VencimientoSpec(
      etiqueta: 'Extintor Cabina',
      campoFecha: 'VENCIMIENTO_EXTINTOR_CABINA',
      campoArchivo: 'ARCHIVO_EXTINTOR_CABINA',
      icono: Icons.fire_extinguisher,
    ),
    VencimientoSpec(
      etiqueta: 'Extintor Exterior',
      campoFecha: 'VENCIMIENTO_EXTINTOR_EXTERIOR',
      campoArchivo: 'ARCHIVO_EXTINTOR_EXTERIOR',
      icono: Icons.fire_extinguisher,
    ),
  ];

  /// Vencimientos que se controlan en cada ENGANCHE
  /// (batea / tolva / bivuelco / tanque / acoplado).
  static const List<VencimientoSpec> enganche = [
    VencimientoSpec(
      etiqueta: 'RTO / VTV',
      campoFecha: 'VENCIMIENTO_RTO',
      campoArchivo: 'ARCHIVO_RTO',
      icono: Icons.assignment_turned_in,
    ),
    VencimientoSpec(
      etiqueta: 'Seguro',
      campoFecha: 'VENCIMIENTO_SEGURO',
      campoArchivo: 'ARCHIVO_SEGURO',
      icono: Icons.security,
    ),
  ];

  /// Devuelve la lista correspondiente al TIPO del vehículo.
  /// Si el tipo está vacío o no es reconocido, asume "enganche" (más
  /// chico) para no mostrar campos que no aplican.
  static List<VencimientoSpec> forTipo(String? tipo) {
    final t = (tipo ?? '').toUpperCase();
    if (t == 'TRACTOR' || t == 'CHASIS') return tractor;
    return enganche;
  }
}

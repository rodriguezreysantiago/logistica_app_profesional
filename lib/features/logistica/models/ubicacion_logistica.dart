import 'package:cloud_firestore/cloud_firestore.dart';

/// Punto físico de carga o descarga. Reusable entre tarifas.
///
/// `lat/lng` son opcionales — quedan disponibles para el futuro mapa
/// de planeamiento de viajes (cálculo de distancias, ETA, ruteo). No
/// se requieren para la operación actual.
class UbicacionLogistica {
  final String id;
  final String nombre;
  final String localidad;
  final String provincia;
  final String? direccion;
  final double? lat;
  final double? lng;
  final bool activa;
  final DateTime? creadoEn;
  final String? creadoPor;

  const UbicacionLogistica({
    required this.id,
    required this.nombre,
    required this.localidad,
    required this.provincia,
    this.direccion,
    this.lat,
    this.lng,
    this.activa = true,
    this.creadoEn,
    this.creadoPor,
  });

  /// Texto compuesto para mostrar como subtítulo / chip.
  /// Ejemplo: "Tres Arroyos, Buenos Aires" o "Tres Arroyos, Buenos
  /// Aires — Av. San Martín 123".
  String get etiquetaCompleta {
    final base = '$localidad, $provincia';
    if (direccion == null || direccion!.isEmpty) return base;
    return '$base — $direccion';
  }

  factory UbicacionLogistica.fromMap(String id, Map<String, dynamic> d) {
    return UbicacionLogistica(
      id: id,
      nombre: (d['nombre'] ?? '').toString(),
      localidad: (d['localidad'] ?? '').toString(),
      provincia: (d['provincia'] ?? '').toString(),
      direccion: (d['direccion'] as String?)?.trim().isEmpty ?? true
          ? null
          : (d['direccion'] as String).trim(),
      lat: (d['lat'] as num?)?.toDouble(),
      lng: (d['lng'] as num?)?.toDouble(),
      activa: d['activa'] != false,
      creadoEn: (d['creado_en'] as Timestamp?)?.toDate(),
      creadoPor: d['creado_por']?.toString(),
    );
  }

  factory UbicacionLogistica.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) =>
      UbicacionLogistica.fromMap(doc.id, doc.data());

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'localidad': localidad,
      'provincia': provincia,
      if (direccion != null) 'direccion': direccion,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      'activa': activa,
      if (creadoPor != null) 'creado_por': creadoPor,
    };
  }
}

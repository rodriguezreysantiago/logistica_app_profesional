import 'package:cloud_firestore/cloud_firestore.dart';

/// Punto físico de carga o descarga. Reusable entre tarifas.
///
/// `lat/lng` son opcionales — quedan disponibles para el futuro mapa
/// de planeamiento de viajes (cálculo de distancias, ETA, ruteo). No
/// se requieren para la operación actual.
///
/// `empresaIds` y `empresaNombres` (paralelos por índice) son la lista
/// de empresas que USAN esta ubicación física. Decisión Vecchi
/// 2026-05-08: la misma ubicación puede ser usada por varias empresas
/// (ej. Puerto de Quequén lo usan CARGILL, BUNGE y COFCO). NO es 1:1.
/// El query "ubicaciones de empresa X" usa `array-contains` sobre
/// `empresaIds`. `empresaNombres` se mantiene en paralelo como
/// snapshot — si renombran la empresa después, el snapshot queda
/// para referencia histórica.
///
/// Backwards compat: ubicaciones viejas con `empresa_id` (singular,
/// string) y `empresa_nombre` se leen al cargar y se meten en la
/// lista. Al actualizar via service se reescriben con el campo
/// nuevo. Si se editan, los campos viejos se borran.
///
/// Ubicaciones sin empresa siguen funcionando — aparecen "huérfanas"
/// en la lista, el operador puede asociar empresas desde la edición
/// inline.
class UbicacionLogistica {
  final String id;
  final String nombre;
  final String localidad;
  final String provincia;
  final String? direccion;
  final double? lat;
  final double? lng;
  final List<String> empresaIds;
  final List<String> empresaNombres;
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
    this.empresaIds = const [],
    this.empresaNombres = const [],
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

  /// Texto resumido de empresas asociadas. "PROFERTIL, CARGILL"
  /// o "PROFERTIL +2" si hay más de 3.
  String get etiquetaEmpresas {
    if (empresaNombres.isEmpty) return '';
    if (empresaNombres.length <= 3) return empresaNombres.join(' · ');
    return '${empresaNombres.take(2).join(' · ')} · +${empresaNombres.length - 2}';
  }

  factory UbicacionLogistica.fromMap(String id, Map<String, dynamic> d) {
    // Empresas: leer la lista nueva si existe, sino caer al campo
    // singular legacy. `empresa_ids` y `empresa_nombres` son listas
    // paralelas por índice — si el doc tiene mismatch (1 id pero 2
    // nombres), confiamos en `empresa_ids` y completamos nombres con
    // strings vacíos como fallback.
    final empresaIdsRaw = d['empresa_ids'];
    final empresaNombresRaw = d['empresa_nombres'];
    final List<String> empresaIds;
    final List<String> empresaNombres;
    if (empresaIdsRaw is List) {
      empresaIds = empresaIdsRaw
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      final nombres = (empresaNombresRaw is List)
          ? empresaNombresRaw.map((e) => e?.toString() ?? '').toList()
          : <String>[];
      empresaNombres = List.generate(
        empresaIds.length,
        (i) => i < nombres.length ? nombres[i] : '',
      );
    } else {
      // Legacy: campos singulares.
      final legacyId = (d['empresa_id'] as String?)?.trim();
      final legacyNombre = (d['empresa_nombre'] as String?)?.trim();
      if (legacyId != null && legacyId.isNotEmpty) {
        empresaIds = [legacyId];
        empresaNombres = [legacyNombre ?? ''];
      } else {
        empresaIds = const [];
        empresaNombres = const [];
      }
    }

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
      empresaIds: empresaIds,
      empresaNombres: empresaNombres,
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
      if (empresaIds.isNotEmpty) 'empresa_ids': empresaIds,
      if (empresaNombres.isNotEmpty) 'empresa_nombres': empresaNombres,
      'activa': activa,
      if (creadoPor != null) 'creado_por': creadoPor,
    };
  }
}

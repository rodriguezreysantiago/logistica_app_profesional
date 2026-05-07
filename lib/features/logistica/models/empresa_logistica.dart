import 'package:cloud_firestore/cloud_firestore.dart';

/// Tipo de empresa en el módulo Logística.
///
/// - [cliente]: empresa origen o destino del viaje (silo, planta,
///   puerto, fábrica). Paga el flete o lo recibe.
/// - [dadorTransporte]: otra empresa de transporte que tenía la carga
///   asignada y nos la cede. Cobra un % del flete (variable por carga).
enum TipoEmpresaLogistica {
  cliente('CLIENTE', 'Cliente'),
  dadorTransporte('DADOR_TRANSPORTE', 'Dador de transporte');

  final String codigo;
  final String etiqueta;
  const TipoEmpresaLogistica(this.codigo, this.etiqueta);

  static TipoEmpresaLogistica fromCodigo(String? codigo) {
    return TipoEmpresaLogistica.values.firstWhere(
      (t) => t.codigo == codigo,
      orElse: () => TipoEmpresaLogistica.cliente,
    );
  }
}

/// Empresa con la que Vecchi opera. Reusable: una misma empresa puede
/// figurar como origen, destino o dador en distintas tarifas.
class EmpresaLogistica {
  final String id;
  final String nombre;
  final TipoEmpresaLogistica tipo;
  final String? cuit;
  final String? contacto;
  final bool activa;
  final DateTime? creadoEn;
  final String? creadoPor;

  const EmpresaLogistica({
    required this.id,
    required this.nombre,
    required this.tipo,
    this.cuit,
    this.contacto,
    this.activa = true,
    this.creadoEn,
    this.creadoPor,
  });

  /// Construye una empresa desde el id + map de datos. Permite usar
  /// tanto el resultado de un stream (`QueryDocumentSnapshot`) como una
  /// lectura puntual (`DocumentSnapshot.data()`).
  factory EmpresaLogistica.fromMap(String id, Map<String, dynamic> d) {
    return EmpresaLogistica(
      id: id,
      nombre: (d['nombre'] ?? '').toString(),
      tipo: TipoEmpresaLogistica.fromCodigo(d['tipo']?.toString()),
      cuit: (d['cuit'] as String?)?.trim().isEmpty ?? true
          ? null
          : (d['cuit'] as String).trim(),
      contacto: (d['contacto'] as String?)?.trim().isEmpty ?? true
          ? null
          : (d['contacto'] as String).trim(),
      activa: d['activa'] != false,
      creadoEn: (d['creado_en'] as Timestamp?)?.toDate(),
      creadoPor: d['creado_por']?.toString(),
    );
  }

  factory EmpresaLogistica.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) =>
      EmpresaLogistica.fromMap(doc.id, doc.data());

  /// Map listo para `add()` o `set()`. Excluye `id` (lo gestiona
  /// Firestore) y `creado_en` (que se setea con `serverTimestamp`
  /// en el service).
  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'tipo': tipo.codigo,
      if (cuit != null) 'cuit': cuit,
      if (contacto != null) 'contacto': contacto,
      'activa': activa,
      if (creadoPor != null) 'creado_por': creadoPor,
    };
  }
}

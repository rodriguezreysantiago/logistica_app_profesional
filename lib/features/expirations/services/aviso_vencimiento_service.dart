import 'package:cloud_firestore/cloud_firestore.dart';

/// Registro de un aviso enviado por el admin al chofer (vía WhatsApp,
/// mail o lo que sumemos en el futuro).
///
/// Vive en la colección `AVISOS_VENCIMIENTOS` y queda como auditoría:
/// quién mandó qué, cuándo, por qué canal, con cuántos días de
/// anticipación. El editor de vencimientos lee esta colección para
/// mostrar el historial y evitar que el admin avise dos veces el mismo
/// día sin querer.
class AvisoVencimiento {
  /// ID del documento Firestore (autoincremental).
  final String id;

  /// Colección del destinatario: 'EMPLEADOS' o 'VEHICULOS'.
  final String destinatarioColeccion;

  /// DNI (si es chofer) o patente (si es vehículo).
  final String destinatarioId;

  /// Sufijo del campo (ej: 'LICENCIA_DE_CONDUCIR', 'RTO',
  /// 'EXTINTOR_CABINA'). Permite filtrar el historial al vencimiento
  /// puntual que se está editando.
  final String campoBase;

  /// Etiqueta legible del documento: 'Licencia', 'RTO', etc.
  final String tipoDoc;

  /// Canal usado: 'WHATSAPP' por ahora; en el futuro 'MAIL', 'PUSH'.
  final String canal;

  /// Cuándo se mandó el aviso.
  final DateTime enviadoEn;

  /// DNI y nombre del admin que disparó el aviso.
  final String enviadoPorDni;
  final String enviadoPorNombre;

  /// Días que faltaban para el vencimiento al momento de avisar
  /// (negativo si ya estaba vencido). Snapshot histórico — no se
  /// recalcula.
  final int diasRestantes;

  /// Texto literal que se mandó (auditoría).
  final String mensaje;

  const AvisoVencimiento({
    required this.id,
    required this.destinatarioColeccion,
    required this.destinatarioId,
    required this.campoBase,
    required this.tipoDoc,
    required this.canal,
    required this.enviadoEn,
    required this.enviadoPorDni,
    required this.enviadoPorNombre,
    required this.diasRestantes,
    required this.mensaje,
  });

  factory AvisoVencimiento.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final ts = data['enviado_en'];
    DateTime fecha;
    if (ts is Timestamp) {
      fecha = ts.toDate();
    } else if (ts is String) {
      fecha = DateTime.tryParse(ts) ?? DateTime.now();
    } else {
      fecha = DateTime.now();
    }
    return AvisoVencimiento(
      id: doc.id,
      destinatarioColeccion:
          (data['destinatario_coleccion'] ?? '').toString(),
      destinatarioId: (data['destinatario_id'] ?? '').toString(),
      campoBase: (data['campo_base'] ?? '').toString(),
      tipoDoc: (data['tipo_doc'] ?? '').toString(),
      canal: (data['canal'] ?? '').toString(),
      enviadoEn: fecha,
      enviadoPorDni: (data['enviado_por_dni'] ?? '').toString(),
      enviadoPorNombre: (data['enviado_por_nombre'] ?? '').toString(),
      diasRestantes: (data['dias_restantes'] is num)
          ? (data['dias_restantes'] as num).toInt()
          : 0,
      mensaje: (data['mensaje'] ?? '').toString(),
    );
  }
}

/// Servicio para grabar y consultar el historial de avisos enviados
/// desde la auditoría de vencimientos.
class AvisoVencimientoService {
  AvisoVencimientoService._();

  static const String _coleccion = 'AVISOS_VENCIMIENTOS';

  /// Registra un nuevo aviso enviado.
  static Future<void> registrar({
    required String destinatarioColeccion,
    required String destinatarioId,
    required String campoBase,
    required String tipoDoc,
    required String canal,
    required int diasRestantes,
    required String mensaje,
    required String adminDni,
    required String adminNombre,
  }) async {
    await FirebaseFirestore.instance.collection(_coleccion).add({
      'destinatario_coleccion': destinatarioColeccion,
      'destinatario_id': destinatarioId,
      'campo_base': campoBase,
      'tipo_doc': tipoDoc,
      'canal': canal,
      'enviado_en': FieldValue.serverTimestamp(),
      'enviado_por_dni': adminDni,
      'enviado_por_nombre': adminNombre,
      'dias_restantes': diasRestantes,
      'mensaje': mensaje,
    });
  }

  /// Stream del historial de avisos para un vencimiento puntual.
  /// Devuelve los más recientes primero.
  ///
  /// Filtra por (coleccion + docId + campoBase) para apuntar
  /// exactamente al vencimiento que se está editando — ej. la licencia
  /// del chofer 12345678, o el RTO de la patente AB123CD.
  ///
  /// **Importante**: el `orderBy` se hace en el cliente, no en
  /// Firestore. Si lo hiciéramos server-side junto con los 3 `where`
  /// de igualdad, Firestore exigiría crear un índice compuesto que el
  /// admin tendría que generar manualmente desde la consola la primera
  /// vez (con un click en el link de error). Para evitar esa fricción
  /// — la pantalla aparecía "vacía" hasta que se creara el índice —
  /// pedimos los docs sin orden y los ordenamos acá.
  static Stream<List<AvisoVencimiento>> streamHistorial({
    required String destinatarioColeccion,
    required String destinatarioId,
    required String campoBase,
    int limit = 10,
  }) {
    return FirebaseFirestore.instance
        .collection(_coleccion)
        .where('destinatario_coleccion', isEqualTo: destinatarioColeccion)
        .where('destinatario_id', isEqualTo: destinatarioId)
        .where('campo_base', isEqualTo: campoBase)
        .snapshots()
        .map((s) {
      final lista = s.docs.map(AvisoVencimiento.fromDoc).toList();
      // Ordenamos por fecha descendente en el cliente — el listado por
      // vencimiento puntual es chico (decenas de avisos como mucho),
      // no hay impacto de performance.
      lista.sort((a, b) => b.enviadoEn.compareTo(a.enviadoEn));
      // Aplicamos limit a mano porque ya no usamos .limit() de Firestore
      // (tampoco tendría sentido sin orderBy server-side).
      if (lista.length > limit) {
        return lista.sublist(0, limit);
      }
      return lista;
    });
  }
}

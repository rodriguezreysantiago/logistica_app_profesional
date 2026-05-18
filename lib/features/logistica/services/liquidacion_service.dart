import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../models/viaje.dart';

/// Service de la pantalla LIQUIDACIÓN. Provee:
///   - Stream de viajes del mes filtrables por empresa empleadora del
///     chofer (no por cliente del flete) + chofer.
///   - Acción de liquidar en bulk varios viajes de una pasada.
///
/// **Por qué no está en `ViajesService`**: este service razona en
/// términos de período + empresa empleadora — un dominio operativo
/// distinto al CRUD de viajes individual. Mantenerlos separados
/// permite que la pantalla de liquidación crezca (proyecciones,
/// exports a Excel, comparativos mes-a-mes) sin contaminar el modelo
/// transaccional del viaje.
///
/// **Resolución empresa empleadora del chofer**: el viaje guarda solo
/// `chofer_dni`. La empresa empleadora vive en `EMPLEADOS/{dni}.EMPRESA`
/// como string formato `'NOMBRE: (XX-XXXXXXXX-X)'`. Acá usamos
/// `AppEmpresasEmpleadoras.cuitDeStringEmpresa()` para extraer el
/// CUIT y agrupar por empresa.
class LiquidacionService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _viajes =>
      _db.collection(AppCollections.viajesLogistica);
  static CollectionReference<Map<String, dynamic>> get _empleados =>
      _db.collection(AppCollections.empleados);

  /// Stream de viajes activos en un rango de fechas, filtrados por
  /// `fecha_carga` (la fecha de evento real, no la de creación del
  /// doc). Si `fecha_carga` es null en algún doc, ese viaje no entra
  /// — los viajes sin carga registrada típicamente son CANCELADOS o
  /// recién creados, no son liquidables.
  ///
  /// El filtro por empresa empleadora del chofer se hace en cliente
  /// (requiere lookup a EMPLEADOS) — usar [streamEmpleadosPorEmpresa]
  /// para obtener la lista de DNIs y filtrar acá.
  ///
  /// Acepta un set opcional de [choferDnis] para filtrar solo viajes
  /// de esos choferes. Si es null o vacío, devuelve todos los viajes
  /// del rango (sin filtro de chofer).
  static Stream<List<Viaje>> streamViajesEnRango({
    required DateTime desde,
    required DateTime hasta,
    Set<String>? choferDnis,
  }) {
    // .where con índice (fecha_carga, activo) — agregado en
    // firestore.indexes.json si Firestore lo pide.
    Query<Map<String, dynamic>> q = _viajes
        .where('activo', isEqualTo: true)
        .where('fecha_carga', isGreaterThanOrEqualTo: Timestamp.fromDate(desde))
        .where('fecha_carga', isLessThan: Timestamp.fromDate(hasta));

    return q.snapshots().map((snap) {
      // Filtro defensivo (auditoria 2026-05-17): viajes legacy con
      // estado 'CANCELADO' o 'POSTERGADO' (estados removidos 2026-05-14)
      // tienen `activo: true` y siguen apareciendo. La factory
      // Viaje.fromCodigo los mapea silenciosamente a `planeado` y se
      // sumaban a la liquidacion. Filtramos por el campo raw ANTES de
      // construir el modelo para no incluirlos.
      var docs = snap.docs.where((d) {
        final estadoRaw = (d.data()['estado'] ?? '').toString();
        return estadoRaw != 'CANCELADO' && estadoRaw != 'POSTERGADO';
      }).toList();
      var viajes = docs.map((d) => Viaje.fromMap(d.id, d.data())).toList();
      if (choferDnis != null && choferDnis.isNotEmpty) {
        viajes = viajes.where((v) => choferDnis.contains(v.choferDni)).toList();
      }
      // Orden por fecha_carga ascendente (cronológico) para que la
      // tabla quede natural — Firestore lo devuelve sin orden garantizado.
      viajes.sort(
          (a, b) => (a.fechaCarga ?? desde).compareTo(b.fechaCarga ?? desde));
      return viajes;
    });
  }

  /// Stream de empleados activos (rol CHOFER) con su empresa
  /// empleadora resuelta a CUIT. Devuelve `Map<dni, EmpleadoMin>`.
  ///
  /// Útil para la pantalla LIQUIDACION:
  ///   1. Cargar el mapa una sola vez (al abrir).
  ///   2. Filtrar choferes por CUIT de empresa para alimentar el
  ///      dropdown de chofer.
  ///   3. Pasar los DNIs al [streamViajesEnRango] como filtro server-friendly.
  static Stream<Map<String, EmpleadoLiquidacion>> streamEmpleadosCache() {
    return _empleados
        .where('ROL', isEqualTo: 'CHOFER')
        .snapshots()
        .map((snap) {
      final out = <String, EmpleadoLiquidacion>{};
      for (final d in snap.docs) {
        final data = d.data();
        if (data['ACTIVO'] == false) continue;
        final dni = d.id;
        final nombre = (data['NOMBRE'] ?? '').toString();
        final empresaRaw = (data['EMPRESA'] ?? '').toString();
        final cuit = AppEmpresasEmpleadoras.cuitDeStringEmpresa(empresaRaw);
        out[dni] = EmpleadoLiquidacion(
          dni: dni,
          nombre: nombre,
          empresaCuit: cuit,
        );
      }
      return out;
    });
  }

  /// Marca múltiples viajes como liquidados en una sola transacción
  /// (batch). Si la cantidad supera 500 (límite de Firestore), parte
  /// en chunks.
  ///
  /// Devuelve la cantidad de viajes que se actualizaron exitosamente.
  static Future<int> marcarLiquidadosBulk({
    required List<String> viajeIds,
    required String liquidadoPorDni,
  }) async {
    if (viajeIds.isEmpty) return 0;
    var totalActualizados = 0;
    // Chunks de 500 — límite de operaciones por batch en Firestore.
    for (var i = 0; i < viajeIds.length; i += 500) {
      final chunk = viajeIds.sublist(
        i,
        (i + 500 > viajeIds.length) ? viajeIds.length : i + 500,
      );
      // Race-condition guard (auditoria 2026-05-18): pre-fetch cada doc
      // y solo actualizamos los que SIGUEN pendientes. Sin esto, dos
      // operadores que liquidan en paralelo PISAN `liquidado_en` y
      // `liquidado_por_dni` del primero → trazabilidad rota. La ventana
      // de race se reduce de "tamaño del batch" a "milisegundos entre
      // get y batch.commit". No usamos runTransaction porque la memoria
      // del proyecto prohibe transacciones client-side en Windows
      // (bugs cloud_firestore desktop).
      final pendientes = <String>[];
      for (final id in chunk) {
        final snap = await _viajes.doc(id).get();
        if (snap.exists && (snap.data()?['liquidado'] != true)) {
          pendientes.add(id);
        }
      }
      if (pendientes.isEmpty) continue;
      final batch = _db.batch();
      for (final id in pendientes) {
        batch.update(_viajes.doc(id), {
          'liquidado': true,
          'liquidado_en': FieldValue.serverTimestamp(),
          'liquidado_por_dni': liquidadoPorDni,
          'actualizado_en': FieldValue.serverTimestamp(),
          'actualizado_por_dni': liquidadoPorDni,
        });
      }
      await batch.commit();
      totalActualizados += pendientes.length;
    }
    return totalActualizados;
  }

  /// Inverso del bulk: desmarca múltiples viajes como NO liquidados.
  /// Útil si el operador se equivocó y necesita revertir una
  /// liquidación masiva.
  static Future<int> desmarcarLiquidadosBulk({
    required List<String> viajeIds,
    required String actualizadoPorDni,
  }) async {
    if (viajeIds.isEmpty) return 0;
    var totalActualizados = 0;
    for (var i = 0; i < viajeIds.length; i += 500) {
      final chunk = viajeIds.sublist(
        i,
        (i + 500 > viajeIds.length) ? viajeIds.length : i + 500,
      );
      // Mismo guard que marcarLiquidadosBulk pero al reves: solo
      // desmarcamos los que actualmente ESTAN liquidados — sin esto,
      // un doble click reescribiria `actualizado_en` sobre viajes
      // que ya estaban no-liquidados.
      final liquidados = <String>[];
      for (final id in chunk) {
        final snap = await _viajes.doc(id).get();
        if (snap.exists && (snap.data()?['liquidado'] == true)) {
          liquidados.add(id);
        }
      }
      if (liquidados.isEmpty) continue;
      final batch = _db.batch();
      for (final id in liquidados) {
        batch.update(_viajes.doc(id), {
          'liquidado': false,
          'liquidado_en': null,
          'liquidado_por_dni': null,
          'actualizado_en': FieldValue.serverTimestamp(),
          'actualizado_por_dni': actualizadoPorDni,
        });
      }
      await batch.commit();
      totalActualizados += liquidados.length;
    }
    return totalActualizados;
  }
}

/// Subset mínimo de un empleado que la pantalla LIQUIDACION necesita.
/// Mantener el shape chico evita rebuilds caros y deja explícito qué
/// info se usa: DNI, nombre y CUIT de empresa empleadora.
class EmpleadoLiquidacion {
  final String dni;
  final String nombre;
  final String? empresaCuit;

  const EmpleadoLiquidacion({
    required this.dni,
    required this.nombre,
    required this.empresaCuit,
  });
}

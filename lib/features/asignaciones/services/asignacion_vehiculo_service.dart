import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/audit_log_service.dart';
import '../models/asignacion_vehiculo.dart';

/// Único punto de entrada para cambiar la asignación chofer↔vehículo.
///
/// Antes de este servicio había dos flujos paralelos que escribían
/// directo a Firestore (`EmpleadoActions.unidad` desde la ficha del
/// admin y `RevisionService.finalizarRevision` cuando se aprobaba la
/// solicitud del chofer). Eso duplicaba código, NO loggeaba histórico
/// y tenía un mini-bug de inconsistencia de terminología
/// (ESTADO=`OCUPADO` vs ESTADO=`ASIGNADO`). Ahora ambos flujos
/// llaman a [cambiarAsignacion] y el log temporal queda automático.
///
/// **Modelo**: cada cambio cierra la asignación activa anterior
/// (`hasta = now`) y crea una nueva (`desde: now, hasta: null`). Así
/// se puede reconstruir quién manejó qué patente en cualquier momento
/// del pasado — útil para multas tardías, eventos Volvo y disputas.
class AsignacionVehiculoService {
  final FirebaseFirestore _db;

  AsignacionVehiculoService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  /// Convención del codebase: "sin asignar" se representa con `-`.
  /// Lo guardamos acá para no esparcir el string mágico.
  static const String _sinAsignar = '-';

  /// Estados del campo `VEHICULOS.ESTADO`.
  static const String _estadoOcupado = 'OCUPADO';
  static const String _estadoLibre = 'LIBRE';

  /// Cambia la asignación del [choferDni] a [nuevaPatente].
  ///
  /// - Si [nuevaPatente] es `null` o vacío o `-`, desvincula al chofer
  ///   (queda sin unidad). En ese caso libera la patente que tenía.
  /// - Si [nuevaPatente] ya tenía otro chofer activo, ese chofer queda
  ///   también desvinculado (cierra su asignación + limpia el espejo
  ///   `EMPLEADOS.{otro}.VEHICULO`). Esto resuelve un bug pre-existente
  ///   donde dos choferes podían terminar apuntando a la misma patente.
  /// - Si el chofer ya tenía esa misma patente (no-op), retorna sin
  ///   tocar nada.
  ///
  /// La operación corre dentro de una transaction para evitar race
  /// conditions con sincronizaciones simultáneas. El audit log
  /// (fire-and-forget) se dispara después.
  Future<void> cambiarAsignacion({
    required String choferDni,
    required String? nuevaPatente,
    required String asignadoPorDni,
    String? choferNombre,
    String? asignadoPorNombre,
    String? motivo,
  }) async {
    final dniLimpio = choferDni.trim();
    if (dniLimpio.isEmpty) {
      throw ArgumentError('choferDni vacío');
    }
    final asignadorLimpio = asignadoPorDni.trim();
    if (asignadorLimpio.isEmpty) {
      throw ArgumentError('asignadoPorDni vacío');
    }

    final patenteNorm = _normalizarPatente(nuevaPatente);
    final desvincular = patenteNorm == null;

    // Pre-lectura del doc del empleado para 2 cosas:
    //   1. Validar que sea CHOFER (admins/supervisores/planta no manejan).
    //      Solo aplica al ASIGNAR — desvincular siempre se permite, así
    //      podemos limpiar si quedó un dato sucio de antes de esta regla.
    //   2. Tomar el snapshot del nombre.
    final empSnap =
        await _db.collection(AppCollections.empleados).doc(dniLimpio).get();
    if (!empSnap.exists) {
      throw StateError('Empleado $dniLimpio no existe');
    }
    final empData = empSnap.data() ?? const <String, dynamic>{};
    if (!desvincular) {
      final rolCrudo = empData['ROL']?.toString() ?? '';
      final rolNorm = AppRoles.normalizar(rolCrudo);
      if (!AppRoles.tieneVehiculo(rolNorm)) {
        throw StateError(
          'No se puede asignar vehículo a $dniLimpio: tiene rol $rolNorm. '
          'Solo los empleados con rol CHOFER pueden tener unidad asignada.',
        );
      }
    }
    final choferNombreFinal =
        choferNombre ?? empData['NOMBRE']?.toString();
    final asignadoPorNombreFinal =
        asignadoPorNombre ?? await _leerNombreEmpleado(asignadorLimpio);

    // Snapshot que la transaction llena. Lo usamos después del commit
    // para escribir el audit log con la patente anterior real.
    String? patenteAnterior;

    await _db.runTransaction((tx) async {
      final colAsig = _db.collection(AppCollections.asignacionesVehiculo);

      // 1) Lecturas primero (Firestore exige reads antes de writes).
      final activaChoferQ = await colAsig
          .where('chofer_dni', isEqualTo: dniLimpio)
          .where('hasta', isNull: true)
          .limit(1)
          .get();

      QuerySnapshot<Map<String, dynamic>>? activaPatenteQ;
      if (!desvincular) {
        activaPatenteQ = await colAsig
            .where('vehiculo_id', isEqualTo: patenteNorm)
            .where('hasta', isNull: true)
            .limit(1)
            .get();
      }

      final activaChoferDoc =
          activaChoferQ.docs.isEmpty ? null : activaChoferQ.docs.first;
      final patenteActualChofer =
          activaChoferDoc?.data()['vehiculo_id']?.toString();
      patenteAnterior = patenteActualChofer;

      final activaPatenteDoc =
          (activaPatenteQ?.docs.isEmpty ?? true) ? null : activaPatenteQ!.docs.first;
      final choferActualPatente =
          activaPatenteDoc?.data()['chofer_dni']?.toString();

      // 2) No-ops: si el chofer ya tenía esa patente, o si pidieron
      // desvincular pero no había nada, salimos sin escribir.
      if (desvincular && activaChoferDoc == null) {
        return;
      }
      if (!desvincular &&
          patenteActualChofer == patenteNorm &&
          choferActualPatente == dniLimpio) {
        return;
      }

      final ahora = Timestamp.now();

      // 3) Cerrar asignación activa del chofer (si tenía).
      if (activaChoferDoc != null) {
        tx.update(activaChoferDoc.reference, {'hasta': ahora});
      }

      // 4) Cerrar asignación activa de la patente nueva (si la tenía
      // y NO es la misma asignación que la del chofer — caso raro pero
      // posible si el dato venía corrupto).
      if (activaPatenteDoc != null &&
          activaPatenteDoc.id != activaChoferDoc?.id) {
        tx.update(activaPatenteDoc.reference, {'hasta': ahora});
      }

      // 5) Crear la nueva asignación si corresponde.
      if (!desvincular) {
        final nuevaRef = colAsig.doc();
        tx.set(nuevaRef, <String, dynamic>{
          'vehiculo_id': patenteNorm,
          'chofer_dni': dniLimpio,
          'chofer_nombre': choferNombreFinal,
          'desde': ahora,
          'hasta': null,
          'asignado_por_dni': asignadorLimpio,
          'asignado_por_nombre': asignadoPorNombreFinal,
          if (motivo != null && motivo.trim().isNotEmpty)
            'motivo': motivo.trim(),
        });
      }

      // 6) Espejos en EMPLEADOS y VEHICULOS — el resto de la app sigue
      // leyendo de ahí, no se entera del cambio de fuente de verdad.
      tx.update(_db.collection(AppCollections.empleados).doc(dniLimpio), {
        'VEHICULO': desvincular ? _sinAsignar : patenteNorm,
      });

      if (!desvincular) {
        tx.update(_db.collection(AppCollections.vehiculos).doc(patenteNorm), {
          'ESTADO': _estadoOcupado,
        });
      }

      if (patenteActualChofer != null &&
          patenteActualChofer != _sinAsignar &&
          patenteActualChofer.isNotEmpty &&
          patenteActualChofer != patenteNorm) {
        tx.update(
          _db.collection(AppCollections.vehiculos).doc(patenteActualChofer),
          {'ESTADO': _estadoLibre},
        );
      }

      // 7) Cleanup del bug pre-existente: si la patente nueva tenía
      // otro chofer en EMPLEADOS, limpiamos su campo VEHICULO también.
      if (!desvincular &&
          choferActualPatente != null &&
          choferActualPatente != dniLimpio &&
          choferActualPatente.isNotEmpty) {
        tx.update(
          _db.collection(AppCollections.empleados).doc(choferActualPatente),
          {'VEHICULO': _sinAsignar},
        );
      }
    });

    // 8) Audit log fuera de la transaction (fire-and-forget).
    unawaited(AuditLog.registrar(
      accion: desvincular
          ? AuditAccion.desvincularEquipo
          : AuditAccion.asignarEquipo,
      entidad: AppCollections.empleados,
      entidadId: dniLimpio,
      detalles: {
        'campo': 'VEHICULO',
        'unidad_anterior': patenteAnterior ?? '',
        'unidad_nueva': patenteNorm ?? '',
        if (motivo != null && motivo.trim().isNotEmpty) 'motivo': motivo.trim(),
      },
    ));
  }

  /// Devuelve la asignación que estaba activa para [vehiculoId] en
  /// el instante [fecha]. Usar para atribuir eventos Volvo del pasado,
  /// multas tardías, etc.
  ///
  /// Devuelve `null` si en ese momento no había nadie asignado, o si
  /// el vehículo no existe.
  Future<AsignacionVehiculo?> obtenerChoferEnFecha({
    required String vehiculoId,
    required DateTime fecha,
  }) async {
    final patenteLimpia = vehiculoId.trim();
    if (patenteLimpia.isEmpty) return null;

    final fechaTs = Timestamp.fromDate(fecha);

    // Estrategia: arrancamos por la asignación con `desde` MÁS GRANDE
    // que sea ≤ fecha. Esa es la candidata. Después validamos que `hasta`
    // sea null o > fecha.
    final snap = await _db
        .collection(AppCollections.asignacionesVehiculo)
        .where('vehiculo_id', isEqualTo: patenteLimpia)
        .where('desde', isLessThanOrEqualTo: fechaTs)
        .orderBy('desde', descending: true)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    final candidata = AsignacionVehiculo.fromDoc(snap.docs.first);

    // Si la candidata ya estaba cerrada antes de la fecha, no hay match.
    if (candidata.hasta != null && !candidata.hasta!.isAfter(fecha)) {
      return null;
    }
    return candidata;
  }

  /// Stream del historial completo de [vehiculoId] (más recientes
  /// primero). [limit] por default 50, pensado para una pantalla con
  /// scroll razonable; subir si se necesita.
  Stream<List<AsignacionVehiculo>> streamHistorialPorVehiculo(
    String vehiculoId, {
    int limit = 50,
  }) {
    final patenteLimpia = vehiculoId.trim();
    if (patenteLimpia.isEmpty) {
      return Stream.value(const <AsignacionVehiculo>[]);
    }
    return _db
        .collection(AppCollections.asignacionesVehiculo)
        .where('vehiculo_id', isEqualTo: patenteLimpia)
        .orderBy('desde', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(AsignacionVehiculo.fromDoc).toList());
  }

  /// Stream del historial completo de [choferDni].
  Stream<List<AsignacionVehiculo>> streamHistorialPorChofer(
    String choferDni, {
    int limit = 50,
  }) {
    final dniLimpio = choferDni.trim();
    if (dniLimpio.isEmpty) {
      return Stream.value(const <AsignacionVehiculo>[]);
    }
    return _db
        .collection(AppCollections.asignacionesVehiculo)
        .where('chofer_dni', isEqualTo: dniLimpio)
        .orderBy('desde', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(AsignacionVehiculo.fromDoc).toList());
  }

  /// Normaliza la patente recibida: limpia espacios, devuelve null si
  /// está vacía o representa "sin asignar".
  static String? _normalizarPatente(String? raw) {
    if (raw == null) return null;
    final t = raw.trim();
    if (t.isEmpty || t == _sinAsignar) return null;
    return t.toUpperCase();
  }

  /// Lee `EMPLEADOS/{dni}.NOMBRE`. Devuelve `null` si no existe o
  /// si la lectura falla (es snapshot opcional, no bloquea el cambio).
  Future<String?> _leerNombreEmpleado(String dni) async {
    try {
      final snap =
          await _db.collection(AppCollections.empleados).doc(dni).get();
      return snap.data()?['NOMBRE']?.toString();
    } catch (_) {
      return null;
    }
  }
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/audit_log_service.dart';
import '../models/asignacion_vehiculo.dart';
import 'asignacion_enganche_service.dart';

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
  /// La operación corre como writes secuenciales (NO usa runTransaction).
  /// El plugin C++ de cloud_firestore en Windows desktop tiene un bug
  /// con runTransaction cuando se mezclan reads + tx.set + tx.update —
  /// dispara un abort() nativo del Visual C++ Runtime imposible de
  /// catchear desde Dart. Mismo patrón resuelto en Gomería 2026-05-04
  /// (ver `feedback_windows_cloud_firestore_bugs.md`).
  ///
  /// Trade-off vs versión transaccional: si una operación intermedia
  /// falla (red caída, rules), queda estado parcial. Lo asumimos:
  /// (a) probabilidad baja con un solo supervisor + red estable,
  /// (b) los logs siguen siendo la fuente de verdad,
  /// (c) un job de cleanup futuro puede reconciliar.
  ///
  /// Orden de writes diseñado para minimizar inconsistencia visible si
  /// algo falla: primero CREAR la nueva asignación, después CERRAR las
  /// viejas. Si crashea entremedio, hay momentáneamente 2 activas (la
  /// nueva + alguna vieja) pero no queda al chofer "sin asignación".
  ///
  /// El audit log (fire-and-forget) se dispara después.
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

    // === 1. Pre-lectura del empleado (validación + snapshot de nombre).
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
    final choferNombreFinal = choferNombre ?? empData['NOMBRE']?.toString();
    final asignadoPorNombreFinal =
        asignadoPorNombre ?? await _leerNombreEmpleado(asignadorLimpio);

    // === 2. Lecturas en paralelo: asignación activa del chofer + de la
    // patente nueva. Ambos `.get()` arrancan en paralelo al asignarse;
    // el segundo `await` no agrega latencia porque la request ya está
    // en vuelo.
    final colAsig = _db.collection(AppCollections.asignacionesVehiculo);
    final activaChoferQF = colAsig
        .where('chofer_dni', isEqualTo: dniLimpio)
        .where('hasta', isNull: true)
        .limit(1)
        .get();
    final activaPatenteQF = desvincular
        ? null
        : colAsig
            .where('vehiculo_id', isEqualTo: patenteNorm)
            .where('hasta', isNull: true)
            .limit(1)
            .get();

    final activaChoferQ = await activaChoferQF;
    final activaPatenteQ =
        activaPatenteQF == null ? null : await activaPatenteQF;

    final activaChoferDoc =
        activaChoferQ.docs.isEmpty ? null : activaChoferQ.docs.first;
    final patenteActualChofer =
        activaChoferDoc?.data()['vehiculo_id']?.toString();

    final activaPatenteDoc =
        (activaPatenteQ == null || activaPatenteQ.docs.isEmpty)
            ? null
            : activaPatenteQ.docs.first;
    final choferActualPatente =
        activaPatenteDoc?.data()['chofer_dni']?.toString();

    // === 3. No-ops.
    if (desvincular && activaChoferDoc == null) {
      return;
    }
    if (!desvincular &&
        patenteActualChofer == patenteNorm &&
        choferActualPatente == dniLimpio) {
      return;
    }

    final ahora = Timestamp.now();
    final patenteAnterior = patenteActualChofer;

    // === 4. CREAR primero la nueva asignación (si aplica) — writes
    // secuenciales en orden que minimiza ventana de inconsistencia.
    if (!desvincular) {
      final nuevaRef = colAsig.doc();
      await nuevaRef.set(<String, dynamic>{
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

    // === 5. Cerrar asignación activa del chofer (si tenía).
    if (activaChoferDoc != null) {
      await activaChoferDoc.reference.update({'hasta': ahora});
    }

    // === 6. Cerrar asignación de la patente nueva si la tenía OTRO chofer.
    if (activaPatenteDoc != null &&
        activaPatenteDoc.id != activaChoferDoc?.id) {
      await activaPatenteDoc.reference.update({'hasta': ahora});
    }

    // === 7. Espejos en EMPLEADOS y VEHICULOS — best-effort. Si alguno
    // falla, logueamos y seguimos: el log temporal de ASIGNACIONES_*
    // ya quedó correcto, los espejos pueden reconciliarse después.
    final empleadoRef =
        _db.collection(AppCollections.empleados).doc(dniLimpio);
    try {
      await empleadoRef.update(
        {'VEHICULO': desvincular ? _sinAsignar : patenteNorm},
      );
    } catch (e) {
      // ignore: avoid_print
      print('Aviso: update espejo EMPLEADOS.$dniLimpio.VEHICULO falló: $e');
    }

    if (!desvincular) {
      try {
        await _db
            .collection(AppCollections.vehiculos)
            .doc(patenteNorm)
            .update({'ESTADO': _estadoOcupado});
      } catch (e) {
        // ignore: avoid_print
        print('Aviso: update espejo VEHICULOS.$patenteNorm.ESTADO falló: $e');
      }
    }

    if (patenteActualChofer != null &&
        patenteActualChofer != _sinAsignar &&
        patenteActualChofer.isNotEmpty &&
        patenteActualChofer != patenteNorm) {
      try {
        await _db
            .collection(AppCollections.vehiculos)
            .doc(patenteActualChofer)
            .update({'ESTADO': _estadoLibre});
      } catch (e) {
        // ignore: avoid_print
        print(
          'Aviso: liberar VEHICULOS.$patenteActualChofer.ESTADO falló: $e',
        );
      }
    }

    // === 8. Cleanup: si la patente nueva tenía otro chofer en EMPLEADOS,
    // limpiarle su campo VEHICULO.
    if (!desvincular &&
        choferActualPatente != null &&
        choferActualPatente != dniLimpio &&
        choferActualPatente.isNotEmpty) {
      try {
        await _db
            .collection(AppCollections.empleados)
            .doc(choferActualPatente)
            .update({'VEHICULO': _sinAsignar});
      } catch (e) {
        // ignore: avoid_print
        print(
          'Aviso: limpiar EMPLEADOS.$choferActualPatente.VEHICULO falló: $e',
        );
      }
    }

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

    // 9) Cascade: si el chofer tenía un enganche, hay que reasignarlo
    // al nuevo tractor (Fase 0 Gomería 2026-05-04). Sin esto, el log
    // de ASIGNACIONES_ENGANCHE quedaría desfasado: el enganche dice
    // estar en el tractor viejo cuando físicamente está en el nuevo.
    //
    // Si desvinculamos al chofer (le sacamos el tractor), el enganche
    // se desengancha también. El campo EMPLEADOS.ENGANCHE en el
    // espejo NO se modifica acá — el chofer puede mantener su enganche
    // "asignado" al volver a tomar otro tractor.
    try {
      final engancheActual = (empData['ENGANCHE'] ?? '').toString().trim();
      final tieneEnganche =
          engancheActual.isNotEmpty && engancheActual != _sinAsignar;
      if (tieneEnganche) {
        await AsignacionEngancheService(firestore: _db).cambiarAsignacion(
          engancheId: engancheActual,
          nuevoTractorId: patenteNorm,
          asignadoPorDni: asignadorLimpio,
          asignadoPorNombre: asignadoPorNombreFinal,
          motivo: motivo != null && motivo.trim().isNotEmpty
              ? '${motivo.trim()} (cascade tractor change)'
              : 'Cascade: cambio de tractor del chofer',
        );
      }
    } catch (e) {
      // No bloqueamos el cambio de tractor por un fallo del cascade.
      // El log temporal puede repararse manualmente si hace falta.
      // ignore: avoid_print
      print('Aviso: cascade ASIGNACIONES_ENGANCHE falló (no bloquea): $e');
    }
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

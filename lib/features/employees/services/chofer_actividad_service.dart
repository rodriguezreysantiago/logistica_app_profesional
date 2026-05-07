import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../../eco_driving/utils/etiquetas_alerta_volvo.dart';
import '../../fleet_map/services/sitrack_snapshot_service.dart';

/// Resumen agregado de la actividad de un chofer en una ventana de tiempo.
///
/// La fuente de los km manejados son las ASIGNACIONES_VEHICULO con
/// snapshots de odómetro Sitrack (Fase 2 Sitrack). Las asignaciones
/// previas a esa fase no tienen `odometer_inicial`/`odometer_final`
/// y se cuentan en `asignacionesSinTelemetria`.
///
/// Los eventos Volvo se cuentan filtrando VOLVO_ALERTAS por
/// `chofer_dni` (snapshot que pone el `volvoAlertasPoller` con el
/// chofer asignado en el momento del evento).
class ChoferActividadResumen {
  /// Ventana en días que cubre este resumen.
  final int dias;

  /// DNI del chofer.
  final String dni;

  /// Suma de km manejados en el período (de asignaciones cerradas y
  /// activas para las que se pudo computar). 0 si no hay datos.
  final double kmTotales;

  /// Total de asignaciones que solapan con la ventana.
  final int asignaciones;

  /// Asignaciones del período que NO tenían `odometer_inicial` o
  /// `odometer_final` cargados (legacy pre-Fase 2 Sitrack). El admin
  /// las puede mostrar como "datos parciales".
  final int asignacionesSinTelemetria;

  /// Tractores que el chofer manejó en el período, con sus km.
  final List<TractorUsado> tractores;

  /// Cuenta de eventos Volvo por severidad (HIGH, MEDIUM, LOW).
  final Map<String, int> eventosPorSeveridad;

  /// Cuenta de eventos Volvo por tipo (OVERSPEED, IDLING, etc.).
  /// Pre-ordenado descendente por cantidad para que el caller pueda
  /// tomar los primeros N sin reordenar.
  final List<EventoTipoConteo> eventosPorTipo;

  /// Total de eventos Volvo en el período (sum de severidades).
  int get totalEventos =>
      eventosPorSeveridad.values.fold<int>(0, (a, b) => a + b);

  const ChoferActividadResumen({
    required this.dias,
    required this.dni,
    required this.kmTotales,
    required this.asignaciones,
    required this.asignacionesSinTelemetria,
    required this.tractores,
    required this.eventosPorSeveridad,
    required this.eventosPorTipo,
  });

  static ChoferActividadResumen empty(String dni, int dias) =>
      ChoferActividadResumen(
        dias: dias,
        dni: dni,
        kmTotales: 0,
        asignaciones: 0,
        asignacionesSinTelemetria: 0,
        tractores: const [],
        eventosPorSeveridad: const {},
        eventosPorTipo: const [],
      );
}

class TractorUsado {
  final String patente;

  /// Km computados en el período. `null` si no se pudieron calcular
  /// (ej. asignación legacy sin baseline de odómetro Sitrack).
  final double? kmEnPeriodo;

  /// True si la última asignación del chofer en este tractor sigue
  /// activa (`hasta == null`).
  final bool activaActual;

  /// True si el km del período es parcial — vino de odometer_inicial
  /// más una lectura actual de Sitrack (asignación todavía abierta) en
  /// lugar de odometer_final cerrado. Útil para que la UI muestre un
  /// asterisco/leyenda "en curso".
  final bool esParcial;

  const TractorUsado({
    required this.patente,
    required this.kmEnPeriodo,
    required this.activaActual,
    this.esParcial = false,
  });
}

class EventoTipoConteo {
  final String tipo; // ej. "OVERSPEED"
  final int cantidad;

  const EventoTipoConteo({required this.tipo, required this.cantidad});
}

/// Calcula el resumen de actividad del chofer.
///
/// Para mantener el costo de lectura acotado, hace 2 queries totales:
/// una a ASIGNACIONES_VEHICULO y otra a VOLVO_ALERTAS, ambas filtradas
/// por `chofer_dni` y por la ventana temporal. La pantalla lo invoca
/// una vez por cada cambio de ventana (7/30/90).
class ChoferActividadService {
  final FirebaseFirestore _db;

  ChoferActividadService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  Future<ChoferActividadResumen> resumen({
    required String dni,
    int dias = 30,
  }) async {
    final dniLimpio = dni.trim();
    if (dniLimpio.isEmpty) {
      return ChoferActividadResumen.empty(dni, dias);
    }

    final ahora = DateTime.now();
    final cutoff = ahora.subtract(Duration(days: dias));
    final cutoffTs = Timestamp.fromDate(cutoff);

    // Lecturas en paralelo: asignaciones del chofer en el período +
    // eventos Volvo del chofer en el período.
    final asignFuture = _db
        .collection(AppCollections.asignacionesVehiculo)
        .where('chofer_dni', isEqualTo: dniLimpio)
        // Asignaciones cuyo `desde` esté en la ventana. Las que
        // empezaron antes pero siguen activas las traemos en una
        // segunda query simple (chofer_dni + hasta == null) y luego
        // filtramos client-side las que arrancaron antes del cutoff.
        // Esto evita un índice compuesto (chofer + hasta + desde).
        .where('desde', isGreaterThanOrEqualTo: cutoffTs)
        .get();

    final asignActivasFuture = _db
        .collection(AppCollections.asignacionesVehiculo)
        .where('chofer_dni', isEqualTo: dniLimpio)
        .where('hasta', isNull: true)
        .get();

    final eventosFuture = _db
        .collection(AppCollections.volvoAlertas)
        .where('chofer_dni', isEqualTo: dniLimpio)
        .where('creado_en', isGreaterThanOrEqualTo: cutoffTs)
        .get();

    final results = await Future.wait([
      asignFuture,
      asignActivasFuture,
      eventosFuture,
    ]);
    final asignSnap = results[0];
    final asignActivasSnap = results[1];
    final eventosSnap = results[2];

    // Consolidar todas las asignaciones (algunas pueden duplicarse
    // entre las dos queries — usamos doc.id como dedupe natural).
    // De las activas, solo nos interesan las que arrancaron ANTES
    // del cutoff (las que arrancaron después ya vienen en la 1ra query).
    final asignacionesPorId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final d in asignSnap.docs) {
      asignacionesPorId[d.id] = d;
    }
    for (final d in asignActivasSnap.docs) {
      asignacionesPorId[d.id] = d;
    }

    // Computar km y aglutinar tractores. Para cada asignación:
    //   - Cerrada con telemetría completa: km = odoFin - odoIni.
    //   - Cerrada legacy sin telemetría: tractor visible, km null,
    //     suma a `sinTelemetria`.
    //   - Activa con odoIni: lookup current odometer en SITRACK_POSICIONES
    //     y computa km parcial (odoCurrent - odoIni). Marca esParcial.
    //   - Activa sin odoIni: tractor visible, km null, suma a
    //     `sinTelemetria`.
    int sinTelemetria = 0;
    // Map de patente → {km computados (puede ser parcial), esActual,
    // esParcial}. Multiple asignaciones para la misma patente en el
    // período se suman.
    final kmPorTractor = <String, double>{};
    final tieneAlgunaTelemetriaPorTractor = <String, bool>{};
    final ultimaActivaPorTractor = <String, bool>{};
    final esParcialPorTractor = <String, bool>{};

    final snapSvc = SitrackSnapshotService(firestore: _db);

    for (final d in asignacionesPorId.values) {
      final data = d.data();
      final patente =
          (data['vehiculo_id'] ?? '').toString().trim().toUpperCase();
      if (patente.isEmpty) continue;
      final odoIni = (data['odometer_inicial'] as num?)?.toDouble();
      final odoFin = (data['odometer_final'] as num?)?.toDouble();
      final estaActiva = data['hasta'] == null;

      if (estaActiva) {
        ultimaActivaPorTractor[patente] = true;
      }

      // Cerrada con telemetría completa.
      if (!estaActiva && odoIni != null && odoFin != null) {
        final diff = odoFin - odoIni;
        if (diff > 0) {
          kmPorTractor.update(patente, (v) => v + diff, ifAbsent: () => diff);
          tieneAlgunaTelemetriaPorTractor[patente] = true;
        }
        continue;
      }

      // Activa con baseline → intentar lookup actual desde Sitrack.
      if (estaActiva && odoIni != null) {
        final snap = await snapSvc.obtener(patente);
        if (snap.odometer != null) {
          final diff = snap.odometer! - odoIni;
          if (diff > 0) {
            kmPorTractor.update(
              patente,
              (v) => v + diff,
              ifAbsent: () => diff,
            );
            tieneAlgunaTelemetriaPorTractor[patente] = true;
            esParcialPorTractor[patente] = true;
            continue;
          }
        }
        // Si Sitrack no devolvió odómetro, cae al "sin telemetría".
      }

      // Sin datos suficientes — pero igualmente registramos la patente
      // (para que aparezca en el listado) y sumamos al contador.
      sinTelemetria++;
      // Asegurar que el tractor figure en el listado aún sin km.
      kmPorTractor.putIfAbsent(patente, () => 0);
    }

    // Construir lista de TractorUsado. Si un tractor solo tuvo
    // asignaciones sin telemetría (entry creada por putIfAbsent con
    // valor 0), kmEnPeriodo queda null para que la UI muestre "—".
    final tractores = kmPorTractor.entries.map((e) {
      final tieneTele = tieneAlgunaTelemetriaPorTractor[e.key] ?? false;
      return TractorUsado(
        patente: e.key,
        kmEnPeriodo: tieneTele ? e.value : null,
        activaActual: ultimaActivaPorTractor[e.key] ?? false,
        esParcial: esParcialPorTractor[e.key] ?? false,
      );
    }).toList();
    // Orden: primero los que tienen km (mayor a menor), después los
    // sin telemetría (alfabéticamente por patente).
    tractores.sort((a, b) {
      final kmA = a.kmEnPeriodo;
      final kmB = b.kmEnPeriodo;
      if (kmA == null && kmB == null) return a.patente.compareTo(b.patente);
      if (kmA == null) return 1;
      if (kmB == null) return -1;
      return kmB.compareTo(kmA);
    });

    final kmTotales = kmPorTractor.entries
        .where((e) => tieneAlgunaTelemetriaPorTractor[e.key] ?? false)
        .fold<double>(0.0, (a, e) => a + e.value);

    // Eventos por severidad y tipo.
    // Para los eventos `GENERIC`, agrupamos por el SUBTIPO real
    // (SEATBELT, TELL_TALE, etc.) en lugar de pilarlos todos como
    // "GENERIC" — así la lista "Por tipo" muestra el detalle útil.
    final eventosPorSeveridad = <String, int>{};
    final eventosPorTipoMap = <String, int>{};
    for (final d in eventosSnap.docs) {
      final data = d.data();
      final sev = (data['severidad'] ?? '').toString().toUpperCase();
      final tipo = tipoAlertaVolvoFromDoc(data);
      if (sev.isNotEmpty) {
        eventosPorSeveridad.update(sev, (v) => v + 1, ifAbsent: () => 1);
      }
      if (tipo.isNotEmpty) {
        eventosPorTipoMap.update(tipo, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    final eventosPorTipo = eventosPorTipoMap.entries
        .map((e) => EventoTipoConteo(tipo: e.key, cantidad: e.value))
        .toList()
      ..sort((a, b) => b.cantidad.compareTo(a.cantidad));

    return ChoferActividadResumen(
      dias: dias,
      dni: dniLimpio,
      kmTotales: kmTotales,
      asignaciones: asignacionesPorId.length,
      asignacionesSinTelemetria: sinTelemetria,
      tractores: tractores,
      eventosPorSeveridad: eventosPorSeveridad,
      eventosPorTipo: eventosPorTipo,
    );
  }
}

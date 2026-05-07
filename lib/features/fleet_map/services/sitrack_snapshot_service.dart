import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';

/// Snapshot resuelto del último estado conocido de un tractor en Sitrack.
///
/// Se construye leyendo `SITRACK_POSICIONES/{patente}` que el cron
/// `sitrackPosicionPoller` mantiene actualizado cada 5 min. Si el doc no
/// existe (patente nunca reportó), o el odómetro no está cargado en el
/// último reporte (raro pero posible), los campos vienen `null`.
class SitrackSnapshot {
  /// Odómetro total del tractor en kilómetros (de la ECU si tiene ICAN,
  /// sino calculado por GPS). Null si no se pudo leer.
  final double? odometer;

  /// Timestamp del reporte que trajo este odómetro. Null si no se pudo
  /// leer. Útil para que el caller decida si el snapshot es lo
  /// "suficientemente fresco" — ej. si el último reporte es de hace 6h
  /// el odómetro puede haber subido en ese tiempo si el chofer manejó.
  final DateTime? reportDate;

  const SitrackSnapshot({this.odometer, this.reportDate});

  bool get isEmpty => odometer == null;
  bool get isNotEmpty => odometer != null;

  static const SitrackSnapshot empty = SitrackSnapshot();
}

/// Servicio de lectura del último snapshot Sitrack para una patente.
///
/// Diseñado para ser invocado desde otros services (asignaciones,
/// gomería) ANTES de persistir un evento que necesita el km del tractor
/// (alta/cierre de asignación, instalación/retiro de cubierta, etc).
///
/// **Best-effort**: si la lectura falla por red, rules o el doc no
/// existe, devuelve `SitrackSnapshot.empty` en lugar de tirar excepción.
/// El caller decide qué hacer con la ausencia (típicamente: persiste el
/// evento sin el campo de odómetro, no es un blocker).
class SitrackSnapshotService {
  final FirebaseFirestore _db;

  SitrackSnapshotService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  /// Devuelve el último odómetro conocido para [patente] o
  /// `SitrackSnapshot.empty` si no hay datos disponibles.
  ///
  /// Nunca tira excepción — la integración con asignaciones/gomería
  /// no debe fallar porque Sitrack no contestó. La trazabilidad se
  /// mantiene en `report_date` del doc devuelto: si hace 6h que no
  /// reporta, el caller puede decidir si igual usa el valor o no.
  Future<SitrackSnapshot> obtener(String patente) async {
    final p = patente.trim().toUpperCase();
    if (p.isEmpty || p == '-') return SitrackSnapshot.empty;

    try {
      final snap = await _db
          .collection(AppCollections.sitrackPosiciones)
          .doc(p)
          .get();
      if (!snap.exists) return SitrackSnapshot.empty;

      final data = snap.data() ?? const <String, dynamic>{};
      final odometer = (data['odometer'] as num?)?.toDouble();
      final ts = (data['report_date'] as Timestamp?)?.toDate();

      return SitrackSnapshot(
        odometer: odometer,
        reportDate: ts,
      );
    } catch (_) {
      // Best-effort: cualquier error → snapshot vacío. El caller persiste
      // sin odómetro y la app sigue funcionando.
      return SitrackSnapshot.empty;
    }
  }
}

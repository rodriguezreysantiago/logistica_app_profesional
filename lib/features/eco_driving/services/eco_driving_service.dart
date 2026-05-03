import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../models/volvo_score_diario.dart';

/// Lecturas sobre `VOLVO_SCORES_DIARIOS`.
///
/// Las escrituras pasan exclusivamente por la scheduled function
/// `volvoScoresPoller` (Admin SDK, bypass de rules). El cliente solo lee.
class EcoDrivingService {
  final FirebaseFirestore _db;

  EcoDrivingService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(AppCollections.volvoScoresDiarios);

  /// Stream del score diario de la flota desde [desde] hasta hoy,
  /// ordenado por fecha descendente.
  Stream<List<VolvoScoreDiario>> streamFleetEntreFechas({
    required DateTime desde,
    required DateTime hasta,
  }) {
    return _col
        .where('es_fleet', isEqualTo: true)
        .where('fecha_ts', isGreaterThanOrEqualTo: Timestamp.fromDate(desde))
        .where('fecha_ts', isLessThanOrEqualTo: Timestamp.fromDate(hasta))
        .orderBy('fecha_ts', descending: true)
        .snapshots()
        .map((s) => s.docs.map(VolvoScoreDiario.fromDoc).toList());
  }

  /// Stream de scores diarios POR VEHÍCULO en el rango. Devuelve un doc
  /// por (patente, día). La pantalla agrupa en memoria por patente para
  /// armar el ranking promedio.
  Stream<List<VolvoScoreDiario>> streamPorVehiculoEntreFechas({
    required DateTime desde,
    required DateTime hasta,
  }) {
    return _col
        .where('es_fleet', isEqualTo: false)
        .where('fecha_ts', isGreaterThanOrEqualTo: Timestamp.fromDate(desde))
        .where('fecha_ts', isLessThanOrEqualTo: Timestamp.fromDate(hasta))
        .orderBy('fecha_ts', descending: true)
        .snapshots()
        .map((s) => s.docs.map(VolvoScoreDiario.fromDoc).toList());
  }

  /// Stream del histórico diario de UN vehículo concreto. Usar para el
  /// drill-down (gráfico de evolución del score).
  Stream<List<VolvoScoreDiario>> streamHistorialPorPatente(
    String patente, {
    required DateTime desde,
    required DateTime hasta,
  }) {
    final p = patente.trim().toUpperCase();
    return _col
        .where('patente', isEqualTo: p)
        .where('fecha_ts', isGreaterThanOrEqualTo: Timestamp.fromDate(desde))
        .where('fecha_ts', isLessThanOrEqualTo: Timestamp.fromDate(hasta))
        .orderBy('fecha_ts', descending: true)
        .snapshots()
        .map((s) => s.docs.map(VolvoScoreDiario.fromDoc).toList());
  }
}

/// Agregación en memoria del ranking por vehículo.
///
/// La API entrega scores DIARIOS, así que para mostrar "score promedio
/// del último mes por vehículo" agrupamos los docs por patente y
/// promediamos el `total` y los días con data.
class RankingVehiculo {
  final String patente;
  final double scorePromedio;
  final int diasConData;
  final double? kmTotalesEnRango;
  final double? consumoPromedioLPor100Km;

  const RankingVehiculo({
    required this.patente,
    required this.scorePromedio,
    required this.diasConData,
    required this.kmTotalesEnRango,
    required this.consumoPromedioLPor100Km,
  });

  /// Color suave para el badge: <60 rojo, 60-80 amarillo, >=80 verde.
  /// La UI lee este getter para no duplicar la lógica en widgets.
  static String severidad(double score) {
    if (score < 60) return 'mal';
    if (score < 80) return 'medio';
    return 'bien';
  }

  /// Construye el ranking a partir de los docs diarios.
  static List<RankingVehiculo> desdeDocs(List<VolvoScoreDiario> docs) {
    final agg = <String, _AggAcum>{};
    for (final d in docs) {
      final p = d.patente;
      final score = d.scoreTotal;
      if (p == null || score == null) continue;
      final a = agg.putIfAbsent(p, _AggAcum.new);
      a.sumScore += score;
      a.dias++;
      final km = d.totalDistanceKm;
      if (km != null) a.sumKm += km;
      final lph = d.fuelLPor100Km;
      if (lph != null) {
        a.sumConsumo += lph;
        a.diasConsumo++;
      }
    }
    final out = agg.entries.map((e) {
      final a = e.value;
      return RankingVehiculo(
        patente: e.key,
        scorePromedio: a.dias > 0 ? a.sumScore / a.dias : 0,
        diasConData: a.dias,
        kmTotalesEnRango: a.sumKm > 0 ? a.sumKm : null,
        consumoPromedioLPor100Km:
            a.diasConsumo > 0 ? a.sumConsumo / a.diasConsumo : null,
      );
    }).toList();
    out.sort((a, b) => b.scorePromedio.compareTo(a.scorePromedio));
    return out;
  }
}

class _AggAcum {
  double sumScore = 0;
  int dias = 0;
  double sumKm = 0;
  double sumConsumo = 0;
  int diasConsumo = 0;
}

// Servicio que arma los KPIs del módulo Vista Ejecutiva.
//
// Filosofía: reusar al máximo la data ya pre-calculada por crons
// (STATS/dashboard cada 5 min + ICM_SEMANAL/{id} semanal). Solo lo que
// no esté pre-agregado se queryea on-the-fly (con limit para mantener
// los reads controlados).
//
// Sin caching propio — el StreamBuilder/FutureBuilder del lado UI
// se encarga del refresh. Si en el futuro abrimos la pantalla muy
// seguido conviene memoizar el último snapshot por unos minutos.

import 'package:cloud_firestore/cloud_firestore.dart';

/// Snapshot completo de KPIs para la Vista Ejecutiva. Se carga 1 vez
/// y se renderiza en pantalla; refresh manual pull-to-refresh.
class KpisVistaEjecutiva {
  final KpiMes viajesDelMes;
  final KpiIcm icmFlota;
  final KpiSimple choferesActivos;
  final KpiSimple alertasCriticas;

  /// Línea ICM últimas 12 semanas (label + valor).
  /// Orden cronológico ascendente.
  final List<PuntoTendencia> tendenciaIcm;

  /// Barras viajes últimas 8 semanas (label + valor).
  /// Orden cronológico ascendente.
  final List<PuntoTendencia> viajesPorSemana;

  /// Top 5 mejores choferes por ICM de la última semana cerrada.
  final List<ChoferRankingItem> top5Mejores;

  /// Top 5 a mejorar (peores ICM) de la última semana cerrada.
  final List<ChoferRankingItem> top5Peores;

  const KpisVistaEjecutiva({
    required this.viajesDelMes,
    required this.icmFlota,
    required this.choferesActivos,
    required this.alertasCriticas,
    required this.tendenciaIcm,
    required this.viajesPorSemana,
    required this.top5Mejores,
    required this.top5Peores,
  });
}

/// KPI con valor actual + comparativa al período anterior.
/// La tendencia se calcula como `(actual - anterior) / anterior * 100`,
/// null si `anterior == 0` (evita división por cero — sin punto de
/// comparación visualmente sale como "—").
class KpiMes {
  final int actual;
  final int anterior;
  final double? variacionPct;

  const KpiMes({
    required this.actual,
    required this.anterior,
    required this.variacionPct,
  });

  /// Helper: construye desde dos enteros calculando la variación.
  factory KpiMes.fromActualYAnterior(int actual, int anterior) {
    final pct = anterior == 0 ? null : (actual - anterior) / anterior * 100;
    return KpiMes(actual: actual, anterior: anterior, variacionPct: pct);
  }
}

/// KPI ICM con valor actual + variación semana anterior. Igual que
/// KpiMes pero con doubles.
class KpiIcm {
  final double actual;
  final double anterior;
  final double? variacionAbs; // diferencia absoluta de puntos ICM
  final int choferesEnPromedio;

  const KpiIcm({
    required this.actual,
    required this.anterior,
    required this.variacionAbs,
    required this.choferesEnPromedio,
  });

  factory KpiIcm.fromActualYAnterior(
    double actual,
    double anterior,
    int n,
  ) {
    final variacion = anterior == 0 ? null : actual - anterior;
    return KpiIcm(
      actual: actual,
      anterior: anterior,
      variacionAbs: variacion,
      choferesEnPromedio: n,
    );
  }
}

/// KPI sin comparativa (solo el número del momento).
class KpiSimple {
  final int valor;
  final String? sublabel;

  const KpiSimple({required this.valor, this.sublabel});
}

/// Un punto en una serie temporal (label visible + valor numérico).
class PuntoTendencia {
  final String label;
  final double valor;
  const PuntoTendencia({required this.label, required this.valor});
}

/// Un chofer en el top 5 (con nombre + ICM + categoría).
class ChoferRankingItem {
  final String dni;
  final String nombre;
  final double icm;
  // Color sugerido en hex sin prefijo para que la UI lo mapee. Si querés
  // cambiar el threshold, ajustar en `_categorizar`.
  final String categoria; // 'verde' | 'amarillo' | 'rojo'

  const ChoferRankingItem({
    required this.dni,
    required this.nombre,
    required this.icm,
    required this.categoria,
  });
}

class VistaEjecutivaService {
  VistaEjecutivaService._();

  /// Carga todos los KPIs del tablero en un solo Future. Las queries
  /// independientes corren en paralelo con `Future.wait`.
  static Future<KpisVistaEjecutiva> cargar({
    required FirebaseFirestore db,
  }) async {
    final ahora = DateTime.now();

    // Lanzar en paralelo — son queries independientes.
    final results = await Future.wait([
      _viajesDelMes(db, ahora),
      _icmFlota(db, ahora),
      _statsSnapshot(db),
      _tendenciaIcm(db, ahora, semanas: 12),
      _viajesPorSemana(db, ahora, semanas: 8),
    ]);

    final viajesMes = results[0] as KpiMes;
    final icm = results[1] as _IcmDosSemanas;
    final stats = results[2] as Map<String, dynamic>;
    final tendIcm = results[3] as List<PuntoTendencia>;
    final viajesSem = results[4] as List<PuntoTendencia>;

    // De ICM_SEMANAL ya viene el top 5 mejores y peores — los
    // extraemos del doc de la última semana cerrada (que ya pedimos).
    final mejores = icm.top5Mejores;
    final peores = icm.top5Peores;

    final choferesActivos = (stats['choferes_activos'] as num?)?.toInt() ?? 0;
    final unidadesAsign = (stats['unidades_asignadas'] as num?)?.toInt() ?? 0;
    final vencidos = (stats['vencidos'] as num?)?.toInt() ?? 0;
    final pendientes =
        (stats['revisiones_pendientes'] as num?)?.toInt() ?? 0;
    // "Alertas críticas" = vencidos + revisiones pendientes.
    final alertas = vencidos + pendientes;

    return KpisVistaEjecutiva(
      viajesDelMes: viajesMes,
      icmFlota: KpiIcm.fromActualYAnterior(
        icm.actual,
        icm.anterior,
        icm.choferesEnPromedio,
      ),
      choferesActivos: KpiSimple(
        valor: choferesActivos,
        sublabel: '$unidadesAsign con unidad asignada',
      ),
      alertasCriticas: KpiSimple(
        valor: alertas,
        sublabel: alertas == 0
            ? 'Todo al día'
            : '$vencidos vencidos · $pendientes revisiones',
      ),
      tendenciaIcm: tendIcm,
      viajesPorSemana: viajesSem,
      top5Mejores: mejores,
      top5Peores: peores,
    );
  }

  // ───────────────────────────────────────────────────────────────────
  // KPIs individuales
  // ───────────────────────────────────────────────────────────────────

  /// Cuenta viajes con `fecha_carga` en el mes actual y mes anterior.
  /// Solo cuenta los `activo: true` (excluye soft-deleted).
  /// Cuenta los 2 meses en paralelo.
  static Future<KpiMes> _viajesDelMes(
    FirebaseFirestore db,
    DateTime ahora,
  ) async {
    final inicioMesActual = DateTime(ahora.year, ahora.month, 1);
    final inicioMesAnterior = DateTime(ahora.year, ahora.month - 1, 1);
    final finMesAnterior = inicioMesActual;
    final results = await Future.wait([
      _contarViajesEnRango(db, inicioMesActual, ahora),
      _contarViajesEnRango(db, inicioMesAnterior, finMesAnterior),
    ]);
    return KpiMes.fromActualYAnterior(results[0], results[1]);
  }

  /// Count de viajes con `fecha_carga` en [desde, hasta) y `activo=true`.
  /// Usa `.count()` (count aggregation de Firestore) para no traer
  /// los docs enteros — barato y rápido. Si la query no tiene índice,
  /// Firestore tira error pidiéndolo (el indices.json ya tiene uno
  /// para `activo + fecha_carga`).
  static Future<int> _contarViajesEnRango(
    FirebaseFirestore db,
    DateTime desde,
    DateTime hasta,
  ) async {
    try {
      final agg = await db
          .collection('VIAJES_LOGISTICA')
          .where('activo', isEqualTo: true)
          .where('fecha_carga',
              isGreaterThanOrEqualTo: Timestamp.fromDate(desde))
          .where('fecha_carga', isLessThan: Timestamp.fromDate(hasta))
          .count()
          .get();
      return agg.count ?? 0;
    } catch (_) {
      // Fallback defensivo si el count falla (ej. sin índice): devolver
      // 0 para no romper el tablero. El error queda en consola.
      return 0;
    }
  }

  /// ICM promedio última semana cerrada vs anterior + top5/peores.
  /// Lee de `ICM_SEMANAL/{YYYY-WNN}` — debe estar generado por el cron
  /// `recomputeIcmSemanalScheduled` (lunes 6 AM ART). Si la última
  /// semana cerrada NO tiene doc todavía, cae a 0 (UI lo refleja con
  /// "—").
  static Future<_IcmDosSemanas> _icmFlota(
    FirebaseFirestore db,
    DateTime ahora,
  ) async {
    // Semana en curso: lunes 00 → próximo lunes 00.
    // Lo que queremos es la SEMANA ANTERIOR CERRADA = lunes pasado a hoy.
    // Y la previa a esa = 2 semanas atrás.
    final diasDesdeLunes = (ahora.weekday - DateTime.monday) % 7;
    final lunesActual = DateTime(ahora.year, ahora.month, ahora.day)
        .subtract(Duration(days: diasDesdeLunes));
    final lunesSemanaCerrada =
        lunesActual.subtract(const Duration(days: 7));
    final lunesPrevia =
        lunesActual.subtract(const Duration(days: 14));

    final idActual = _isoWeekId(lunesSemanaCerrada);
    final idAnterior = _isoWeekId(lunesPrevia);

    final snaps = await Future.wait([
      db.collection('ICM_SEMANAL').doc(idActual).get(),
      db.collection('ICM_SEMANAL').doc(idAnterior).get(),
    ]);
    final actualData = snaps[0].data();
    final anteriorData = snaps[1].data();

    final icmAct = (actualData?['icm_promedio'] as num?)?.toDouble() ?? 0.0;
    final icmAnt = (anteriorData?['icm_promedio'] as num?)?.toDouble() ?? 0.0;
    final n = (actualData?['choferes_activos'] as num?)?.toInt() ?? 0;

    final mejoresRaw =
        (actualData?['top_5_mejores'] as List?) ?? const [];
    final peoresRaw = (actualData?['top_5_peores'] as List?) ?? const [];
    final mejores = mejoresRaw
        .whereType<Map>()
        .map(_topItemToChofer)
        .toList(growable: false);
    final peores = peoresRaw
        .whereType<Map>()
        .map(_topItemToChofer)
        .toList(growable: false);

    return _IcmDosSemanas(
      actual: icmAct,
      anterior: icmAnt,
      choferesEnPromedio: n,
      top5Mejores: mejores,
      top5Peores: peores,
    );
  }

  static ChoferRankingItem _topItemToChofer(Map raw) {
    final m = raw.cast<String, dynamic>();
    final dni = (m['dni'] ?? '').toString();
    final nombre = (m['nombre'] ?? 'DNI $dni').toString();
    final icm = (m['icm'] as num?)?.toDouble() ?? 0.0;
    return ChoferRankingItem(
      dni: dni,
      nombre: nombre,
      icm: icm,
      categoria: _categorizar(icm),
    );
  }

  static String _categorizar(double icm) {
    if (icm >= 80) return 'verde';
    if (icm >= 60) return 'amarillo';
    return 'rojo';
  }

  /// Lee `STATS/dashboard` (poblado por el cron `recomputeDashboardStats`
  /// cada 5 min). Si el doc no existe devuelve {} para que los KPIs
  /// caigan a 0 silenciosamente.
  static Future<Map<String, dynamic>> _statsSnapshot(
    FirebaseFirestore db,
  ) async {
    try {
      final snap = await db.collection('STATS').doc('dashboard').get();
      return snap.data() ?? const {};
    } catch (_) {
      return const {};
    }
  }

  /// Serie de N puntos: ICM promedio por semana (las últimas N semanas
  /// cerradas + actual on-the-fly si está disponible).
  static Future<List<PuntoTendencia>> _tendenciaIcm(
    FirebaseFirestore db,
    DateTime ahora, {
    required int semanas,
  }) async {
    final diasDesdeLunes = (ahora.weekday - DateTime.monday) % 7;
    final lunesActual = DateTime(ahora.year, ahora.month, ahora.day)
        .subtract(Duration(days: diasDesdeLunes));
    // Lista de lunes desde el más viejo al más nuevo.
    final lunes = <DateTime>[];
    for (int i = semanas - 1; i >= 0; i--) {
      lunes.add(lunesActual.subtract(Duration(days: 7 * i)));
    }
    // Una lectura por semana — N reads (default 12). Asumimos que el
    // cron las dejó pre-calculadas. Si alguna falta, el punto queda
    // en 0 (no rompe el gráfico).
    final snaps = await Future.wait(
      lunes.map((l) =>
          db.collection('ICM_SEMANAL').doc(_isoWeekId(l)).get()),
    );
    final result = <PuntoTendencia>[];
    for (var i = 0; i < lunes.length; i++) {
      final data = snaps[i].data();
      final icm = (data?['icm_promedio'] as num?)?.toDouble() ?? 0.0;
      result.add(PuntoTendencia(
        label: _labelSemanaCorto(lunes[i]),
        valor: icm,
      ));
    }
    return result;
  }

  /// Serie de N puntos: cantidad de viajes por semana (count) las
  /// últimas N semanas cerradas + la actual.
  /// Suma viajes con `activo=true` y `fecha_carga` en el rango.
  static Future<List<PuntoTendencia>> _viajesPorSemana(
    FirebaseFirestore db,
    DateTime ahora, {
    required int semanas,
  }) async {
    final diasDesdeLunes = (ahora.weekday - DateTime.monday) % 7;
    final lunesActual = DateTime(ahora.year, ahora.month, ahora.day)
        .subtract(Duration(days: diasDesdeLunes));
    final lunes = <DateTime>[];
    for (int i = semanas - 1; i >= 0; i--) {
      lunes.add(lunesActual.subtract(Duration(days: 7 * i)));
    }
    final counts = await Future.wait(
      lunes.map((l) => _contarViajesEnRango(
            db,
            l,
            l.add(const Duration(days: 7)),
          )),
    );
    final result = <PuntoTendencia>[];
    for (var i = 0; i < lunes.length; i++) {
      result.add(PuntoTendencia(
        label: _labelSemanaCorto(lunes[i]),
        valor: counts[i].toDouble(),
      ));
    }
    return result;
  }

  // ───────────────────────────────────────────────────────────────────
  // Helpers
  // ───────────────────────────────────────────────────────────────────

  /// ID semana ISO 8601 ("YYYY-WNN"). Mismo algoritmo que el cron
  /// server-side y que `icm_historico_service`. Crítico que sean
  /// idénticos: si un dia se cambia uno, hay que cambiar todos.
  static String _isoWeekId(DateTime d) {
    final target = DateTime.utc(d.year, d.month, d.day);
    final dayNum = (target.weekday + 6) % 7;
    final thursday = target.add(Duration(days: 3 - dayNum));
    final firstThursday = DateTime.utc(thursday.year, 1, 4);
    final firstThursdayDayNum = (firstThursday.weekday + 6) % 7;
    final week = 1 +
        ((thursday.difference(firstThursday).inDays -
                    3 +
                    firstThursdayDayNum) /
                7)
            .round();
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }

  /// Label corto para el eje X de los gráficos: "12 May" (día + mes abrev).
  /// Más legible que "S 12-18 May" para muchos puntos juntos.
  static String _labelSemanaCorto(DateTime lunes) {
    const meses = [
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
    ];
    return '${lunes.day} ${meses[lunes.month - 1]}';
  }
}

/// Estructura interna que devuelve `_icmFlota` con todo lo necesario
/// para los KPIs ICM y el top5/peores (evita re-leer el mismo doc).
class _IcmDosSemanas {
  final double actual;
  final double anterior;
  final int choferesEnPromedio;
  final List<ChoferRankingItem> top5Mejores;
  final List<ChoferRankingItem> top5Peores;

  const _IcmDosSemanas({
    required this.actual,
    required this.anterior,
    required this.choferesEnPromedio,
    required this.top5Mejores,
    required this.top5Peores,
  });
}

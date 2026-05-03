import 'package:cloud_firestore/cloud_firestore.dart';

/// Doc de la colección `VOLVO_SCORES_DIARIOS`. Cada doc representa el
/// score AGREGADO POR DÍA de un vehículo (o de la flota completa).
///
/// La popula la scheduled function `volvoScoresPoller` (1x por día a las
/// 04:00 ART) leyendo la Volvo Group Scores API v2.0.2.
///
/// **Score "total" 0-100**: indica eficiencia general del manejo. Cuanto
/// más alto, mejor. Las plantas operativas suelen tener 60-80; >85 es
/// excelente, <50 indica problemas serios.
///
/// **Sub-scores**: 17+ métricas adicionales con la misma escala 0-100.
/// Las más importantes para el reporte:
///   - `anticipation`: cuánto anticipa el chofer al tráfico.
///   - `braking`: pisadas de freno por parada (artefacto del patrón
///     operativo — no necesariamente buen manejo).
///   - `coasting`: distancia rodando libre sobre total.
///   - `idling`: minimización del tiempo en ralentí (CRÍTICO para consumo).
///   - `overspeed`: episodios de sobrevelocidad.
///   - `cruiseControl`: distancia con cruise activo.
///
/// **Métricas operativas** (no son scores, son crudos):
///   - `totalDistance`: METROS recorridos (convertir a km en UI).
///   - `avgFuelConsumption`: ML/100km (formato ml es nativo, dividir por
///     1000 para L/100km).
///   - `vehicleUtilization`: % de uso del vehículo en el período.
///   - `co2Emissions`: TONELADAS de CO2.
class VolvoScoreDiario {
  /// Doc id: `{patente}_{YYYY-MM-DD}` o `_FLEET_{YYYY-MM-DD}`.
  final String id;

  /// `true` si este doc representa el agregado de la flota completa
  /// (no un vehículo individual). En ese caso `patente` y `vin` son
  /// nulos.
  final bool esFleet;

  /// Patente del vehículo. `null` si `esFleet == true`.
  final String? patente;

  /// VIN del vehículo. `null` si `esFleet == true`.
  final String? vin;

  /// Fecha del score como YYYY-MM-DD (TZ Argentina).
  final String fecha;

  /// Inicio del día ART como Timestamp — usar para queries por rango.
  final DateTime fechaTs;

  /// Score total 0-100 (`null` si Volvo no devolvió data ese día).
  final double? scoreTotal;

  /// Mapa de los 17+ sub-scores. Claves canónicas según spec v2.0.2:
  /// anticipation, braking, coasting, engineAndGearUtilization,
  /// withinEconomy, aboveEconomy, engineLoad, gearboxInAutoMode,
  /// gearboxInManualMode, gearboxInPowerMode, overrev, topgear,
  /// speedAdaption, cruiseControl, overspeed, standstill, idling,
  /// edriveMode, standstillElectric.
  final Map<String, double> subScores;

  /// Segundos de motor encendido en el período.
  final int? totalTime;

  /// Velocidad promedio en km/h.
  final double? avgSpeedDriving;

  /// Distancia total en METROS (no km — la API usa metros).
  final double? totalDistance;

  /// Consumo promedio en ml/100km. Para L/100km, dividir por 1000.
  final double? avgFuelConsumption;

  /// % de uso del vehículo (0-100).
  final double? vehicleUtilization;

  /// Toneladas de CO2 emitidas.
  final double? co2Emissions;

  const VolvoScoreDiario({
    required this.id,
    required this.esFleet,
    required this.patente,
    required this.vin,
    required this.fecha,
    required this.fechaTs,
    required this.scoreTotal,
    required this.subScores,
    required this.totalTime,
    required this.avgSpeedDriving,
    required this.totalDistance,
    required this.avgFuelConsumption,
    required this.vehicleUtilization,
    required this.co2Emissions,
  });

  /// Distancia total en kilómetros (conversión desde metros). Devuelve
  /// `null` si la API no entregó el dato.
  double? get totalDistanceKm {
    final m = totalDistance;
    return m == null ? null : m / 1000;
  }

  /// Consumo en L/100km (la API entrega en ml/100km).
  double? get fuelLPor100Km {
    final ml = avgFuelConsumption;
    return ml == null ? null : ml / 1000;
  }

  /// Horas de motor encendido (la API entrega en segundos).
  double? get horasMotor {
    final s = totalTime;
    return s == null ? null : s / 3600;
  }

  factory VolvoScoreDiario.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return VolvoScoreDiario.fromMap(doc.id, doc.data());
  }

  factory VolvoScoreDiario.fromMap(String id, Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    final esFleet = d['es_fleet'] == true;
    final scoresRaw = d['scores'];
    final Map<String, double> subScores = {};
    if (scoresRaw is Map) {
      scoresRaw.forEach((k, v) {
        if (v is num) subScores[k.toString()] = v.toDouble();
      });
    }
    return VolvoScoreDiario(
      id: id,
      esFleet: esFleet,
      patente: esFleet ? null : d['patente']?.toString(),
      vin: esFleet ? null : d['vin']?.toString(),
      fecha: (d['fecha'] ?? '').toString(),
      fechaTs: (d['fecha_ts'] as Timestamp?)?.toDate() ?? DateTime.now(),
      scoreTotal: subScores['total'],
      subScores: subScores,
      totalTime: (d['totalTime'] as num?)?.toInt(),
      avgSpeedDriving: (d['avgSpeedDriving'] as num?)?.toDouble(),
      totalDistance: (d['totalDistance'] as num?)?.toDouble(),
      avgFuelConsumption: (d['avgFuelConsumption'] as num?)?.toDouble(),
      vehicleUtilization: (d['vehicleUtilization'] as num?)?.toDouble(),
      co2Emissions: (d['co2Emissions'] as num?)?.toDouble(),
    );
  }
}

/// Etiquetas legibles para los sub-scores. Lista en el orden que tiene
/// más sentido visualmente (de "manejo" a "operación").
class VolvoSubScoreLabels {
  VolvoSubScoreLabels._();

  static const Map<String, String> etiquetas = {
    'anticipation': 'Anticipación',
    'braking': 'Frenado',
    'coasting': 'Rodar libre',
    'engineAndGearUtilization': 'Uso motor + caja',
    'withinEconomy': 'RPM en zona económica',
    'aboveEconomy': 'RPM sobre zona económica',
    'engineLoad': 'Carga motor',
    'gearboxInAutoMode': 'Caja en automático',
    'gearboxInPowerMode': 'Caja en power',
    'overrev': 'Sin overrev',
    'topgear': 'En marcha alta',
    'speedAdaption': 'Adaptación velocidad',
    'cruiseControl': 'Uso de cruise',
    'overspeed': 'Sin sobrevelocidad',
    'standstill': 'Sin tiempo parado',
    'idling': 'Sin ralentí',
  };

  /// Etiqueta legible o el key crudo si no está mapeado.
  static String label(String key) => etiquetas[key] ?? key;
}

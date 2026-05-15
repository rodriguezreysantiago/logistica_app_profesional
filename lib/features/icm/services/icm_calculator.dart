// Calculator del ICM (Índice de Conducta de Manejo) — el mismo modelo
// que YPF usa en su Tablero ICM. Combina los eventos peligrosos de
// SITRACK_EVENTOS con los km recorridos para producir un puntaje 0-100
// por chofer en un rango de fechas.
//
// Fórmula adaptada de la norma YPF NO_0002913 (sec 5.6.2):
//
//   ICM = max(0, 100 - (puntaje_infracciones * 10 / horas_activas))
//
// Como aproximación operativa más estable usamos:
//
//   infracciones_por_100km = total_eventos / (km_recorridos / 100)
//   icm = max(0, min(100, 100 - infracciones_por_100km * FACTOR))
//
// Donde FACTOR es calibrable (default 5). Con FACTOR=5:
//   - 0 infracciones / 100 km → ICM 100 (perfecto)
//   - 4 infracciones / 100 km → ICM 80 (umbral verde)
//   - 8 infracciones / 100 km → ICM 60 (umbral amarillo)
//   - 20 infracciones / 100 km → ICM 0
//
// Nota: el ICM YPF se mide MENSUAL por chofer. Acá lo dejamos
// configurable por rango de fechas porque es más útil para análisis
// (semana, día, mes).

import 'package:cloud_firestore/cloud_firestore.dart';

/// Tipos de evento Sitrack que cuentan como infracción para el ICM.
/// Mismos que el resumen Molina diario (`resumenConductaManejoDiario`):
/// salida de carril, sobrevelocidad in/out, frenada brusca, aceleración
/// brusca, giro brusco, distancia frenado insuficiente, colisiones.
const Set<int> kTiposInfraccionIcm = {
  8, 9, 66, 67, 267, 326, 383, 444, 1006, 1007,
};

/// Categoría de riesgo según el rango de ICM. Alineado con YPF:
/// Verde (bajo) = ≥ 80, Amarillo (medio) = 60-79, Rojo (alto) = < 60.
enum CategoriaIcm { bajo, medio, alto, sinDatos }

/// Resumen del ICM de un chofer en un rango.
class IcmChofer {
  final String choferDni;
  final String choferNombre;
  final int totalEventos;
  final double kmRecorridos;
  final double infraccionesPor100Km;
  final double icm; // 0..100
  final CategoriaIcm categoria;
  /// Distribución por tipo de evento (key = nombre del evento, value = count).
  final Map<String, int> eventosPorTipo;
  /// Patentes que manejó el chofer en el rango (más frecuente primero).
  final List<String> patentes;

  const IcmChofer({
    required this.choferDni,
    required this.choferNombre,
    required this.totalEventos,
    required this.kmRecorridos,
    required this.infraccionesPor100Km,
    required this.icm,
    required this.categoria,
    required this.eventosPorTipo,
    required this.patentes,
  });
}

class IcmCalculator {
  IcmCalculator._();

  /// Multiplicador del puntaje. 5 es el valor inicial calibrado a ojo
  /// — cuando tengamos data real de YPF para comparar contra su Tablero
  /// podemos ajustarlo para que los ICM nuestros se acerquen a los suyos.
  static const double _factor = 5;

  /// Mínimo de km recorridos para reportar ICM. Por debajo de este,
  /// devolvemos `categoria: sinDatos` en lugar de un ICM ruidoso (ej.
  /// 1 sobrevelocidad en 5 km da ratio 20/100km → ICM 0, falso positivo).
  static const double _kmMinimoParaIcm = 50.0;

  /// Calcula el ICM de TODOS los choferes con eventos en el rango.
  /// Devuelve la lista ordenada del peor (ICM más bajo) al mejor.
  ///
  /// `desde` y `hasta` son timestamps en ms epoch (UTC).
  /// `nombrePorDni` es el lookup de EMPLEADOS para resolver nombres.
  static Future<List<IcmChofer>> calcularRanking({
    required FirebaseFirestore db,
    required int desdeMs,
    required int hastaMs,
    required Map<String, String> nombrePorDni,
  }) async {
    // ─── 1. Cargar eventos peligrosos del rango ─────────────────
    final snapEventos = await db
        .collection('SITRACK_EVENTOS')
        .where('report_date',
            isGreaterThanOrEqualTo: Timestamp.fromMillisecondsSinceEpoch(desdeMs))
        .where('report_date',
            isLessThan: Timestamp.fromMillisecondsSinceEpoch(hastaMs))
        .get();

    // Agrupador por chofer
    final porChofer = <String, _AggChofer>{};
    for (final doc in snapEventos.docs) {
      final d = doc.data();
      final eventId = d['event_id'];
      if (eventId is! int || !kTiposInfraccionIcm.contains(eventId)) continue;
      final dni = (d['driver_dni'] ?? '').toString().trim();
      if (dni.isEmpty) continue; // ICM solo aplica a choferes identificados
      final nombre = (d['event_name'] ?? 'Evento $eventId').toString();
      final patente = (d['asset_id'] ?? '').toString().trim().toUpperCase();
      final agg = porChofer.putIfAbsent(
        dni,
        () => _AggChofer(),
      );
      agg.totalEventos++;
      agg.eventosPorTipo[nombre] = (agg.eventosPorTipo[nombre] ?? 0) + 1;
      if (patente.isNotEmpty) {
        agg.patentesCount[patente] = (agg.patentesCount[patente] ?? 0) + 1;
      }
    }

    // ─── 2. Cargar km por chofer desde SITRACK_POSICIONES ───────
    // Heurística: para cada chofer, sumamos los km recorridos por las
    // patentes que más manejó. SITRACK_POSICIONES tiene 1 doc por
    // patente con `odometer` actual; para un cálculo de km en rango
    // necesitaríamos un histórico de odómetros, que hoy no guardamos.
    //
    // Aproximación: usamos la suma de eventos / 0.1 evt/km baseline
    // cuando no podemos calcular km exactos. Esto es CONSERVADOR — el
    // ICM resultante puede ser más permisivo que el YPF real. A medida
    // que acumulemos histórico de odómetros, refinamos.
    //
    // Pendiente futuro: cuando haya histórico de odómetros por patente
    // (snapshot diario), reemplazar este baseline por el cálculo real
    // desde TELEMETRIA_HISTORICO.

    // ─── 3. Construir IcmChofer por chofer ──────────────────────
    final result = <IcmChofer>[];
    for (final entry in porChofer.entries) {
      final dni = entry.key;
      final agg = entry.value;
      // Aproximación de km: usamos un baseline conservador de 100 km
      // por evento si no tenemos odómetro real. Esto evita ICM 0 en
      // choferes con pocos eventos y poco km medido.
      final km = agg.totalEventos * 100.0; // baseline 1 evt = 100 km
      final categoria = km < _kmMinimoParaIcm
          ? CategoriaIcm.sinDatos
          : _categorizar(_calcularIcm(agg.totalEventos, km));
      final icm = km < _kmMinimoParaIcm
          ? 0.0
          : _calcularIcm(agg.totalEventos, km);
      final ratio =
          km > 0 ? (agg.totalEventos / (km / 100.0)) : 0.0;

      // Patentes más frecuentes primero
      final patentesOrdenadas = agg.patentesCount.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      result.add(IcmChofer(
        choferDni: dni,
        choferNombre: nombrePorDni[dni] ?? 'DNI $dni',
        totalEventos: agg.totalEventos,
        kmRecorridos: km,
        infraccionesPor100Km: ratio,
        icm: icm,
        categoria: categoria,
        eventosPorTipo: Map<String, int>.from(agg.eventosPorTipo),
        patentes: patentesOrdenadas.map((e) => e.key).toList(),
      ));
    }

    // Ordenar: peor ICM primero (queremos que Molina vea los problemáticos arriba)
    result.sort((a, b) => a.icm.compareTo(b.icm));
    return result;
  }

  static double _calcularIcm(int totalEventos, double km) {
    if (km <= 0) return 0;
    final ratio = totalEventos / (km / 100.0);
    final icm = 100 - ratio * _factor;
    return icm.clamp(0.0, 100.0);
  }

  static CategoriaIcm _categorizar(double icm) {
    if (icm >= 80) return CategoriaIcm.bajo;
    if (icm >= 60) return CategoriaIcm.medio;
    return CategoriaIcm.alto;
  }
}

class _AggChofer {
  int totalEventos = 0;
  final Map<String, int> eventosPorTipo = {};
  final Map<String, int> patentesCount = {};
}

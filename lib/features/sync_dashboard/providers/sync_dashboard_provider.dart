import 'package:flutter/foundation.dart';

import '../../../shared/utils/formatters.dart';

/// Tipo de evento por unidad. Se usa para colorear/filtrar la lista de
/// actividad reciente.
enum SyncEventTipo {
  /// La unidad se mandó a sincronizar y devolvió OK.
  exito,

  /// La unidad falló (network, parsing, auth, etc.).
  error,

  /// La unidad NO se sincronizó: cooldown, sin VIN, no es Volvo, ya en
  /// vuelo. Útil para diagnosticar "no se actualiza nada".
  saltado,
}

/// Un evento individual de sincronización. Lo crea el AutoSyncService y
/// el provider lo guarda en una lista circular.
class SyncEvent {
  final String patente;
  final SyncEventTipo tipo;
  final DateTime cuando;

  /// Mensaje descriptivo. Para errores: el message de la excepción. Para
  /// saltados: el motivo (cooldown, sin VIN, etc.).
  final String? mensaje;

  const SyncEvent({
    required this.patente,
    required this.tipo,
    required this.cuando,
    this.mensaje,
  });
}

/// Resumen de un ciclo terminado del AutoSyncService. Sirve para ver el
/// histórico ("hace 5 ciclos sincronizaron 8 unidades, hubo 2 errores").
class CicloResumen {
  final int numero;
  final DateTime inicio;
  final Duration duracion;
  final int total;
  final int exito;
  final int error;
  final int saltado;

  const CicloResumen({
    required this.numero,
    required this.inicio,
    required this.duracion,
    required this.total,
    required this.exito,
    required this.error,
    required this.saltado,
  });
}

class SyncDashboardProvider extends ChangeNotifier {
  // =========================
  // ESTADO GLOBAL
  // =========================

  int _totalSyncs = 0;
  int _successSyncs = 0;
  int _failedSyncs = 0;
  int _skippedSyncs = 0;

  /// Cantidad de syncs en vuelo en este momento.
  int _activeSyncs = 0;

  /// Latencias de los últimos N requests (para promedio).
  final List<Duration> _latencies = [];

  DateTime? _lastSyncAt;

  // =========================
  // CICLO ACTUAL
  // =========================

  int _cycle = 0;
  int _cycleTotal = 0;
  int _cycleProcessed = 0;
  DateTime? _cycleStartedAt;

  // =========================
  // ACTIVIDAD RECIENTE
  // =========================

  /// Últimos 50 eventos. Lista circular: el más nuevo al frente.
  static const int _maxEventos = 50;
  final List<SyncEvent> _eventos = [];

  /// Últimos 15 ciclos. Igual: el más reciente al frente.
  static const int _maxCiclos = 15;
  final List<CicloResumen> _historicoCiclos = [];

  // =========================
  // GETTERS
  // =========================

  int get cycle => _cycle;
  int get cycleTotal => _cycleTotal;
  int get cycleProcessed => _cycleProcessed;
  int get totalSyncs => _totalSyncs;
  int get successSyncs => _successSyncs;
  int get failedSyncs => _failedSyncs;
  int get skippedSyncs => _skippedSyncs;
  int get activeSyncs => _activeSyncs;
  DateTime? get lastSyncAt => _lastSyncAt;

  /// Lista inmutable de eventos recientes (más nuevo primero).
  List<SyncEvent> get eventosRecientes => List.unmodifiable(_eventos);

  /// Lista inmutable de últimos ciclos (más reciente primero).
  List<CicloResumen> get historicoCiclos => List.unmodifiable(_historicoCiclos);

  double get successRate {
    final intentados = _successSyncs + _failedSyncs;
    if (intentados == 0) return 0;
    return _successSyncs / intentados;
  }

  double get avgLatencyMs {
    if (_latencies.isEmpty) return 0;
    final total =
        _latencies.fold<int>(0, (sum, d) => sum + d.inMilliseconds);
    return total / _latencies.length;
  }

  // =========================
  // CICLO: control desde AutoSyncService
  // =========================

  void startCycle() {
    _cycle++;
    _cycleTotal = 0;
    _cycleProcessed = 0;
    _cycleStartedAt = DateTime.now();
    notifyListeners();
  }

  void setTotal(int value) {
    _cycleTotal = value;
    notifyListeners();
  }

  void updateProgress(int value) {
    _cycleProcessed = value;
    notifyListeners();
  }

  /// Cierra el ciclo actual: actualiza totales y agrega un resumen al
  /// histórico. [success], [error] y [skipped] son contadores DEL CICLO,
  /// no del total. Acá los acumulo a los globales.
  void finishCycle({
    required int total,
    required int success,
    required int error,
    required int skipped,
  }) {
    _totalSyncs += total;
    _successSyncs += success;
    _failedSyncs += error;
    _skippedSyncs += skipped;
    _activeSyncs = 0;
    _lastSyncAt = DateTime.now();

    final inicio = _cycleStartedAt ?? _lastSyncAt!;
    final resumen = CicloResumen(
      numero: _cycle,
      inicio: inicio,
      duracion: _lastSyncAt!.difference(inicio),
      total: total,
      exito: success,
      error: error,
      saltado: skipped,
    );

    // Insertamos al frente y recortamos al máximo.
    _historicoCiclos.insert(0, resumen);
    if (_historicoCiclos.length > _maxCiclos) {
      _historicoCiclos.removeRange(_maxCiclos, _historicoCiclos.length);
    }

    _cycleStartedAt = null;
    notifyListeners();
  }

  /// El ciclo entero falló (excepción antes de procesar las unidades).
  void failCycle(String error) {
    _activeSyncs = 0;
    _lastSyncAt = DateTime.now();
    _addEvento(SyncEvent(
      patente: '(ciclo)',
      tipo: SyncEventTipo.error,
      cuando: _lastSyncAt!,
      mensaje: error,
    ));
    notifyListeners();
  }

  // =========================
  // EVENTOS POR UNIDAD
  // =========================

  void markVehicleQueued(String patente) {
    _activeSyncs++;
    notifyListeners();
  }

  /// Marcador de "estoy ejecutando este request ahora". No incrementa
  /// nada; el activeSyncs ya se contó en markVehicleQueued.
  void markVehicleSyncing(String patente) {
    // Reservado para futuras mejoras (mostrar qué patente está corriendo).
  }

  void markVehicleSuccess(String patente, {Duration? duracion}) {
    _activeSyncs = (_activeSyncs - 1).clamp(0, 999999);
    _lastSyncAt = DateTime.now();
    if (duracion != null) addLatency(duracion);
    _addEvento(SyncEvent(
      patente: patente,
      tipo: SyncEventTipo.exito,
      cuando: _lastSyncAt!,
    ));
    notifyListeners();
  }

  void markVehicleError(String patente, String error) {
    _activeSyncs = (_activeSyncs - 1).clamp(0, 999999);
    _lastSyncAt = DateTime.now();
    _addEvento(SyncEvent(
      patente: patente,
      tipo: SyncEventTipo.error,
      cuando: _lastSyncAt!,
      mensaje: error,
    ));
    notifyListeners();
  }

  /// Una unidad NO se sincronizó: cooldown, sin VIN, no es Volvo, ya en
  /// loading. [motivo] es una descripción corta.
  void markVehicleSkipped(String patente, String motivo) {
    _addEvento(SyncEvent(
      patente: patente,
      tipo: SyncEventTipo.saltado,
      cuando: DateTime.now(),
      mensaje: motivo,
    ));
    notifyListeners();
  }

  void _addEvento(SyncEvent e) {
    _eventos.insert(0, e);
    if (_eventos.length > _maxEventos) {
      _eventos.removeRange(_maxEventos, _eventos.length);
    }
  }

  // =========================
  // LATENCY
  // =========================

  void addLatency(Duration duration) {
    _latencies.add(duration);
    if (_latencies.length > 100) {
      _latencies.removeAt(0);
    }
    notifyListeners();
  }

  // =========================
  // RESET
  // =========================

  void reset() {
    _totalSyncs = 0;
    _successSyncs = 0;
    _failedSyncs = 0;
    _skippedSyncs = 0;
    _activeSyncs = 0;
    _cycle = 0;
    _cycleTotal = 0;
    _cycleProcessed = 0;
    _cycleStartedAt = null;
    _latencies.clear();
    _lastSyncAt = null;
    _eventos.clear();
    _historicoCiclos.clear();
    notifyListeners();
  }

  // =========================
  // SNAPSHOT (para logs / debugging)
  // =========================

  Map<String, dynamic> snapshot() {
    return {
      "cycle": _cycle,
      "cycleTotal": _cycleTotal,
      "cycleProcessed": _cycleProcessed,
      "totalSyncs": _totalSyncs,
      "successSyncs": _successSyncs,
      "failedSyncs": _failedSyncs,
      "skippedSyncs": _skippedSyncs,
      "activeSyncs": _activeSyncs,
      "successRate": successRate,
      "avgLatencyMs": avgLatencyMs,
      "lastSyncAt": AppFormatters.formatearFechaHora(_lastSyncAt),
      "eventosRecientes": _eventos.length,
      "ciclosEnHistorial": _historicoCiclos.length,
    };
  }
}

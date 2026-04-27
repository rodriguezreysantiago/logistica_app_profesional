import 'package:flutter/foundation.dart';

class SyncDashboardProvider extends ChangeNotifier {
  // =========================
  // 🔥 ESTADO GLOBAL
  // =========================

  int _totalSyncs = 0;
  int _successSyncs = 0;
  int _failedSyncs = 0;

  int _activeSyncs = 0;

  final List<Duration> _latencies = [];

  DateTime? _lastSyncAt;

  // =========================
  // 🔥 CICLO ACTUAL (AUTO SYNC)
  // =========================

  int _cycle = 0;
  int _cycleTotal = 0;
  int _cycleProcessed = 0;

  int get cycle => _cycle;
  int get cycleTotal => _cycleTotal;
  int get cycleProcessed => _cycleProcessed;

  // =========================
  // GETTERS
  // =========================

  int get totalSyncs => _totalSyncs;
  int get successSyncs => _successSyncs;
  int get failedSyncs => _failedSyncs;

  int get activeSyncs => _activeSyncs;

  DateTime? get lastSyncAt => _lastSyncAt;

  double get successRate {
    if (_totalSyncs == 0) return 0;
    return _successSyncs / _totalSyncs;
  }

  double get avgLatencyMs {
    if (_latencies.isEmpty) return 0;
    final total =
        _latencies.fold<int>(0, (sum, d) => sum + d.inMilliseconds);
    return total / _latencies.length;
  }

  // =========================
  // 🔥 CYCLE CONTROL
  // =========================

  void startCycle() {
    _cycle++;
    _cycleTotal = 0;
    _cycleProcessed = 0;

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

  void finishCycle({
    required int total,
    required int success,
    required int errors,
  }) {
    _totalSyncs += total;
    _successSyncs += success;
    _failedSyncs += errors;

    _activeSyncs = 0;
    _lastSyncAt = DateTime.now();

    notifyListeners();
  }

  void failCycle(String error) {
    _activeSyncs = 0;
    _failedSyncs++;
    _lastSyncAt = DateTime.now();

    notifyListeners();
  }

  // =========================
  // 🔥 VEHICLE TRACKING
  // =========================

  void markVehicleQueued(String patente) {
    _activeSyncs++;
    notifyListeners();
  }

  void markVehicleSyncing(String patente) {}

  void markVehicleSuccess(String patente) {
    _activeSyncs = (_activeSyncs - 1).clamp(0, 999999);

    _successSyncs++;
    _lastSyncAt = DateTime.now();

    notifyListeners();
  }

  void markVehicleError(String patente, String error) {
    _activeSyncs = (_activeSyncs - 1).clamp(0, 999999);

    _failedSyncs++;
    _lastSyncAt = DateTime.now();

    notifyListeners();
  }

  // =========================
  // 🔥 LATENCY
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
    _activeSyncs = 0;

    _cycle = 0;
    _cycleTotal = 0;
    _cycleProcessed = 0;

    _latencies.clear();
    _lastSyncAt = null;

    notifyListeners();
  }

  // =========================
  // SNAPSHOT
  // =========================

  Map<String, dynamic> snapshot() {
    return {
      "cycle": _cycle,
      "cycleTotal": _cycleTotal,
      "cycleProcessed": _cycleProcessed,
      "totalSyncs": _totalSyncs,
      "successSyncs": _successSyncs,
      "failedSyncs": _failedSyncs,
      "activeSyncs": _activeSyncs,
      "successRate": successRate,
      "avgLatencyMs": avgLatencyMs,
      "lastSyncAt": _lastSyncAt?.toIso8601String(),
    };
  }
}
import 'dart:async';
import 'dart:math';

import '../../features/vehicles/providers/vehiculo_provider.dart';
import '../../features/sync_dashboard/providers/sync_dashboard_provider.dart';

class AutoSyncService {
  final VehiculoProvider provider;
  final SyncDashboardProvider? dashboard;

  Timer? _timer;
  bool _running = false;

  final Random _random = Random();

  // 🔥 métricas internas
  int _cycle = 0;
  int _lastProcessed = 0;
  int _lastSuccess = 0;
  int _lastErrors = 0;

  AutoSyncService(
    this.provider, {
    this.dashboard,
  });

  void start() {
    if (_timer != null) return;

    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      _sync();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _sync() async {
    if (_running) return;
    _running = true;

    _cycle++;
    _lastProcessed = 0;
    _lastSuccess = 0;
    _lastErrors = 0;

    dashboard?.startCycle();

    try {
      final snapshot = await provider.repository
          .getVehiculosPorTipo("TRACTOR")
          .first;

      final docs = snapshot.docs;

      dashboard?.setTotal(docs.length);

      for (final doc in docs) {
        final data = doc.data() as Map<String, dynamic>;

        final patente = doc.id;
        final vin = (data['VIN'] ?? '').toString();
        final marca = data['MARCA'];

        _lastProcessed++;
        dashboard?.updateProgress(_lastProcessed);

        // 🔥 filtro base
        if (marca != 'VOLVO' || vin.isEmpty) continue;

        if (!provider.debeSincronizar(patente)) continue;
        if (provider.isLoading(patente)) continue;

        dashboard?.markVehicleSyncing(patente);

        try {
          await provider.sync(patente, vin);

          provider.marcarSync(patente);

          _lastSuccess++;
          dashboard?.markVehicleSuccess(patente);
        } catch (e) {
          _lastErrors++;
          dashboard?.markVehicleError(patente, e.toString());
        }

        final delay = 200 + _random.nextInt(300);
        await Future.delayed(Duration(milliseconds: delay));
      }

      dashboard?.finishCycle(
        total: docs.length,
        success: _lastSuccess,
        errors: _lastErrors,
      );
    } catch (e) {
      dashboard?.failCycle(e.toString());
    } finally {
      _running = false;
    }
  }

  // =========================
  // 🔥 opcional: métricas debug
  // =========================
  Map<String, dynamic> getMetrics() {
    return {
      "cycle": _cycle,
      "processed": _lastProcessed,
      "success": _lastSuccess,
      "errors": _lastErrors,
    };
  }
}
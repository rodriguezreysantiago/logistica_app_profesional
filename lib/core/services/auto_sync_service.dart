import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../features/vehicles/providers/vehiculo_provider.dart';
import '../../features/sync_dashboard/providers/sync_dashboard_provider.dart';
import 'prefs_service.dart';

/// Sincroniza periódicamente la flota Volvo con la API de Volvo Connect
/// y reporta cada paso al [SyncDashboardProvider] para que el admin pueda
/// observar la salud de la integración.
class AutoSyncService {
  final VehiculoProvider provider;
  final SyncDashboardProvider? dashboard;

  Timer? _timer;
  bool _running = false;

  final Random _random = Random();

  /// Frecuencia entre ciclos automáticos.
  static const Duration _intervalo = Duration(seconds: 60);

  /// Pausa entre cada unidad procesada (anti-rate-limit Volvo).
  static const int _delayMinMs = 200;
  static const int _delayMaxMs = 500;

  AutoSyncService(
    this.provider, {
    this.dashboard,
  });

  void start() {
    if (_timer != null) return;

    // Primer ciclo inmediato (no esperamos 60 seg para que el usuario vea
    // actividad apenas abre la app), después cada minuto.
    _runOnce();
    _timer = Timer.periodic(_intervalo, (_) => _runOnce());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Dispara un ciclo manualmente (botón "EJECUTAR AHORA" del dashboard).
  /// Si ya hay uno corriendo, no hace nada — devuelve [false].
  Future<bool> runNow() async {
    if (_running) return false;
    await _sync();
    return true;
  }

  /// Helper para que el Timer.periodic no quede esperando el future.
  void _runOnce() {
    // ignore: unawaited_futures
    _sync();
  }

  Future<void> _sync() async {
    if (_running) return;

    // Las rules de Firestore requieren `isAdmin()` para escribir en
    // VEHICULOS y TELEMETRIA_HISTORICO. Si no hay usuario logueado o el
    // rol no es ADMIN, salimos en silencio — evita logs llenos de
    // "Permission denied" cuando un chofer abre la app o cuando la app
    // arranca antes de que el AuthGuard redirija al login.
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || PrefsService.rol != 'ADMIN') {
      return;
    }

    _running = true;

    int procesados = 0;
    int exito = 0;
    int errores = 0;
    int saltados = 0;

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
        final vin = (data['VIN'] ?? '').toString().trim();
        final marca = (data['MARCA'] ?? '').toString().toUpperCase();

        procesados++;
        dashboard?.updateProgress(procesados);

        // ─── FILTROS DE ELEGIBILIDAD ───
        // Cada filtro reporta el motivo del skip al dashboard para que
        // el admin pueda diagnosticar por qué algo no se actualiza.
        if (marca != 'VOLVO') {
          dashboard?.markVehicleSkipped(patente, 'No es Volvo (marca: $marca)');
          saltados++;
          continue;
        }
        if (vin.isEmpty) {
          dashboard?.markVehicleSkipped(patente, 'Sin VIN cargado');
          saltados++;
          continue;
        }
        if (provider.isLoading(patente)) {
          dashboard?.markVehicleSkipped(patente, 'Ya está sincronizando');
          saltados++;
          continue;
        }
        if (!provider.debeSincronizar(patente)) {
          dashboard?.markVehicleSkipped(
              patente, 'Cooldown (sincronizada hace <5 min)');
          saltados++;
          continue;
        }

        // ─── EJECUTAR SYNC ───
        dashboard?.markVehicleQueued(patente);
        dashboard?.markVehicleSyncing(patente);

        final stopwatch = Stopwatch()..start();
        try {
          await provider.sync(patente, vin);
          provider.marcarSync(patente);
          stopwatch.stop();
          dashboard?.markVehicleSuccess(patente,
              duracion: stopwatch.elapsed);
          exito++;
        } catch (e) {
          stopwatch.stop();
          dashboard?.markVehicleError(patente, e.toString());
          errores++;
        }

        // Pausa anti-rate-limit entre cada request.
        final delay =
            _delayMinMs + _random.nextInt(_delayMaxMs - _delayMinMs);
        await Future.delayed(Duration(milliseconds: delay));
      }

      dashboard?.finishCycle(
        total: procesados,
        success: exito,
        error: errores,
        skipped: saltados,
      );

      debugPrint(
          '🔄 AutoSync ciclo cerrado: procesados=$procesados '
          'éxito=$exito error=$errores saltados=$saltados');

      // Snapshot histórico TELEMETRIA_HISTORICO: ya NO se escribe desde
      // el cliente. La Cloud Function `telemetriaSnapshotScheduled`
      // corre cada 6 horas y lo hace server-side via Admin SDK.
      // Las rules de TELEMETRIA_HISTORICO quedaron en `write: if false`,
      // así que cualquier intento desde acá fallaría con
      // permission-denied.
    } catch (e) {
      debugPrint('❌ AutoSync ciclo falló: $e');
      dashboard?.failCycle(e.toString());
    } finally {
      _running = false;
    }
  }
}

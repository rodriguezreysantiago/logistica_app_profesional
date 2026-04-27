import 'dart:collection';
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'vehiculo_repository.dart';
import 'volvo_api_service.dart';

class VehiculoManager {
  final VehiculoRepository _repo;
  final VolvoApiService _api;

  VehiculoManager(this._repo, this._api);

  final Set<String> _sincronizando = {};

  // 🔥 LIMITADOR DE CONCURRENCIA
  final int _maxConcurrent = 5;
  int _currentRunning = 0;

  // 🔥 RATE LIMIT (200–500 ms)
  final int _minDelayMs = 200;
  final int _maxDelayMs = 500;
  final Random _random = Random();

  // 🔥 cola tipada correctamente
  final Queue<Future<void> Function()> _queue = Queue();

  List<dynamic> cacheVolvo = [];

  // ================================
  // INIT / CACHE
  // ================================
  Future<void> precargarDatosVolvo() async {
    try {
      cacheVolvo = await _repo.traerFlotaVolvo();
      debugPrint("📦 Cache Volvo cargada: ${cacheVolvo.length} unidades");
    } catch (e) {
      debugPrint("⚠️ Error cargando cache Volvo: $e");
      cacheVolvo = [];
    }
  }

  // ================================
  // 🔥 SYNC CENTRAL (CON POOL + RATE LIMIT)
  // ================================
  Future<void> sincronizarUnidadIndividual(
    String patente,
    String vin,
  ) async {
    if (_sincronizando.contains(patente)) return;

    final completer = Completer<void>();

    _queue.add(() async {
      try {
        await _executeSync(patente, vin);
        completer.complete();
      } catch (e) {
        completer.completeError(e);
      }
    });

    _processQueue();

    return completer.future;
  }

  void _processQueue() {
    while (_currentRunning < _maxConcurrent && _queue.isNotEmpty) {
      final task = _queue.removeFirst();
      _currentRunning++;

      _runWithDelay(task);
    }
  }

  void _runWithDelay(Future<void> Function() task) async {
    // 🔥 delay random anti-rate-limit
    final delay = _minDelayMs +
        _random.nextInt(_maxDelayMs - _minDelayMs + 1);

    await Future.delayed(Duration(milliseconds: delay));

    task().whenComplete(() {
      _currentRunning--;
      _processQueue();
    });
  }

  Future<void> _executeSync(String patente, String vin) async {
    _sincronizando.add(patente);

    final cleanVin = vin.trim().toUpperCase();

    try {
      double? metros;

      // 1️⃣ CACHE LOCAL
      metros = _buscarEnCache(cleanVin);

      // 2️⃣ REPO
      metros ??= await _repo.traerKmDesdeApi(cleanVin);

      // 3️⃣ FALLBACK API
      metros ??= await _api.traerKilometrajeCualquierVia(cleanVin);

      if (metros == null || metros <= 0) {
        debugPrint("ℹ️ $patente sin datos válidos");
        return;
      }

      final km = metros / 1000;

      await _repo.actualizarKilometraje(
        patente: patente,
        km: km,
      );

      debugPrint("✅ Sync OK $patente → ${km.toStringAsFixed(1)} km");
    } catch (e, stack) {
      debugPrint("❌ Sync error $patente: $e");
      debugPrint(stack.toString());
      rethrow;
    } finally {
      _sincronizando.remove(patente);
    }
  }

  // ================================
  // CACHE
  // ================================
  double? _buscarEnCache(String vin) {
    try {
      final v = cacheVolvo.firstWhere(
        (e) => (e['vin'] ?? '').toString().toUpperCase() == vin,
      );

      final value =
          v['hrTotalVehicleDistance'] ?? v['lastKnownOdometer'];

      if (value == null) return null;

      return (value as num).toDouble();
    } catch (_) {
      return null;
    }
  }

  // ================================
  // ESTADO
  // ================================
  bool estaSincronizando(String patente) {
    return _sincronizando.contains(patente);
  }
}
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/vehiculo_manager.dart';
import '../services/vehiculo_repository.dart';

class VehiculoProvider extends ChangeNotifier {
  // 🔥 MUTABLES (para ProxyProvider)
  late VehiculoManager manager;
  late VehiculoRepository repository;

  VehiculoProvider({
    required this.manager,
    required this.repository,
  });

  // ================= INIT =================

  bool _initialized = false;
  bool _initializing = false;

  Future<void> init() async {
    if (_initialized || _initializing) return;

    _initializing = true;

    try {
      await manager.precargarDatosVolvo();
      _initialized = true;
      debugPrint("✅ Provider inicializado");
    } catch (e) {
      debugPrint("⚠️ Error init provider: $e");
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  // ================= STREAM =================

  Stream<QuerySnapshot> getVehiculosPorTipo(String tipo) {
    return repository.getVehiculosPorTipo(tipo);
  }

  // ================= ESTADO =================

  final Set<String> _loading = {};
  final Set<String> _success = {};
  final Map<String, String> _error = {};

  bool isLoading(String p) => _loading.contains(p);
  bool isSuccess(String p) => _success.contains(p);
  String? getError(String p) => _error[p];

  void clearEstado(String p) {
    _loading.remove(p);
    _success.remove(p);
    _error.remove(p);
    notifyListeners();
  }

  void clearAll() {
    _loading.clear();
    _success.clear();
    _error.clear();
    _lastSync.clear();
    notifyListeners();
  }

  // ================= CONTROL INTELIGENTE =================

  final Map<String, DateTime> _lastSync = {};

  bool debeSincronizar(String patente) {
    final last = _lastSync[patente];
    if (last == null) return true;

    return DateTime.now().difference(last).inMinutes > 5;
  }

  void marcarSync(String patente) {
    _lastSync[patente] = DateTime.now();

    // 🔥 limpieza automática (evita crecimiento infinito)
    if (_lastSync.length > 500) {
      final keys = _lastSync.keys.take(100).toList();
      for (final k in keys) {
        _lastSync.remove(k);
      }
    }
  }

  // ================= SYNC =================

  Future<void> sync(String patente, String vin) async {
    // 🔥 doble protección
    if (_loading.contains(patente)) return;
    if (!debeSincronizar(patente)) return;

    _loading.add(patente);
    _success.remove(patente);
    _error.remove(patente);
    notifyListeners();

    try {
      await manager.sincronizarUnidadIndividual(patente, vin);

      _success.add(patente);
      marcarSync(patente);

      debugPrint("🚀 Sync OK provider: $patente");

      // 🔥 limpiar success automáticamente (UX limpia)
      Future.delayed(const Duration(seconds: 3), () {
        _success.remove(patente);
        notifyListeners();
      });

    } catch (e) {
      _error[patente] = e.toString();
      debugPrint("⚠️ Error sync $patente: $e");

      // 🔥 limpiar error automático
      Future.delayed(const Duration(seconds: 5), () {
        _error.remove(patente);
        notifyListeners();
      });

    } finally {
      _loading.remove(patente);
      notifyListeners();
    }
  }
}
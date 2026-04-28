import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'volvo_api_service.dart';

class VehiculoRepository {
  final FirebaseFirestore _db;
  final VolvoApiService _api;

  VehiculoRepository({
    FirebaseFirestore? firestore,
    VolvoApiService? api,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _api = api ?? VolvoApiService();

  // ================= COLLECTION =================

  static const String collection = 'VEHICULOS';

  // ================= STREAM CACHE =================

  final Map<String, Stream<QuerySnapshot>> _streamsCache = {};

  Stream<QuerySnapshot> getVehiculosPorTipo(String tipo) {
    return _streamsCache.putIfAbsent(
      tipo,
      () => _db
          .collection(collection)
          .where('TIPO', isEqualTo: tipo)
          .snapshots(),
    );
  }

  Stream<QuerySnapshot> getVehiculosPorTipos(List<String> tipos) {
    final key = tipos.join(',');

    return _streamsCache.putIfAbsent(
      key,
      () => _db
          .collection(collection)
          .where('TIPO', whereIn: tipos)
          .snapshots(),
    );
  }

  // 🔥 opcional: limpieza manual de cache
  void clearStreamCache() {
    _streamsCache.clear();
  }

  // ================= FIRESTORE =================

  Future<void> actualizarKilometraje({
    required String patente,
    required double km,
  }) async {
    await _db.collection(collection).doc(patente).update({
      'KM_ACTUAL': km,
      'ULTIMA_SINCRO': FieldValue.serverTimestamp(),
      'SINCRO_TIPO': 'AUTO',
    });
  }

  Future<void> actualizarCampos({
    required String patente,
    required Map<String, dynamic> data,
  }) async {
    await _db.collection(collection).doc(patente).update(data);
  }

  Future<void> actualizarEstado(String patente, String estado) async {
    await _db.collection(collection).doc(patente).update({
      'ESTADO': estado,
    });
  }

  // ================= PAGINACIÓN =================

  /// Trae vehículos paginados ordenados por patente (ID del documento).
  /// Pasar [lastDocument] para traer la siguiente página.
  Future<QuerySnapshot> getPaginados({
    required int limit,
    DocumentSnapshot? lastDocument,
  }) async {
    Query query =
        _db.collection(collection).orderBy(FieldPath.documentId).limit(limit);

    if (lastDocument != null) {
      query = query.startAfterDocument(lastDocument);
    }

    return await query.get();
  }

  // ================= VOLVO CACHE =================

  List<dynamic>? _cacheVolvo;
  DateTime? _lastFetchVolvo;

  /// Si hay un fetch en curso, los callers concurrentes esperan al MISMO
  /// future en lugar de hacer polling con Future.delayed. Esto elimina el
  /// busy-loop y previene race conditions.
  Completer<List<dynamic>>? _inFlightFetch;

  /// Trae la flota de Volvo con cache de 5 minutos.
  /// Si dos llamadas concurrentes llegan a la vez, ambas reciben el mismo
  /// resultado (single-flight pattern).
  Future<List<dynamic>> traerFlotaVolvo() async {
    // 1) Cache válido (< 5 min) → devolver de inmediato.
    if (_cacheVolvo != null &&
        _lastFetchVolvo != null &&
        DateTime.now().difference(_lastFetchVolvo!).inMinutes < 5) {
      return _cacheVolvo!;
    }

    // 2) Hay un fetch en curso → engancharse al mismo future.
    final inFlight = _inFlightFetch;
    if (inFlight != null) {
      return inFlight.future;
    }

    // 3) Disparar nuevo fetch y guardarlo como "in flight".
    final completer = Completer<List<dynamic>>();
    _inFlightFetch = completer;

    try {
      final data = await _api.traerDatosFlota();
      _cacheVolvo = data;
      _lastFetchVolvo = DateTime.now();
      completer.complete(data);
      return data;
    } catch (e) {
      // Ante error, devolvemos el cache anterior si existe.
      // Importante: NO completamos el completer con error (para que las
      // llamadas concurrentes tampoco fallen).
      final fallback = _cacheVolvo ?? <dynamic>[];
      completer.complete(fallback);
      return fallback;
    } finally {
      _inFlightFetch = null;
    }
  }

  // ================= API KM =================

  Future<double?> traerKmDesdeApi(String vin) async {
    try {
      return await _api.traerKilometrajeCualquierVia(vin);
    } catch (_) {
      return null;
    }
  }
}
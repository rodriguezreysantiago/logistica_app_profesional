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

  // ================= VOLVO CACHE =================

  List<dynamic>? _cacheVolvo;
  DateTime? _lastFetchVolvo;
  bool _fetchingVolvo = false;

  Future<List<dynamic>> traerFlotaVolvo() async {
    // 🔥 evita requests simultáneos
    if (_fetchingVolvo) {
      while (_fetchingVolvo) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      return _cacheVolvo ?? [];
    }

    // 🔥 cache 5 min
    if (_cacheVolvo != null &&
        _lastFetchVolvo != null &&
        DateTime.now().difference(_lastFetchVolvo!).inMinutes < 5) {
      return _cacheVolvo!;
    }

    try {
      _fetchingVolvo = true;

      final data = await _api.traerDatosFlota();

      _cacheVolvo = data;
      _lastFetchVolvo = DateTime.now();

      return data;
    } catch (e) {
      return _cacheVolvo ?? [];
    } finally {
      _fetchingVolvo = false;
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
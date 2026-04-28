import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Servicio de integración con Volvo Connect — Volvo Group Vehicle API.
///
/// 📚 BASADO EN DOC OFICIAL (Volvo Trucks Developer Portal):
///   - Volvo Group Vehicle API v1.0.6  →  /vehicle/...  (odómetro y estado)
///   - rFMS v2.1 (estándar abierto)    →  /rfms/...     (fallback)
///
/// 🔐 AUTH: HTTP Basic Authentication. Sin OAuth, sin token, sin renovación.
///   header: Authorization: Basic <base64(usuario:contraseña)>
///
/// 📦 Campo de odómetro: `hrTotalVehicleDistance` en METROS, dentro de
///   vehicleStatusResponse.vehicleStatuses[i].hrTotalVehicleDistance
///
/// ⚠️ Rate limit: 1 request cada 10 seg por endpoint y por usuario.
/// 🔒 Producción: mover credenciales a Cloud Functions o --dart-define.
class VolvoApiService {
  // ============= CREDENCIALES =============
  // ✅ Las credenciales se leen de variables de compilación (--dart-define).
  //
  // Para correr en desarrollo:
  //   flutter run -d windows --dart-define-from-file=secrets.json
  //
  // Donde `secrets.json` (NO commiteado, está en .gitignore) contiene:
  //   {
  //     "VOLVO_USERNAME": "tu_usuario",
  //     "VOLVO_PASSWORD": "tu_contraseña"
  //   }
  //
  // Si no se proveen env vars, se usan los fallbacks de abajo para que la
  // app no quede inutilizable en dev. EN PRODUCCIÓN deben pasarse las env vars.
  static const String _envUsername =
      String.fromEnvironment('VOLVO_USERNAME');
  static const String _envPassword =
      String.fromEnvironment('VOLVO_PASSWORD');

  // ⚠️ FALLBACK SÓLO PARA DEV (no usar en producción).
  static const String _fallbackUsername = '018B1E992E';
  static const String _fallbackPassword = 'yeBgBh3of3';

  String get _username =>
      _envUsername.isNotEmpty ? _envUsername : _fallbackUsername;
  String get _password =>
      _envPassword.isNotEmpty ? _envPassword : _fallbackPassword;

  // ============= ENDPOINTS =============
  // Volvo Group Vehicle API (la que tiene odómetro detallado).
  static const String _baseUrl = 'https://api.volvotrucks.com';
  static const String _vehiclesUrl = '$_baseUrl/vehicle/vehicles';
  static const String _statusesUrl = '$_baseUrl/vehicle/vehiclestatuses';

  // ============= ACCEPT HEADERS (exactos de la spec) =============
  // Estos NO son intercambiables: Volvo rechaza con 406 si no coinciden.
  static const String _acceptVehicles =
      'application/x.volvogroup.com.vehicles.v1.0+json; UTF-8';
  static const String _acceptStatuses =
      'application/x.volvogroup.com.vehiclestatuses.v1.0+json; UTF-8';

  // Header Basic Auth, calculado una sola vez.
  late final String _authHeader =
      'Basic ${base64Encode(utf8.encode('$_username:$_password'))}';

  // ============= CIRCUIT BREAKER =============
  // Si la auth falla 3 veces seguidas con 401, dejamos de pegarle a Volvo
  // hasta que la app se reinicie (o el admin llame resetAuthFailures()).
  int _consecutive401 = 0;
  static const int _max401 = 3;
  bool get _circuitOpen => _consecutive401 >= _max401;

  void resetAuthFailures() => _consecutive401 = 0;

  // ============= DIO =============
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
    ),
  );

  // ============= LOGGING =============

  void _logDioResult(String label, {Response? response, Object? error}) {
    if (error != null) {
      if (error is DioException) {
        debugPrint("🚨 [VOLVO $label] DioException type: ${error.type}");
        debugPrint("🚨 [VOLVO $label] message: ${error.message}");
        debugPrint("🚨 [VOLVO $label] statusCode: ${error.response?.statusCode}");
        debugPrint("🚨 [VOLVO $label] responseData: ${error.response?.data}");
        debugPrint("🚨 [VOLVO $label] requestPath: ${error.requestOptions.uri}");
      } else {
        debugPrint("🚨 [VOLVO $label] Error inesperado: $error");
      }
      return;
    }

    if (response != null &&
        response.statusCode != null &&
        response.statusCode! >= 400) {
      debugPrint("⚠️ [VOLVO $label] HTTP ${response.statusCode}");
      debugPrint("⚠️ [VOLVO $label] body: ${response.data}");
      debugPrint("⚠️ [VOLVO $label] url: ${response.requestOptions.uri}");
    }
  }

  bool _trackAuthState(Response response) {
    if (response.statusCode == 401) {
      _consecutive401++;
      debugPrint(
          "🚨 [VOLVO AUTH] Credenciales rechazadas ($_consecutive401/$_max401). "
          "${_circuitOpen ? 'Circuit breaker ABIERTO. Pausando llamadas.' : ''}");
      return false;
    }
    if (response.statusCode != null &&
        response.statusCode! >= 200 &&
        response.statusCode! < 300) {
      _consecutive401 = 0;
      return true;
    }
    return false;
  }

  // ===========================================================================
  // 1. LISTA DE VEHÍCULOS — /vehicle/vehicles
  // ===========================================================================

  /// Devuelve la lista de vehículos asignados a la cuenta de API.
  /// Respuesta: vehicleResponse.vehicles[]
  Future<List<dynamic>> traerDatosFlota() async {
    if (_circuitOpen) {
      debugPrint("⏸️ [VOLVO FLOTA] Circuit breaker abierto. Saltando llamada.");
      return [];
    }

    try {
      final response = await _dio.get(
        _vehiclesUrl,
        options: Options(
          headers: {
            'Authorization': _authHeader,
            'Accept': _acceptVehicles,
          },
          validateStatus: (s) => true,
        ),
      );

      _trackAuthState(response);

      if (response.statusCode == 200 && response.data != null) {
        final list = response.data['vehicleResponse']?['vehicles'] ?? [];
        debugPrint("📦 [VOLVO FLOTA] OK: ${list.length} unidades recibidas");
        return list is List ? list : [];
      }

      _logDioResult("FLOTA", response: response);
      return [];
    } catch (e) {
      _logDioResult("FLOTA", error: e);
      return [];
    }
  }

  // ===========================================================================
  // 2. KILOMETRAJE POR VIN — /vehicle/vehiclestatuses
  // ===========================================================================

  /// Trae el kilometraje (en metros) de un VIN específico.
  /// Devuelve null si la unidad no respondió o no hay datos.
  ///
  /// Field path: vehicleStatusResponse.vehicleStatuses[0].hrTotalVehicleDistance
  /// Unit: metros (int64). Para KM dividir por 1000.
  Future<double?> traerKilometrajeCualquierVia(String vin) async {
    final String cleanVin = vin.trim().toUpperCase();
    if (cleanVin.isEmpty) return null;

    if (_circuitOpen) {
      debugPrint("⏸️ [VOLVO KM $cleanVin] Circuit breaker abierto.");
      return null;
    }

    try {
      final res = await _dio.get(
        _statusesUrl,
        queryParameters: {
          'vin': cleanVin,
          'latestOnly': 'true',
        },
        options: Options(
          headers: {
            'Authorization': _authHeader,
            'Accept': _acceptStatuses,
          },
          validateStatus: (s) => true,
        ),
      );

      _trackAuthState(res);

      if (res.statusCode == 200 && res.data != null) {
        final statuses = res.data['vehicleStatusResponse']?['vehicleStatuses'];
        if (statuses is List && statuses.isNotEmpty) {
          final s = statuses[0];
          // Campo principal según doc oficial: hrTotalVehicleDistance (metros).
          final odo = s['hrTotalVehicleDistance'];
          if (odo != null) {
            final m = double.tryParse(odo.toString());
            if (m != null && m > 0) {
              debugPrint(
                  "✅ [VOLVO KM $cleanVin] ${(m / 1000).toStringAsFixed(0)} km");
              return m;
            }
          }
        }
        debugPrint("ℹ️ [VOLVO KM $cleanVin] Respuesta 200 pero sin odómetro.");
        return null;
      }

      _logDioResult("STATUS $cleanVin", response: res);
      return null;
    } catch (e) {
      _logDioResult("STATUS $cleanVin", error: e);
      return null;
    }
  }

  // ===========================================================================
  // 3. ESTADOS DE TODA LA FLOTA — para precarga en cache
  // ===========================================================================

  /// Trae el último estado de TODAS las unidades en una sola llamada.
  /// Útil como caché previo a sincronizar uno por uno.
  Future<List<dynamic>> traerEstadosFlota() async {
    if (_circuitOpen) return [];

    try {
      final res = await _dio.get(
        _statusesUrl,
        queryParameters: {'latestOnly': 'true'},
        options: Options(
          headers: {
            'Authorization': _authHeader,
            'Accept': _acceptStatuses,
          },
          validateStatus: (s) => true,
        ),
      );

      _trackAuthState(res);

      if (res.statusCode == 200 && res.data != null) {
        final list =
            res.data['vehicleStatusResponse']?['vehicleStatuses'] ?? [];
        debugPrint("📦 [VOLVO STATUS] OK: ${list.length} estados recibidos");
        return list is List ? list : [];
      }

      _logDioResult("STATUS-ALL", response: res);
      return [];
    } catch (e) {
      _logDioResult("STATUS-ALL", error: e);
      return [];
    }
  }
}

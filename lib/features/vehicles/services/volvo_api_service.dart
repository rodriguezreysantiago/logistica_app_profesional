import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Resultado de un request de diagnóstico contra Volvo. Pensado para
/// inspeccionar visualmente qué viene en el response cuando algo no
/// se está parseando como esperamos.
class VolvoDiagnostico {
  final int? statusCode;
  final String? statusMessage;
  final dynamic rawBody; // Map o String según el response
  final String? errorMessage;
  final Duration duracion;
  final String urlConsultada;

  const VolvoDiagnostico({
    required this.statusCode,
    required this.statusMessage,
    required this.rawBody,
    required this.errorMessage,
    required this.duracion,
    required this.urlConsultada,
  });

  bool get fueExitoso =>
      errorMessage == null && statusCode != null && statusCode! < 400;
}

/// Snapshot de telemetría de un vehículo, sacado de un solo request a
/// `/vehicle/vehiclestatuses`. Cualquier campo puede venir `null` si el
/// vehículo no lo reporta (típico en marcas no-Volvo o unidades viejas).
class VolvoTelemetria {
  /// Odómetro acumulado en metros. Para KM dividir entre 1000.
  final double? odometroMetros;

  /// Nivel de combustible 0..100. Lo entrega Volvo en porcentaje.
  final double? nivelCombustiblePct;

  /// Autonomía estimada en kilómetros que el vehículo puede recorrer
  /// con el combustible actual antes de quedarse vacío.
  final double? autonomiaKm;

  /// Timestamp del snapshot que recibimos del vehículo (no del momento
  /// en que llamamos al API).
  final DateTime? leidoEn;

  const VolvoTelemetria({
    this.odometroMetros,
    this.nivelCombustiblePct,
    this.autonomiaKm,
    this.leidoEn,
  });

  /// True cuando el response trajo al menos un dato útil.
  bool get tieneAlgunDato =>
      odometroMetros != null ||
      nivelCombustiblePct != null ||
      autonomiaKm != null;
}

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
  // Las credenciales se leen ÚNICAMENTE de variables de compilación
  // (`--dart-define`). Nunca se hardcodean ni se compilan en el binario:
  // si lo hicieran, cualquiera que descomprima el APK las obtendría.
  //
  // Para correr en desarrollo:
  //   flutter run --dart-define-from-file=secrets.json
  //
  // `secrets.json` (NO commiteado — está en .gitignore) contiene:
  //   {
  //     "VOLVO_USERNAME": "tu_usuario",
  //     "VOLVO_PASSWORD": "tu_contraseña"
  //   }
  //
  // En producción las env vars deben inyectarse desde el pipeline de build
  // (CI/CD), preferentemente migrando el flujo a una Cloud Function que
  // actúe como proxy y mantenga las credenciales server-side.
  static const String _envUsername =
      String.fromEnvironment('VOLVO_USERNAME');
  static const String _envPassword =
      String.fromEnvironment('VOLVO_PASSWORD');

  String get _username => _envUsername;
  String get _password => _envPassword;

  bool get _hasCredentials =>
      _envUsername.isNotEmpty && _envPassword.isNotEmpty;

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

  // Header Basic Auth, calculado una sola vez. Si las credenciales no
  // fueron inyectadas vía --dart-define, dejamos un valor vacío y los
  // requests devuelven [] sin pegarle a Volvo (ver guard `_hasCredentials`).
  late final String _authHeader = _hasCredentials
      ? 'Basic ${base64Encode(utf8.encode('$_username:$_password'))}'
      : '';

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
    if (!_hasCredentials) {
      debugPrint(
          "⚠️ [VOLVO FLOTA] Sin credenciales (faltan VOLVO_USERNAME / VOLVO_PASSWORD en --dart-define).");
      return [];
    }
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

    if (!_hasCredentials) {
      debugPrint(
          "⚠️ [VOLVO KM $cleanVin] Sin credenciales — saltando llamada.");
      return null;
    }
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
  // 2.b TELEMETRÍA COMPLETA POR VIN — /vehicle/vehiclestatuses
  // ===========================================================================
  //
  // Mismo endpoint que `traerKilometrajeCualquierVia`, pero parsea más
  // campos del response (combustible y autonomía) sin generar requests
  // adicionales. Cuesta lo mismo en términos de rate limit.

  /// Trae odómetro + nivel de combustible + autonomía estimada de un VIN
  /// en una sola llamada. Devuelve un [VolvoTelemetria] vacío si la
  /// unidad no respondió o no hay credenciales.
  Future<VolvoTelemetria> traerTelemetria(String vin) async {
    final String cleanVin = vin.trim().toUpperCase();
    if (cleanVin.isEmpty) return const VolvoTelemetria();

    if (!_hasCredentials) {
      debugPrint(
          "⚠️ [VOLVO TELE $cleanVin] Sin credenciales — saltando llamada.");
      return const VolvoTelemetria();
    }
    if (_circuitOpen) {
      debugPrint("⏸️ [VOLVO TELE $cleanVin] Circuit breaker abierto.");
      return const VolvoTelemetria();
    }

    try {
      final res = await _dio.get(
        _statusesUrl,
        queryParameters: {
          'vin': cleanVin,
          'latestOnly': 'true',
          // CRÍTICO: sin este parámetro la API devuelve solo el snapshot
          // base (odómetro, posición) y OMITE fuelLevel + estimatedDistance.
          // Con VOLVOGROUPSNAPSHOT vienen los campos del grupo Volvo.
          'additionalContent': 'VOLVOGROUPSNAPSHOT',
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
          final tele = _parseStatus(statuses[0]);
          if (tele.tieneAlgunDato) {
            debugPrint(
                "✅ [VOLVO TELE $cleanVin] km=${tele.odometroMetros != null ? (tele.odometroMetros! / 1000).toStringAsFixed(0) : '?'} "
                "fuel=${tele.nivelCombustiblePct?.toStringAsFixed(0) ?? '?'}% "
                "auton=${tele.autonomiaKm?.toStringAsFixed(0) ?? '?'}km");
            return tele;
          }
        }
        debugPrint(
            "ℹ️ [VOLVO TELE $cleanVin] Respuesta 200 pero sin datos útiles.");
        return const VolvoTelemetria();
      }

      _logDioResult("TELE $cleanVin", response: res);
      return const VolvoTelemetria();
    } catch (e) {
      _logDioResult("TELE $cleanVin", error: e);
      return const VolvoTelemetria();
    }
  }

  /// Parser de un objeto `vehicleStatuses[i]` del response oficial.
  ///
  /// La estructura real del response (verificada con un VIN diésel +
  /// `additionalContent=VOLVOGROUPSNAPSHOT`) es:
  ///
  /// ```
  /// vehicleStatuses[i] = {
  ///   hrTotalVehicleDistance: <metros>,             // odómetro
  ///   snapshotData: {
  ///     fuelLevel1: <0-100>,                        // % combustible
  ///     volvoGroupSnapshot: {
  ///       estimatedDistanceToEmpty: {
  ///         fuel: <metros>, gas: <metros>           // autonomía por fuente
  ///       }
  ///     }
  ///   }
  /// }
  /// ```
  ///
  /// El parser igual probará paths "legacy" (sin snapshotData) por si una
  /// versión vieja del API los aplana al primer nivel.
  VolvoTelemetria _parseStatus(dynamic raw) {
    if (raw is! Map) return const VolvoTelemetria();

    // 1) Odómetro (metros). Está al primer nivel del status.
    final odo = _toDouble(raw['hrTotalVehicleDistance']);

    final snap = raw['snapshotData'];
    final volvoSnap = (snap is Map) ? snap['volvoGroupSnapshot'] : null;

    // 2) Nivel de combustible — buscar en orden, primero el path real
    //    confirmado, después fallbacks.
    double? fuel;
    if (snap is Map) fuel = _toDouble(snap['fuelLevel1']);
    if (fuel == null) {
      final fuelObj = raw['fuelLevel'];
      if (fuelObj is Map) fuel = _toDouble(fuelObj['fuelLevel1']);
    }
    fuel ??= _toDouble(raw['fuelLevel1']);

    // 3) Autonomía — el path real es snapshotData.volvoGroupSnapshot
    //    .estimatedDistanceToEmpty.{fuel|total|gas|batteryPack} en metros.
    //    Probamos varios contenedores por compatibilidad.
    final autonMetros = _extraerAutonomiaMetros(raw, snap, volvoSnap);
    final autonKm = autonMetros != null ? autonMetros / 1000 : null;

    // 4) Timestamp del snapshot.
    DateTime? leidoEn;
    final ts = raw['receivedDateTime'] ?? raw['createdDateTime'];
    if (ts is String) {
      leidoEn = DateTime.tryParse(ts);
    }

    return VolvoTelemetria(
      odometroMetros: (odo != null && odo > 0) ? odo : null,
      nivelCombustiblePct:
          (fuel != null && fuel >= 0 && fuel <= 100) ? fuel : null,
      autonomiaKm: (autonKm != null && autonKm >= 0) ? autonKm : null,
      leidoEn: leidoEn,
    );
  }

  /// Extrae `estimatedDistanceToEmpty` (en metros) recorriendo todos los
  /// contenedores posibles. Devuelve null si ninguno tiene valor útil.
  double? _extraerAutonomiaMetros(Map raw, dynamic snap, dynamic volvoSnap) {
    // Lista de Maps donde puede estar el objeto estimatedDistanceToEmpty.
    final candidatos = <Map>[
      if (volvoSnap is Map) volvoSnap, // ← path real confirmado para diésel
      if (snap is Map) snap,
      raw,
    ];

    // Bonus: contenedores específicos de vehículos eléctricos/híbridos.
    for (final c in const [
      'chargingStatusInfo',
      'volvoGroupChargingStatusInfo',
      'batteryPackInfo',
    ]) {
      final container = raw[c];
      if (container is Map) candidatos.add(container);
    }

    for (final container in candidatos) {
      final edte = container['estimatedDistanceToEmpty'];
      if (edte is Map) {
        // Probamos campos en orden de preferencia. La doc nueva usa
        // {fuel, gas, batteryPack} sin `total`; la doc vieja tiene `total`.
        final v = _toDouble(edte['total']) ??
            _toDouble(edte['fuel']) ??
            _toDouble(edte['batteryPack']) ??
            _toDouble(edte['gas']);
        if (v != null && v > 0) return v;
      } else if (edte is num) {
        // Edge case: algunos responses lo aplanan a número directo.
        return edte.toDouble();
      }
    }
    return null;
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  // ===========================================================================
  // DIAGNÓSTICO — request crudo para inspección manual
  // ===========================================================================

  /// Hace el mismo request que `traerTelemetria` pero devuelve el response
  /// completo sin parsear. Para usar desde una pantalla de admin cuando
  /// algún campo no aparece y necesitamos ver qué viene literalmente.
  Future<VolvoDiagnostico> diagnosticarStatus(String vin) async {
    final cleanVin = vin.trim().toUpperCase();
    final url = '$_statusesUrl?vin=$cleanVin&latestOnly=true'
        '&additionalContent=VOLVOGROUPSNAPSHOT';

    if (cleanVin.isEmpty) {
      return VolvoDiagnostico(
        statusCode: null,
        statusMessage: null,
        rawBody: null,
        errorMessage: 'VIN vacío.',
        duracion: Duration.zero,
        urlConsultada: url,
      );
    }
    if (!_hasCredentials) {
      return VolvoDiagnostico(
        statusCode: null,
        statusMessage: null,
        rawBody: null,
        errorMessage:
            'Faltan credenciales (VOLVO_USERNAME / VOLVO_PASSWORD en --dart-define).',
        duracion: Duration.zero,
        urlConsultada: url,
      );
    }

    final stopwatch = Stopwatch()..start();
    try {
      final res = await _dio.get(
        _statusesUrl,
        queryParameters: {
          'vin': cleanVin,
          'latestOnly': 'true',
          'additionalContent': 'VOLVOGROUPSNAPSHOT',
        },
        options: Options(
          headers: {
            'Authorization': _authHeader,
            'Accept': _acceptStatuses,
          },
          validateStatus: (s) => true,
        ),
      );
      stopwatch.stop();
      _trackAuthState(res);
      return VolvoDiagnostico(
        statusCode: res.statusCode,
        statusMessage: res.statusMessage,
        rawBody: res.data,
        errorMessage: null,
        duracion: stopwatch.elapsed,
        urlConsultada: url,
      );
    } catch (e) {
      stopwatch.stop();
      return VolvoDiagnostico(
        statusCode: null,
        statusMessage: null,
        rawBody: null,
        errorMessage: e.toString(),
        duracion: stopwatch.elapsed,
        urlConsultada: url,
      );
    }
  }

  // ===========================================================================
  // 3. ESTADOS DE TODA LA FLOTA — para precarga en cache
  // ===========================================================================

  /// Trae el último estado de TODAS las unidades en una sola llamada.
  /// Útil como caché previo a sincronizar uno por uno.
  Future<List<dynamic>> traerEstadosFlota() async {
    if (!_hasCredentials) {
      debugPrint("⚠️ [VOLVO STATUS-ALL] Sin credenciales — saltando llamada.");
      return [];
    }
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

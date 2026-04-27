import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart'; 

class VolvoApiService {
  // ⚠️ MENTOR WARNING: NUNCA dejes credenciales en código cliente en producción real.
  // Para la V2, migrar esto a Firebase Cloud Functions o Google Cloud Secret Manager.
  final String _clientId = '018B1E992E';
  final String _clientSecret = 'yeBgBh3of3';
  
  // ✅ MEJORA PRO: Endpoints separados para Autorización y Datos
  final String _authUrl = 'https://api.volvotrucks.com/oauth2/token'; // O la URL de autenticación específica de tu contrato
  final String _baseUrl = 'https://api.volvotrucks.com';
  
  // Caché del token para no pedirlo en cada consulta
  String? _accessToken;
  DateTime? _tokenExpiry;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 4), // Le damos 1s más por si la red fluctúa
      receiveTimeout: const Duration(seconds: 4),
      sendTimeout: const Duration(seconds: 4),
    ),
  );

  // ===========================================================================
  // 1. MOTOR DE AUTENTICACIÓN (OAUTH 2.0)
  // ===========================================================================
  
  Future<String?> _getValidToken() async {
    // Si tenemos un token y todavía le faltan más de 5 minutos para vencer, lo reusamos.
    if (_accessToken != null && _tokenExpiry != null && _tokenExpiry!.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      return _accessToken;
    }

    try {
      final String authHeader = 'Basic ${base64Encode(utf8.encode('$_clientId:$_clientSecret'))}';
      
      final response = await _dio.post(
        _authUrl,
        data: {'grant_type': 'client_credentials'},
        options: Options(
          headers: {
            'Authorization': authHeader,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        ),
      );

      if (response.statusCode == 200 && response.data['access_token'] != null) {
        _accessToken = response.data['access_token'];
        // Generalmente duran 3600 segundos (1 hora)
        int expiresIn = response.data['expires_in'] ?? 3600;
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));
        return _accessToken;
      }
    } catch (e) {
      debugPrint("🚨 [VOLVO AUTH] Error obteniendo Token: $e");
    }
    return null;
  }

  // ===========================================================================
  // 2. CONSULTAS A LA API
  // ===========================================================================

  Future<List<dynamic>> traerDatosFlota() async {
    final token = await _getValidToken();
    if (token == null) return []; // Fallo de autorización

    try {
      final response = await _dio.get(
        '$_baseUrl/vehicle/vehiclestatuses',
        queryParameters: {'latestOnly': 'true', 'itemsPerPage': 100},
        options: Options(headers: {
          'Authorization': 'Bearer $token', // ✅ USAMOS EL TOKEN, NO LAS CREDENCIALES CRUDAS
          'Accept': 'application/x.volvogroup.com.vehiclestatuses.v1.0+json'
        }),
      );
      return response.data['vehicleStatusResponse']['vehicleStatuses'] ?? [];
    } catch (e) { 
      debugPrint("📡 [INFO] Flota completa no disponible (Timeout/Offline)");
      return []; 
    }
  }

  Future<double?> traerKilometrajeCualquierVia(String vin) async {
    final String cleanVin = vin.trim().toUpperCase();
    if (cleanVin.isEmpty) return null;
    
    final token = await _getValidToken();
    if (token == null) return null;

    final Map<String, String> dataHeaders = {
      'Authorization': 'Bearer $token', // ✅ USAMOS EL TOKEN
      'User-Agent': 'Logistica_App_Profesional/1.0',
    };

    // --- INTENTO 1: ODOMETER ---
    try {
      final res = await _dio.get(
        '$_baseUrl/vehicle/vehicles/$cleanVin/odometer',
        options: Options(
          headers: {
            ...dataHeaders,
            'Accept': 'application/x.volvogroup.com.vehicleodometer.v1.0+json'
          },
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (res.statusCode == 200 && res.data != null) {
        return double.tryParse(res.data['odometerValue'].toString());
      }
    } catch (_) {}

    // --- INTENTO 2: VEHICLE STATUS ---
    try {
      final res = await _dio.get(
        '$_baseUrl/vehicle/vehiclestatuses',
        queryParameters: {'vin': cleanVin, 'latestOnly': 'true'},
        options: Options(
          headers: {
            ...dataHeaders,
            'Accept': 'application/x.volvogroup.com.vehiclestatuses.v1.0+json'
          },
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      
      if (res.statusCode == 200 && res.data != null) {
        final statuses = res.data['vehicleStatusResponse']?['vehicleStatuses'];
        if (statuses != null && statuses is List && statuses.isNotEmpty) {
          final odoData = statuses[0]['lastKnownOdometer'];
          if (odoData != null) return double.tryParse(odoData.toString());
        }
      }
    } catch (_) {}

    // --- INTENTO 3: UTILIZATION (Conversión M -> KM) ---
    try {
      final res = await _dio.get(
        '$_baseUrl/vehicle/vehicles/$cleanVin/utilization',
        options: Options(
          headers: {
            ...dataHeaders,
            'Accept': 'application/x.volvogroup.com.vehicleutilization.v1.0+json'
          },
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (res.statusCode == 200 && res.data != null) {
         final double? metros = double.tryParse(res.data['totalDistance'].toString());
         if (metros != null) {
           return metros / 1000;
         }
      }
    } catch (_) {}

    debugPrint("💤 [OFFLINE] $cleanVin: Sin respuesta telemétrica.");
    return null;
  }
}
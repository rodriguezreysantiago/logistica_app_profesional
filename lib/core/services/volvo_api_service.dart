import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart'; 

class VolvoApiService {
  // ⚠️ MENTOR WARNING: NUNCA dejes credenciales en código cliente en producción real.
  // Para la V2, migrar esto a Firebase Cloud Functions o Google Cloud Secret Manager.
  final String _clientId = '018B1E992E';
  final String _clientSecret = 'yeBgBh3of3';
  final String _baseUrl = 'https://api.volvotrucks.com';
  
  // ✅ MENTOR: Timeout agresivo (3s) para no bloquear la UI si el camión está apagado
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
      sendTimeout: const Duration(seconds: 3),
    ),
  );

  String get _authHeader => 'Basic ${base64Encode(utf8.encode('$_clientId:$_clientSecret'))}';

  Map<String, String> get _baseHeaders => {
    'Authorization': _authHeader,
    'User-Agent': 'Logistica_App_Profesional/1.0',
    'Connection': 'keep-alive',
  };

  Future<List<dynamic>> traerDatosFlota() async {
    try {
      final response = await _dio.get(
        '$_baseUrl/vehicle/vehiclestatuses',
        queryParameters: {'latestOnly': 'true', 'itemsPerPage': 100},
        options: Options(headers: {
          ..._baseHeaders,
          'Accept': 'application/x.volvogroup.com.vehiclestatuses.v1.0+json'
        }),
      );
      return response.data['vehicleStatusResponse']['vehicleStatuses'] ?? [];
    } catch (e) { 
      debugPrint("📡 [INFO] Flota completa no disponible (Timeout/Offline)");
      return []; 
    }
  }

  // ✅ MÉTODO DE RASTREO PROFUNDO (Fallback Chain)
  Future<double?> traerKilometrajeCualquierVia(String vin) async {
    final String cleanVin = vin.trim().toUpperCase();
    if (cleanVin.isEmpty) return null;
    
    // --- INTENTO 1: ODOMETER ---
    try {
      final res = await _dio.get(
        '$_baseUrl/vehicle/vehicles/$cleanVin/odometer',
        options: Options(
          headers: {
            ..._baseHeaders,
            'Accept': 'application/x.volvogroup.com.vehicleodometer.v1.0+json'
          },
          validateStatus: (s) => s != null && s < 500, // ✅ MENTOR: Validación segura
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
            ..._baseHeaders,
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
            ..._baseHeaders,
            'Accept': 'application/x.volvogroup.com.vehicleutilization.v1.0+json'
          },
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (res.statusCode == 200 && res.data != null) {
         final double? metros = double.tryParse(res.data['totalDistance'].toString());
         if (metros != null) {
           return metros / 1000; // ✅ MENTOR: Matemática perfecta
         }
      }
    } catch (_) {}

    // Si la batería del camión está cortada o sin señal
    debugPrint("💤 [OFFLINE] $cleanVin: Sin respuesta telemétrica.");
    return null;
  }
}
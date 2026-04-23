import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart'; 

class VolvoApiService {
  final String clientId = '018B1E992E';
  final String clientSecret = 'yeBgBh3of3';
  final String baseUrl = 'https://api.volvotrucks.com';
  
  // ✅ AJUSTE DE RESILIENCIA: Bajamos a 3 segundos. 
  // Si el camión tiene corriente, la API de Volvo responde en < 1s. 
  // Si no responde en 3s, asumimos que está "cortado" en el depósito.
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
      sendTimeout: const Duration(seconds: 3),
    ),
  );

  String get _authHeader => 'Basic ${base64Encode(utf8.encode('$clientId:$clientSecret'))}';

  Map<String, String> get _baseHeaders => {
    'Authorization': _authHeader,
    'User-Agent': 'Logistica_App_Profesional/1.0',
    'Connection': 'keep-alive',
  };

  Future<List<dynamic>> traerDatosFlota() async {
    try {
      final response = await _dio.get(
        '$baseUrl/vehicle/vehiclestatuses',
        queryParameters: {'latestOnly': 'true', 'itemsPerPage': 100},
        options: Options(headers: {
          ..._baseHeaders,
          'Accept': 'application/x.volvogroup.com.vehiclestatuses.v1.0+json'
        }),
      );
      return response.data['vehicleStatusResponse']['vehicleStatuses'] ?? [];
    } catch (e) { 
      // Error silencioso: si falla la flota completa, devolvemos lista vacía
      debugPrint("📡 [INFO] No se pudo obtener la flota completa (Posible falta de conexión)");
      return []; 
    }
  }

  // ✅ MÉTODO DE RASTREO PROFUNDO: Ahora mucho más rápido y silencioso
  Future<double?> traerKilometrajeCualquierVia(String vin) async {
    final String cleanVin = vin.trim().toUpperCase();
    
    // --- INTENTO 1: ODOMETER ---
    try {
      final res = await _dio.get(
        '$baseUrl/vehicle/vehicles/$cleanVin/odometer',
        options: Options(
          headers: {
            ..._baseHeaders,
            'Accept': 'application/x.volvogroup.com.vehicleodometer.v1.0+json'
          },
          validateStatus: (s) => s! < 500,
        ),
      );
      if (res.statusCode == 200 && res.data != null) {
        return double.tryParse(res.data['odometerValue'].toString());
      }
    } catch (_) {}

    // --- INTENTO 2: VEHICLE STATUS ---
    try {
      final res = await _dio.get(
        '$baseUrl/vehicle/vehiclestatuses',
        queryParameters: {'vin': cleanVin, 'latestOnly': 'true'},
        options: Options(
          headers: {
            ..._baseHeaders,
            'Accept': 'application/x.volvogroup.com.vehiclestatuses.v1.0+json'
          },
          validateStatus: (s) => s! < 500,
        ),
      );
      
      if (res.statusCode == 200 && res.data != null) {
        final statuses = res.data['vehicleStatusResponse']['vehicleStatuses'];
        if (statuses != null && statuses.isNotEmpty) {
          final odoData = statuses[0]['lastKnownOdometer'];
          if (odoData != null) return double.tryParse(odoData.toString());
        }
      }
    } catch (_) {}

    // --- INTENTO 3: UTILIZATION (Basado en el a16.html que pasaste) ---
    // Agregamos este intento porque los datos de utilización suelen estar más disponibles
    try {
      final res = await _dio.get(
        '$baseUrl/vehicle/vehicles/$cleanVin/utilization',
        options: Options(
          headers: {
            ..._baseHeaders,
            'Accept': 'application/x.volvogroup.com.vehicleutilization.v1.0+json'
          },
          validateStatus: (s) => s! < 500,
        ),
      );
      if (res.statusCode == 200 && res.data != null) {
         // Según a16.html, el totalDistance está en metros
         return double.tryParse(res.data['totalDistance'].toString());
      }
    } catch (_) {}

    // Si llegamos acá, no gritamos error, solo informamos
    debugPrint("💤 [OFFLINE] $cleanVin: Sin respuesta eléctrica.");
    return null;
  }
}
import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart'; 

class VolvoApiService {
  final String clientId = '018B1E992E';
  final String clientSecret = 'yeBgBh3of3';
  final String baseUrl = 'https://api.volvotrucks.com';
  
  // ✅ Configuración de Dio Blindada: Tiempos de espera cortos para no trabar hilos
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 8),
    ),
  );

  String get _authHeader => 'Basic ${base64Encode(utf8.encode('$clientId:$clientSecret'))}';

  // ✅ User-Agent Neutro para evitar conflictos de marcas anteriores
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
      debugPrint("❌ Error General Flota: $e");
      return []; 
    }
  }

  // ✅ Método de rastreo profundo con lógica de reintentos silenciosa
  Future<double?> traerKilometrajeCualquierVia(String vin) async {
    final String cleanVin = vin.trim().toUpperCase();
    debugPrint("📡 [API] Rastreo profundo VIN: $cleanVin");
    
    // --- INTENTO 1: ODOMETER (Estándar) ---
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
    } catch (_) {} // Fallo silencioso para pasar al siguiente intento rápidamente

    // --- INTENTO 2: VEHICLE STATUS (SEM 2.5 / Android 12) ---
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
          if (odoData != null) {
            debugPrint("✅ [STATUS] Rescate exitoso para $cleanVin");
            return double.tryParse(odoData.toString());
          }
        }
      }
    } catch (_) {}

    // --- INTENTO 3: FUEL (Modelos anteriores a 2018) ---
    try {
      final res = await _dio.get(
        '$baseUrl/vehicle/vehicles/$cleanVin/fuel',
        options: Options(
          headers: {
            ..._baseHeaders,
            'Accept': 'application/x.volvogroup.com.vehiclefuel.v1.0+json'
          },
          validateStatus: (s) => s! < 500,
        ),
      );
      if (res.statusCode == 200 && res.data != null && res.data['fuelView'] != null) {
        return double.tryParse(res.data['fuelView']['totalVehicleDistance'].toString());
      }
    } catch (_) {}

    debugPrint("🚨 [API] $cleanVin: Sin datos disponibles.");
    return null;
  }
}
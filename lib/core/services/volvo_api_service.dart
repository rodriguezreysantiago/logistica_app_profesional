import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:flutter/material.dart';

class VolvoApiService {
  // Credenciales confirmadas de Santiago Rodriguez Rey
  final String clientId = '018B1E992E';
  final String clientSecret = 'yeBgBh3of3';
  final String baseUrl = 'https://api.volvotrucks.com';
  
  final Dio _dio = Dio();

  // Generamos el Header Basic Auth (El que pide el panel de "Exportar datos")
  String get _authHeader {
    final bytes = utf8.encode('$clientId:$clientSecret');
    return 'Basic ${base64Encode(bytes)}';
  }

  /// ESTA FUNCIÓN TRAE 
  Future<List<dynamic>> traerDatosFlota() async {
    try {
      final response = await _dio.get(
        '$baseUrl/vehicle/vehiclestatuses', // Puerta oficial para tus permisos
        queryParameters: {
          'latestOnly': 'true',
          'contentFilter': 'SNAPSHOT', // Trae la foto actual del camión
        },
        options: Options(
          headers: {
            'Authorization': _authHeader,
            // Header obligatorio según el manual de Volvo v1.0.6
            'Accept': 'application/x.volvogroup.com.vehiclestatuses.v1.0+json',
          },
        ),
      );

      // Estructura de respuesta de Volvo rFMS 2.1
      if (response.data != null && response.data['vehicleStatusResponse'] != null) {
        return response.data['vehicleStatusResponse']['vehicleStatuses'];
      }
      return [];
    } catch (e) {
      if (e is DioException) {
        debugPrint('--- ERROR VOLVO ---');
        debugPrint('Código: ${e.response?.statusCode}');
        debugPrint('Cuerpo: ${e.response?.data}');
      }
      return [];
    }
  }
}
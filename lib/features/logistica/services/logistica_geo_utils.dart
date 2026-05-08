// Helpers de geocoding + cálculos geodésicos para el módulo Logística.
//
// Geocoding: usa Nominatim (OpenStreetMap) — free, sin API key. Política
// de uso: 1 req/seg max, User-Agent obligatorio. Limitamos a Argentina
// (countrycodes=ar) para que la búsqueda sea relevante al operador
// (que va a buscar "Tres Arroyos" o "Bahía Blanca", no "Madrid").
//
// Distancia: geodésica (Haversine) usando latlong2.Distance(). Útil
// para mostrar "X km en línea recta" entre origen y destino. La
// distancia POR RUTA real necesita una API distinta (OSRM, Mapbox,
// Google Routes) — eso queda para cuando armemos el motor de
// planeamiento.

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

/// Resultado de búsqueda en Nominatim.
class GeoLugar {
  final String displayName;
  final LatLng punto;
  final String? localidad;
  final String? provincia;
  final String? direccion;

  const GeoLugar({
    required this.displayName,
    required this.punto,
    this.localidad,
    this.provincia,
    this.direccion,
  });
}

class LogisticaGeoUtils {
  LogisticaGeoUtils._();

  // Cliente Dio dedicado. Nominatim exige User-Agent identificable.
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://nominatim.openstreetmap.org',
      headers: {
        // Política de Nominatim: User-Agent identificable + email
        // de contacto para reportes de abuso. Vecchi usa solo a
        // ritmo humano (operador cargando ubicaciones), bien debajo
        // del rate limit de 1 req/seg.
        'User-Agent': 'CoopertransMovil/1.0 (santiagocoopertrans@gmail.com)',
        'Accept-Language': 'es-AR,es;q=0.9',
      },
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  /// Busca lugares por texto. Filtra a Argentina + límite 8 resultados
  /// (suficiente para que el operador encuentre lo que busca sin
  /// scroll). Caller debe handlear errores de red — si falla, no hay
  /// fallback (el operador puede usar lat/lng manuales).
  static Future<List<GeoLugar>> buscar(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final res = await _dio.get<List<dynamic>>(
      '/search',
      queryParameters: {
        'q': q,
        'format': 'json',
        'countrycodes': 'ar',
        'limit': 8,
        'addressdetails': 1,
      },
    );
    final data = res.data ?? [];
    return data.map((raw) => _parseSearchHit(raw as Map<String, dynamic>))
        .whereType<GeoLugar>()
        .toList();
  }

  /// Reverse geocoding: dado un punto, devuelve localidad/provincia/
  /// dirección si Nominatim los conoce. Se usa al confirmar un punto
  /// en el picker para autocompletar campos del form.
  static Future<GeoLugar?> reverso(LatLng punto) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/reverse',
      queryParameters: {
        'lat': punto.latitude.toStringAsFixed(6),
        'lon': punto.longitude.toStringAsFixed(6),
        'format': 'json',
        'zoom': 14, // ~ciudad/pueblo, suficiente para localidad
        'addressdetails': 1,
      },
    );
    final data = res.data;
    if (data == null) return null;
    return _parseSearchHit(data, fallbackPunto: punto);
  }

  static GeoLugar? _parseSearchHit(
    Map<String, dynamic> raw, {
    LatLng? fallbackPunto,
  }) {
    final lat = double.tryParse(raw['lat']?.toString() ?? '');
    final lon = double.tryParse(raw['lon']?.toString() ?? '');
    final punto = (lat != null && lon != null) ? LatLng(lat, lon) : fallbackPunto;
    if (punto == null) return null;
    final addr = raw['address'] as Map<String, dynamic>? ?? const {};
    // Nominatim devuelve la localidad bajo distintas keys según el
    // tipo de lugar (city/town/village/hamlet/...). Las leemos en
    // orden de preferencia.
    final localidad = addr['city']?.toString() ??
        addr['town']?.toString() ??
        addr['village']?.toString() ??
        addr['hamlet']?.toString() ??
        addr['municipality']?.toString();
    final provincia = addr['state']?.toString() ?? addr['region']?.toString();
    final calle = addr['road']?.toString();
    final numero = addr['house_number']?.toString();
    final direccion = (calle != null)
        ? (numero != null ? '$calle $numero' : calle)
        : null;
    return GeoLugar(
      displayName: raw['display_name']?.toString() ?? '',
      punto: punto,
      localidad: localidad,
      provincia: provincia,
      direccion: direccion,
    );
  }

  /// Distancia geodésica entre dos puntos en kilómetros (línea recta).
  /// Para distancia por ruta real ver `project_planeamiento_viajes_futuro.md`.
  static double distanciaKm(LatLng a, LatLng b) {
    return const Distance().as(LengthUnit.Kilometer, a, b);
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

class Vehiculo {
  final String dominio; // El ID en Firestore
  final String marca;
  final String modelo;
  final int anio;
  final String tipo; 
  final String empresa;
  final String? vin; 
  final DateTime? vencimientoRto;
  final DateTime? vencimientoSeguro;
  final String? urlPdfRto;
  final String? urlPdfSeguro;
  final String estado;

  Vehiculo({
    required this.dominio,
    required this.marca,
    required this.modelo,
    required this.anio,
    required this.tipo,
    required this.empresa,
    this.vin, 
    this.vencimientoRto,
    this.vencimientoSeguro,
    this.urlPdfRto,
    this.urlPdfSeguro,
    this.estado = 'LIBRE', 
  });

  // ==========================================================================
  // SERIALIZACIÓN (Hacia Firebase)
  // ==========================================================================
  
  Map<String, dynamic> toMap() {
    return {
      'DOMINIO': dominio.toUpperCase(),
      'MARCA': marca.toUpperCase(),
      'MODELO': modelo.toUpperCase(),
      // ✅ FIX: Estandarizado a 'ANIO' (sin Ñ) para coincidir con los formularios
      // de alta/edición. Antes estaba mezclado y rompía la lectura del modelo.
      'ANIO': anio,
      'TIPO': tipo.toUpperCase(),
      'EMPRESA': empresa.toUpperCase(),
      'VIN': vin?.toUpperCase(), 
      
      // ✅ MEJORA PRO: Firestore convierte nativamente los objetos DateTime 
      // de Dart a su tipo 'Timestamp' para permitir filtros de fecha exactos y baratos.
      'VENCIMIENTO_RTO': vencimientoRto, 
      'VENCIMIENTO_SEGURO': vencimientoSeguro,
      
      'ARCHIVO_RTO': urlPdfRto,
      'ARCHIVO_SEGURO': urlPdfSeguro, 
      'ESTADO': estado.toUpperCase(), 
    };
  }

  // ==========================================================================
  // DESERIALIZACIÓN (Desde Firebase)
  // ==========================================================================
  
  factory Vehiculo.fromMap(Map<String, dynamic> map, String id) {
    return Vehiculo(
      dominio: id,
      marca: map['MARCA'] ?? 'S/D',
      modelo: map['MODELO'] ?? 'S/D',
      // ✅ FIX: Lectura tolerante. Lee 'ANIO' primero (estándar nuevo) y cae a
      // 'AÑO' por si quedó algún documento viejo en Firestore con el campo con Ñ.
      anio: _parseAnio(map['ANIO'] ?? map['AÑO']),
      tipo: map['TIPO'] ?? 'TRACTOR',
      empresa: map['EMPRESA'] ?? 'PROPIA',
      vin: map['VIN'], 
      
      // ✅ MEJORA PRO: Lectura a prueba de fallos. Si hay un camión viejo cargado con 
      // String, lo lee bien. Si es uno nuevo cargado con Timestamp, también lo lee.
      vencimientoRto: _parseDate(map['VENCIMIENTO_RTO']),
      vencimientoSeguro: _parseDate(map['VENCIMIENTO_SEGURO']),
      
      urlPdfRto: map['ARCHIVO_RTO'],
      urlPdfSeguro: map['ARCHIVO_SEGURO'], 
      estado: map['ESTADO'] ?? 'LIBRE',
    );
  }

  // ✅ FIX: Helper para parsear el año tolerando int, String, double o null.
  static int _parseAnio(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  // Helper privado para retrocompatibilidad de fechas
  static DateTime? _parseDate(dynamic dateData) {
    if (dateData == null) return null;
    if (dateData is Timestamp) {
      return dateData.toDate(); // Formato óptimo nuevo
    }
    if (dateData is String) {
      return DateTime.tryParse(dateData); // Formato heredado antiguo
    }
    return null;
  }

  // ==========================================================================
  // MUTABILIDAD CONTROLADA (Imprescindible para Gestores de Estado)
  // ==========================================================================
  
  Vehiculo copyWith({
    String? dominio,
    String? marca,
    String? modelo,
    int? anio,
    String? tipo,
    String? empresa,
    String? vin,
    DateTime? vencimientoRto,
    DateTime? vencimientoSeguro,
    String? urlPdfRto,
    String? urlPdfSeguro,
    String? estado,
  }) {
    return Vehiculo(
      dominio: dominio ?? this.dominio,
      marca: marca ?? this.marca,
      modelo: modelo ?? this.modelo,
      anio: anio ?? this.anio,
      tipo: tipo ?? this.tipo,
      empresa: empresa ?? this.empresa,
      vin: vin ?? this.vin,
      vencimientoRto: vencimientoRto ?? this.vencimientoRto,
      vencimientoSeguro: vencimientoSeguro ?? this.vencimientoSeguro,
      urlPdfRto: urlPdfRto ?? this.urlPdfRto,
      urlPdfSeguro: urlPdfSeguro ?? this.urlPdfSeguro,
      estado: estado ?? this.estado,
    );
  }
}
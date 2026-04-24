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
  final String estado; // ✅ Mentora: Cambiamos el bool por el String de estado real

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
    this.estado = 'LIBRE', // Estado por defecto
  });

  // Para subir datos a Firebase
  Map<String, dynamic> toMap() {
    return {
      'DOMINIO': dominio.toUpperCase(),
      'MARCA': marca.toUpperCase(),
      'MODELO': modelo.toUpperCase(),
      'AÑO': anio,
      'TIPO': tipo.toUpperCase(),
      'EMPRESA': empresa.toUpperCase(),
      'VIN': vin?.toUpperCase(), 
      'VENCIMIENTO_RTO': vencimientoRto?.toIso8601String().split('T')[0], 
      'VENCIMIENTO_SEGURO': vencimientoSeguro?.toIso8601String().split('T')[0],
      'ARCHIVO_RTO': urlPdfRto,
      // ✅ Mentora: Guardamos el estado exacto que ya tenía, sin forzarlo a LIBRE
      'ESTADO': estado.toUpperCase(), 
    };
  }

  // Para leer datos de Firebase
  factory Vehiculo.fromMap(Map<String, dynamic> map, String id) {
    return Vehiculo(
      dominio: id,
      marca: map['MARCA'] ?? 'S/D',
      modelo: map['MODELO'] ?? 'S/D',
      anio: map['AÑO'] is int ? map['AÑO'] : int.tryParse(map['AÑO'].toString()) ?? 0,
      tipo: map['TIPO'] ?? 'TRACTOR',
      empresa: map['EMPRESA'] ?? 'PROPIA',
      vin: map['VIN'], 
      vencimientoRto: map['VENCIMIENTO_RTO'] != null 
          ? DateTime.tryParse(map['VENCIMIENTO_RTO']) 
          : null,
      vencimientoSeguro: map['VENCIMIENTO_SEGURO'] != null 
          ? DateTime.tryParse(map['VENCIMIENTO_SEGURO']) 
          : null,
      urlPdfRto: map['ARCHIVO_RTO'],
      // ✅ Mentora: Leemos el estado real del camión
      estado: map['ESTADO'] ?? 'LIBRE',
    );
  }
}
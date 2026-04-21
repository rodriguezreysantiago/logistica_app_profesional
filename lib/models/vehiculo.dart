class Vehiculo {
  final String dominio; // La patente es el ID
  final String marca;
  final String modelo;
  final int anio;
  final String tipo; // TRACTOR, BATEA, TOLVA, etc.
  final String empresa;
  final DateTime? vencimientoRto;
  final DateTime? vencimientoSeguro;
  final String? urlPdfRto;
  final bool enServicio;

  Vehiculo({
    required this.dominio,
    required this.marca,
    required this.modelo,
    required this.anio,
    required this.tipo,
    required this.empresa,
    this.vencimientoRto,
    this.vencimientoSeguro,
    this.urlPdfRto,
    this.enServicio = true,
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
      'VENCIMIENTO_RTO': vencimientoRto?.toIso8601String().split('T')[0], // YYYY-MM-DD
      'VENCIMIENTO_SEGURO': vencimientoSeguro?.toIso8601String().split('T')[0],
      'ARCHIVO_RTO': urlPdfRto,
      'ESTADO': enServicio ? 'LIBRE' : 'TALLER',
    };
  }

  // Para leer datos de Firebase
  factory Vehiculo.fromMap(Map<String, dynamic> map, String id) {
    return Vehiculo(
      dominio: id,
      marca: map['MARCA'] ?? 'S/D',
      modelo: map['MODELO'] ?? 'S/D',
      anio: map['AÑO'] ?? 0,
      tipo: map['TIPO'] ?? 'TRACTOR',
      empresa: map['EMPRESA'] ?? 'PROPIA',
      vencimientoRto: map['VENCIMIENTO_RTO'] != null 
          ? DateTime.tryParse(map['VENCIMIENTO_RTO']) 
          : null,
      vencimientoSeguro: map['VENCIMIENTO_SEGURO'] != null 
          ? DateTime.tryParse(map['VENCIMIENTO_SEGURO']) 
          : null,
      urlPdfRto: map['ARCHIVO_RTO'],
      enServicio: map['ESTADO'] != 'TALLER',
    );
  }
}
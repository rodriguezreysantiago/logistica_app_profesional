class Empleado {
  final String id; // DNI
  final String nombre;
  final String categoria; // Chofer, Administrativo, Taller
  final DateTime? vencimientoLNH; 
  final String cuil;
  final bool activo;

  Empleado({
    required this.id,
    required this.nombre,
    required this.categoria,
    this.vencimientoLNH,
    required this.cuil,
    this.activo = true,
  });

  // Convierte el Objeto a un Mapa para guardar en Firebase
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'categoria': categoria,
      'vencimientoLNH': vencimientoLNH?.toIso8601String(),
      'cuil': cuil,
      'activo': activo,
    };
  }

  // NUEVO: Crea un Objeto Empleado a partir de los datos de Firebase
  factory Empleado.fromMap(Map<String, dynamic> map) {
    return Empleado(
      id: map['id'] ?? '',
      nombre: map['nombre'] ?? '',
      categoria: map['categoria'] ?? 'Chofer',
      vencimientoLNH: map['vencimientoLNH'] != null 
          ? DateTime.tryParse(map['vencimientoLNH']) 
          : null,
      cuil: map['cuil'] ?? '',
      activo: map['activo'] ?? true,
    );
  }
}
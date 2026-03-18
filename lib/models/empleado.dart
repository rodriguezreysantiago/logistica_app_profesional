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
}
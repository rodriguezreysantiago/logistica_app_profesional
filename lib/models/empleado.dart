class Empleado {
  final String id; // DNI (Viene del ID del documento)
  final String nombre;
  final String rol; // ✅ Mentora: Cambiado de "categoria" a "rol" para coincidir con tu LoginScreen
  final DateTime? vencimientoLicencia; // Reemplaza LNH para coincidir con el resto de la app
  final String cuil;
  final bool activo;

  Empleado({
    required this.id,
    required this.nombre,
    required this.rol,
    this.vencimientoLicencia,
    required this.cuil,
    this.activo = true,
  });

  // Convierte el Objeto a un Mapa para guardar en Firebase
  Map<String, dynamic> toMap() {
    return {
      // ✅ Mentora: Llaves en MAYÚSCULAS para respetar el esquema de Flete MB
      'NOMBRE': nombre,
      'ROL': rol,
      // ✅ Mentora: Guardamos solo YYYY-MM-DD para no romper la lógica del semáforo
      'VENCIMIENTO_LICENCIA_DE_CONDUCIR': vencimientoLicencia != null 
          ? "${vencimientoLicencia!.year}-${vencimientoLicencia!.month.toString().padLeft(2, '0')}-${vencimientoLicencia!.day.toString().padLeft(2, '0')}"
          : null,
      'CUIL': cuil,
      'ACTIVO': activo,
    };
  }

  // NUEVO: Crea un Objeto Empleado a partir de los datos de Firebase
  // ✅ Mentora: Recibimos el documentId aparte, porque Firebase separa el ID de la data
  factory Empleado.fromMap(Map<String, dynamic> map, String documentId) {
    return Empleado(
      id: documentId, 
      nombre: map['NOMBRE'] ?? '',
      rol: map['ROL'] ?? 'USUARIO',
      vencimientoLicencia: map['VENCIMIENTO_LICENCIA_DE_CONDUCIR'] != null 
          ? DateTime.tryParse(map['VENCIMIENTO_LICENCIA_DE_CONDUCIR']) 
          : null,
      cuil: map['CUIL'] ?? '',
      activo: map['ACTIVO'] ?? true, // Si no existe el campo, por defecto está activo
    );
  }
}
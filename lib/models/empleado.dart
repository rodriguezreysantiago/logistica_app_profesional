class Empleado {
  final String id; // DNI
  final String nombre;
  final String rol;
  final String cuil;
  final bool activo;
  
  // Datos Personales / Operativos
  final String? empresa;
  final String? telefono;
  final String? contrasena;
  final String? archivoPerfil;
  final String? vehiculo; // Patente del tractor asignado
  final String? enganche; // Patente de batea/tolva asignada

  // Vencimientos y Documentos
  final DateTime? vencimientoLicencia;
  final String? archivoLicencia;
  
  final DateTime? vencimientoPsicofisico;
  final String? archivoPsicofisico;
  
  final DateTime? vencimientoManejo;
  final String? archivoManejo;
  
  final DateTime? vencimientoArt;
  final String? archivoArt;

  Empleado({
    required this.id,
    required this.nombre,
    required this.rol,
    required this.cuil,
    this.activo = true,
    this.empresa,
    this.telefono,
    this.contrasena,
    this.archivoPerfil,
    this.vehiculo,
    this.enganche,
    this.vencimientoLicencia,
    this.archivoLicencia,
    this.vencimientoPsicofisico,
    this.archivoPsicofisico,
    this.vencimientoManejo,
    this.archivoManejo,
    this.vencimientoArt,
    this.archivoArt,
  });

  // Convierte el Objeto a un Mapa para guardar en Firebase
  Map<String, dynamic> toMap() {
    return {
      'NOMBRE': nombre.toUpperCase(), // ✅ MENTOR: Todo mayúsculas por seguridad de búsqueda
      'ROL': rol.toUpperCase(),
      'CUIL': cuil,
      'ACTIVO': activo,
      'EMPRESA': empresa?.toUpperCase(),
      'TELEFONO': telefono,
      'CONTRASEÑA': contrasena,
      'ARCHIVO_PERFIL': archivoPerfil,
      'VEHICULO': vehiculo?.toUpperCase(),
      'ENGANCHE': enganche?.toUpperCase(),
      
      // Fechas (Formato YYYY-MM-DD)
      'VENCIMIENTO_LICENCIA_DE_CONDUCIR': vencimientoLicencia?.toIso8601String().split('T')[0],
      'VENCIMIENTO_PSICOFISICO': vencimientoPsicofisico?.toIso8601String().split('T')[0],
      'VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO': vencimientoManejo?.toIso8601String().split('T')[0],
      'VENCIMIENTO_ART': vencimientoArt?.toIso8601String().split('T')[0],
      
      // Archivos PDF/Imágenes
      'ARCHIVO_LICENCIA_DE_CONDUCIR': archivoLicencia,
      'ARCHIVO_PSICOFISICO': archivoPsicofisico,
      'ARCHIVO_CURSO_DE_MANEJO_DEFENSIVO': archivoManejo,
      'ARCHIVO_ART': archivoArt,
    };
  }

  // Crea un Objeto Empleado a partir de los datos de Firebase
  factory Empleado.fromMap(Map<String, dynamic> map, String documentId) {
    return Empleado(
      id: documentId, 
      nombre: map['NOMBRE'] ?? '',
      rol: map['ROL'] ?? 'USUARIO',
      cuil: map['CUIL'] ?? '',
      activo: map['ACTIVO'] ?? true,
      empresa: map['EMPRESA'],
      telefono: map['TELEFONO'],
      contrasena: map['CONTRASEÑA'],
      archivoPerfil: map['ARCHIVO_PERFIL'],
      vehiculo: map['VEHICULO'],
      enganche: map['ENGANCHE'],
      
      // Parseo de Fechas
      vencimientoLicencia: map['VENCIMIENTO_LICENCIA_DE_CONDUCIR'] != null 
          ? DateTime.tryParse(map['VENCIMIENTO_LICENCIA_DE_CONDUCIR']) 
          : null,
      archivoLicencia: map['ARCHIVO_LICENCIA_DE_CONDUCIR'],
      
      vencimientoPsicofisico: map['VENCIMIENTO_PSICOFISICO'] != null 
          ? DateTime.tryParse(map['VENCIMIENTO_PSICOFISICO']) 
          : null,
      archivoPsicofisico: map['ARCHIVO_PSICOFISICO'],
      
      vencimientoManejo: map['VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO'] != null 
          ? DateTime.tryParse(map['VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO']) 
          : null,
      archivoManejo: map['ARCHIVO_CURSO_DE_MANEJO_DEFENSIVO'],
      
      vencimientoArt: map['VENCIMIENTO_ART'] != null 
          ? DateTime.tryParse(map['VENCIMIENTO_ART']) 
          : null,
      archivoArt: map['ARCHIVO_ART'],
    );
  }
}
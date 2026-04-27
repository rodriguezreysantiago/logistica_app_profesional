import 'package:cloud_firestore/cloud_firestore.dart';

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

  // ==========================================================================
  // SERIALIZACIÓN (Hacia Firebase)
  // ==========================================================================
  
  Map<String, dynamic> toMap() {
    return {
      'NOMBRE': nombre.toUpperCase(),
      'ROL': rol.toUpperCase(),
      'CUIL': cuil,
      'ACTIVO': activo,
      'EMPRESA': empresa?.toUpperCase(),
      'TELEFONO': telefono,
      'CONTRASEÑA': contrasena,
      'ARCHIVO_PERFIL': archivoPerfil,
      'VEHICULO': vehiculo?.toUpperCase(),
      'ENGANCHE': enganche?.toUpperCase(),
      
      // ✅ MEJORA PRO: Al pasar un DateTime, Firebase automáticamente 
      // lo convierte a su tipo nativo 'Timestamp', permitiendo querys eficientes.
      'VENCIMIENTO_LICENCIA_DE_CONDUCIR': vencimientoLicencia,
      'VENCIMIENTO_PSICOFISICO': vencimientoPsicofisico,
      'VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO': vencimientoManejo,
      'VENCIMIENTO_ART': vencimientoArt,
      
      // Archivos PDF/Imágenes
      'ARCHIVO_LICENCIA_DE_CONDUCIR': archivoLicencia,
      'ARCHIVO_PSICOFISICO': archivoPsicofisico,
      'ARCHIVO_CURSO_DE_MANEJO_DEFENSIVO': archivoManejo,
      'ARCHIVO_ART': archivoArt,
    };
  }

  // ==========================================================================
  // DESERIALIZACIÓN (Desde Firebase)
  // ==========================================================================
  
  factory Empleado.fromMap(Map<String, dynamic> map, String documentId) {
    return Empleado(
      id: documentId, 
      nombre: map['NOMBRE'] ?? '',
      rol: map['ROL'] ?? 'USUARIO',
      cuil: map['CUIL'] ?? '',
      // Protección de tipo por si alguien carga un string "true" en lugar de boolean
      activo: map['ACTIVO'] is bool ? map['ACTIVO'] : true, 
      empresa: map['EMPRESA'],
      telefono: map['TELEFONO'],
      contrasena: map['CONTRASEÑA'],
      archivoPerfil: map['ARCHIVO_PERFIL'],
      vehiculo: map['VEHICULO'],
      enganche: map['ENGANCHE'],
      
      // ✅ MEJORA PRO: Uso de helper para garantizar lectura sin importar 
      // si el dato viejo era String o si el nuevo es Timestamp.
      vencimientoLicencia: _parseDate(map['VENCIMIENTO_LICENCIA_DE_CONDUCIR']),
      archivoLicencia: map['ARCHIVO_LICENCIA_DE_CONDUCIR'],
      
      vencimientoPsicofisico: _parseDate(map['VENCIMIENTO_PSICOFISICO']),
      archivoPsicofisico: map['ARCHIVO_PSICOFISICO'],
      
      vencimientoManejo: _parseDate(map['VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO']),
      archivoManejo: map['ARCHIVO_CURSO_DE_MANEJO_DEFENSIVO'],
      
      vencimientoArt: _parseDate(map['VENCIMIENTO_ART']),
      archivoArt: map['ARCHIVO_ART'],
    );
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
  
  Empleado copyWith({
    String? id,
    String? nombre,
    String? rol,
    String? cuil,
    bool? activo,
    String? empresa,
    String? telefono,
    String? contrasena,
    String? archivoPerfil,
    String? vehiculo,
    String? enganche,
    DateTime? vencimientoLicencia,
    String? archivoLicencia,
    DateTime? vencimientoPsicofisico,
    String? archivoPsicofisico,
    DateTime? vencimientoManejo,
    String? archivoManejo,
    DateTime? vencimientoArt,
    String? archivoArt,
  }) {
    return Empleado(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      rol: rol ?? this.rol,
      cuil: cuil ?? this.cuil,
      activo: activo ?? this.activo,
      empresa: empresa ?? this.empresa,
      telefono: telefono ?? this.telefono,
      contrasena: contrasena ?? this.contrasena,
      archivoPerfil: archivoPerfil ?? this.archivoPerfil,
      vehiculo: vehiculo ?? this.vehiculo,
      enganche: enganche ?? this.enganche,
      vencimientoLicencia: vencimientoLicencia ?? this.vencimientoLicencia,
      archivoLicencia: archivoLicencia ?? this.archivoLicencia,
      vencimientoPsicofisico: vencimientoPsicofisico ?? this.vencimientoPsicofisico,
      archivoPsicofisico: archivoPsicofisico ?? this.archivoPsicofisico,
      vencimientoManejo: vencimientoManejo ?? this.vencimientoManejo,
      archivoManejo: archivoManejo ?? this.archivoManejo,
      vencimientoArt: vencimientoArt ?? this.vencimientoArt,
      archivoArt: archivoArt ?? this.archivoArt,
    );
  }
}
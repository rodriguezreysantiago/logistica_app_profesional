import 'package:cloud_firestore/cloud_firestore.dart';

class Empleado {
  final String id; // DNI
  final String nombre;
  /// Rol del sistema: CHOFER / PLANTA / SUPERVISOR / ADMIN.
  /// Define QUÉ puede hacer en la app.
  final String rol;
  /// Área organizacional: MANEJO / ADMINISTRACION / PLANTA / TALLER /
  /// GOMERIA. Define DÓNDE trabaja la persona. No afecta permisos.
  /// Default 'MANEJO' por retrocompatibilidad con datos viejos.
  final String area;
  final String cuil;
  final bool activo;

  // Datos Personales / Operativos
  final String? empresa;
  final String? telefono;
  final String? contrasena;
  // Apodo opcional — cómo le decimos al chofer cuando le hablamos.
  // Necesario porque varios choferes tienen 2 nombres y 2 apellidos
  // (ej: "GONZALEZ RODRIGUEZ JUAN CARLOS"), donde el algoritmo de
  // "segundo token" falla. Si está vacío, el saludo cae al fallback
  // (`_extraerPrimerNombre` del NOMBRE).
  final String? apodo;
  final String? archivoPerfil;
  final String? vehiculo; // Patente del tractor asignado
  final String? enganche; // Patente de batea/tolva asignada

  // Vencimientos y Documentos
  final DateTime? vencimientoLicencia;
  final String? archivoLicencia;
  
  final DateTime? vencimientoPreocupacional;
  final String? archivoPreocupacional;
  
  final DateTime? vencimientoManejo;
  final String? archivoManejo;
  
  final DateTime? vencimientoArt;
  final String? archivoArt;

  Empleado({
    required this.id,
    required this.nombre,
    required this.rol,
    required this.cuil,
    this.area = 'MANEJO',
    this.activo = true,
    this.empresa,
    this.telefono,
    this.contrasena,
    this.apodo,
    this.archivoPerfil,
    this.vehiculo,
    this.enganche,
    this.vencimientoLicencia,
    this.archivoLicencia,
    this.vencimientoPreocupacional,
    this.archivoPreocupacional,
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
      'AREA': area.toUpperCase(),
      'CUIL': cuil,
      'ACTIVO': activo,
      'EMPRESA': empresa?.toUpperCase(),
      'TELEFONO': telefono,
      'CONTRASEÑA': contrasena,
      'APODO': apodo,
      'ARCHIVO_PERFIL': archivoPerfil,
      'VEHICULO': vehiculo?.toUpperCase(),
      'ENGANCHE': enganche?.toUpperCase(),
      
      // ✅ MEJORA PRO: Al pasar un DateTime, Firebase automáticamente 
      // lo convierte a su tipo nativo 'Timestamp', permitiendo querys eficientes.
      'VENCIMIENTO_LICENCIA_DE_CONDUCIR': vencimientoLicencia,
      'VENCIMIENTO_PREOCUPACIONAL': vencimientoPreocupacional,
      'VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO': vencimientoManejo,
      'VENCIMIENTO_ART': vencimientoArt,
      
      // Archivos PDF/Imágenes
      'ARCHIVO_LICENCIA_DE_CONDUCIR': archivoLicencia,
      'ARCHIVO_PREOCUPACIONAL': archivoPreocupacional,
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
      rol: map['ROL'] ?? 'CHOFER',
      // Default 'MANEJO' para que choferes existentes que no tienen
      // AREA cargada todavía sigan funcionando. La migración los
      // setea explícitamente en otra pasada.
      area: (map['AREA'] ?? 'MANEJO').toString(),
      cuil: map['CUIL'] ?? '',
      // Protección de tipo por si alguien carga un string "true" en lugar de boolean
      activo: map['ACTIVO'] is bool ? map['ACTIVO'] : true, 
      empresa: map['EMPRESA'],
      telefono: map['TELEFONO'],
      contrasena: map['CONTRASEÑA'],
      apodo: map['APODO'],
      archivoPerfil: map['ARCHIVO_PERFIL'],
      vehiculo: map['VEHICULO'],
      enganche: map['ENGANCHE'],
      
      // ✅ MEJORA PRO: Uso de helper para garantizar lectura sin importar 
      // si el dato viejo era String o si el nuevo es Timestamp.
      vencimientoLicencia: _parseDate(map['VENCIMIENTO_LICENCIA_DE_CONDUCIR']),
      archivoLicencia: map['ARCHIVO_LICENCIA_DE_CONDUCIR'],
      
      vencimientoPreocupacional: _parseDate(map['VENCIMIENTO_PREOCUPACIONAL']),
      archivoPreocupacional: map['ARCHIVO_PREOCUPACIONAL'],
      
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
    String? area,
    String? cuil,
    bool? activo,
    String? empresa,
    String? telefono,
    String? contrasena,
    String? apodo,
    String? archivoPerfil,
    String? vehiculo,
    String? enganche,
    DateTime? vencimientoLicencia,
    String? archivoLicencia,
    DateTime? vencimientoPreocupacional,
    String? archivoPreocupacional,
    DateTime? vencimientoManejo,
    String? archivoManejo,
    DateTime? vencim
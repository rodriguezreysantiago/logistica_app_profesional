class AppRoutes {
  // ✅ MEJORA PRO: Constructor privado. Evita que la clase sea instanciada por error.
  AppRoutes._();

  static const String login = '/';
  static const String home = '/home';

  // Usuario
  static const String perfil = '/perfil';
  static const String equipo = '/equipo';
  static const String misVencimientos = '/mis_vencimientos';

  // Admin
  static const String adminPanel = '/admin_panel';
  static const String adminPersonalLista = '/admin_personal_lista';
  static const String adminVehiculosLista = '/admin_vehiculos_lista';
  static const String adminVencimientosMenu = '/admin_vencimientos_menu';
  static const String adminRevisiones = '/admin_revisiones';
  static const String adminReportes = '/admin_reportes';

  // Auditorías
  static const String vencimientosChoferes = '/vencimientos_choferes';
  static const String vencimientosChasis = '/vencimientos_chasis';
  static const String vencimientosAcoplados = '/vencimientos_acoplados';
}

class AppTexts {
  AppTexts._();

  static const String appName = 'S.M.A.R.T. Logística';
  static const String rutaNoEncontrada = 'Ruta no encontrada';
  // Podés mantener un registro visual de tu versión acá
  static const String appVersion = 'v 1.0.7'; 
}

// ===========================================================================
// ✅ MEJORA PRO: CENTRALIZACIÓN DE COLECCIONES Y ROLES (Sin "Magic Strings")
// ===========================================================================

class AppCollections {
  AppCollections._();

  static const String empleados = 'EMPLEADOS';
  static const String vehiculos = 'VEHICULOS';
  static const String revisiones = 'REVISIONES';
  static const String checklists = 'CHECKLISTS';
}

class AppRoles {
  AppRoles._();

  static const String admin = 'ADMIN';
  static const String chofer = 'USUARIO'; // O 'CHOFER', según uses en tu base
}
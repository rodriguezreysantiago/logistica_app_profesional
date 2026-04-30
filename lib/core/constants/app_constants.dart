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
  static const String adminMantenimiento = '/admin_mantenimiento';
  static const String syncDashboard = '/sync_dashboard';
  static const String adminEstadoBot = '/admin_estado_bot';


  // Auditorías
  static const String vencimientosChoferes = '/vencimientos_choferes';
  static const String vencimientosChasis = '/vencimientos_chasis';
  static const String vencimientosAcoplados = '/vencimientos_acoplados';
  static const String vencimientosCalendario = '/vencimientos_calendario';
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
  static const String telemetriaHistorico = 'TELEMETRIA_HISTORICO';
  /// Idempotencia para notificaciones de mantenimiento: cada vez que un
  /// tractor cruza un umbral, escribimos un doc para no notificar dos
  /// veces el mismo evento en el mismo "ciclo".
  static const String mantenimientosAvisados = 'MANTENIMIENTOS_AVISADOS';
}

class AppRoles {
  AppRoles._();

  static const String admin = 'ADMIN';
  static const String chofer = 'USUARIO'; // O 'CHOFER', según uses en tu base
}

// ===========================================================================
// TIPOS DE UNIDAD DE LA FLOTA
// ===========================================================================
//
// Centralizar acá la lista evita el problema de "agregué un tipo nuevo
// pero me olvidé de actualizarlo en el formulario / la lista / el filtro
// del chofer / el reporte de vencimientos". Cuando aparezca un tipo
// nuevo, sumalo solamente acá y la app lo va a mostrar en todos lados.
class AppTiposVehiculo {
  AppTiposVehiculo._();

  /// Tractor / chasis (la unidad con motor que arrastra los enganches).
  static const String tractor = 'TRACTOR';

  /// Lista de tipos de enganche soportados por la app.
  ///
  /// `ACOPLADO` se mantiene al final por **retrocompatibilidad**: hay
  /// documentos viejos en Firestore con ese TIPO. No aparece como opción
  /// en el formulario de alta para que no se carguen unidades nuevas con
  /// ese tipo, pero sí se incluye en filtros y queries para que las
  /// unidades históricas se vean correctamente.
  static const List<String> enganches = [
    'BATEA',
    'TOLVA',
    'BIVUELCO',
    'TANQUE',
    'ACOPLADO',
  ];

  /// Tipos que se ofrecen como opción en el formulario de alta de
  /// vehículos. Es la lista oficial de los que un admin puede crear.
  static const List<String> seleccionables = [
    'TRACTOR',
    'BATEA',
    'TOLVA',
    'BIVUELCO',
    'TANQUE',
  ];

  /// Etiqueta legible para mostrar en UI (plural). Usar para títulos de
  /// secciones/listas que agrupan unidades por tipo.
  static const Map<String, String> pluralEtiquetas = {
    'TRACTOR': 'TRACTORES',
    'BATEA': 'BATEAS',
    'TOLVA': 'TOLVAS',
    'BIVUELCO': 'BIVUELCOS',
    'TANQUE': 'TANQUES',
    'ACOPLADO': 'ACOPLADOS',
  };

  /// Etiqueta singular en minúsculas para mensajes ("sin tractores
  /// cargados").
  static const Map<String, String> pluralMinusculas = {
    'TRACTOR': 'tractores',
    'BATEA': 'bateas',
    'TOLVA': 'tolvas',
    'BIVUELCO': 'bivuelcos',
    'TANQUE': 'tanques',
    'ACOPLADO': 'acoplados',
  };
}

// ===========================================================================
// MANTENIMIENTO PREVENTIVO (Volvo serviceDistance)
// ===========================================================================
//
// `serviceDistance` que entrega Volvo en metros = distancia restante al
// próximo service programado. Negativo = vencido.
//
// Para que el admin pueda anticipar turnos de taller, definimos 4
// umbrales en KM (NO metros):
//
//   > 5000 km  →  OK (verde)
//   ≤ 5000 km  →  Falta poco (amarillo claro / lime)
//   ≤ 2500 km  →  Programar (amarillo)
//   ≤ 1000 km  →  Urgente (naranja)
//   ≤ 0    km  →  Vencido (rojo)
//
// Cualquier ajuste a la curva de alarma se hace acá — pantalla y badge
// leen estas constantes.
class AppMantenimiento {
  AppMantenimiento._();

  /// KM al próximo service desde el cual el badge pasa a "Falta poco"
  /// (amarillo claro).
  static const double atencionKm = 5000;

  /// KM desde el cual ya hay que pedir turno al taller ("Programar").
  static const double programarKm = 2500;

  /// KM desde el cual la situación es urgente ("Servicio urgente").
  static const double urgenteKm = 1000;

  /// Intervalo entre services programados, en KM. Volvo aplica el plan
  /// estándar de 50.000 km a la flota Vecchi. Si en el futuro hay
  /// tractores con plan distinto, podríamos agregar un campo
  /// `INTERVALO_SERVICE_KM` en VEHICULOS y caer a esta constante como
  /// default.
  static const double intervaloServiceKm = 50000;

  /// Niveles de urgencia ordenados de menor a mayor severidad.
  /// Usados por el badge y la lista de mantenimiento para sortear.
  static MantenimientoEstado clasificar(double? serviceDistanceKm) {
    if (serviceDistanceKm == null) return MantenimientoEstado.sinDato;
    if (serviceDistanceKm <= 0) return MantenimientoEstado.vencido;
    if (serviceDistanceKm <= urgenteKm) return MantenimientoEstado.urgente;
    if (serviceDistanceKm <= programarKm) return MantenimientoEstado.programar;
    if (serviceDistanceKm <= atencionKm) return MantenimientoEstado.atencion;
    return MantenimientoEstado.ok;
  }

  /// Calcula el KM al que se hizo el último service de un tractor.
  ///
  /// Fórmula: `KM_ACTUAL + serviceDistance − intervaloServiceKm`.
  ///
  /// Ejemplo: si un tractor tiene 380.000 km y `serviceDistance: 12.000`,
  /// el próximo service es a 392.000 km y el último fue a 342.000 km.
  ///
  /// Devuelve null si falta alguno de los dos inputs (no hay manera de
  /// estimar sin ambos).
  static double? calcularKmUltimoService({
    required double? kmActual,
    required double? serviceDistanceKm,
  }) {
    if (kmActual == null || serviceDistanceKm == null) return null;
    final resultado = kmActual + serviceDistanceKm - intervaloServiceKm;
    // Si el cálculo da negativo (tractor con menos de 50k km) significa
    // que todavía está en su primer ciclo de service, no tuvo "anterior".
    if (resultado < 0) return null;
    return resultado;
  }

  /// KM recorridos desde el último service. Útil para mostrar en la card
  /// "X km recorridos desde el último service".
  static double? kmDesdeUltimoService({
    required double? kmActual,
    required double? serviceDistanceKm,
  }) {
    final kmUltimo = calcularKmUltimoService(
      kmActual: kmActual,
      serviceDistanceKm: serviceDistanceKm,
    );
    if (kmUltimo == null || kmActual == null) return null;
    return kmActual - kmUltimo;
  }

  /// Calcula `serviceDistance` (KM al próximo service) a partir del
  /// último service cargado manualmente y el odómetro actual.
  ///
  /// Fórmula: `(ULTIMO_SERVICE_KM + intervaloServiceKm) − KM_ACTUAL`.
  ///
  /// Útil cuando la API de Volvo NO entrega `serviceDistance` para la
  /// cuenta (paquete API limitado). Caso real de Vecchi: el response
  /// `vehiclestatuses` no incluye el bloque `uptimeData` que contiene
  /// ese campo, así que dependemos del dato manual + KM en vivo.
  ///
  /// Devuelve null si falta alguno de los inputs **o si los datos son
  /// inconsistentes** (ULTIMO_SERVICE_KM > KM_ACTUAL: el admin cargó
  /// algo mal, ej. invirtió dígitos). Puede ser **negativo** si el
  /// tractor ya pasó el momento del próximo service (vencido).
  static double? serviceDistanceDesdeManual({
    required double? ultimoServiceKm,
    required double? kmActual,
  }) {
    if (ultimoServiceKm == null || kmActual == null) return null;
    // Defensa contra typo del admin: el último service no puede haber
    // sido a más kilómetros de los que tiene el tractor ahora.
    if (ultimoServiceKm > kmActual) return null;
    return (ultimoServiceKm + intervaloServiceKm) - kmActual;
  }
}

/// Estados del mantenimiento preventivo, ordenados por severidad.
/// El `index` se usa para sortear (menor índice = más urgente).
enum MantenimientoEstado {
  vencido('Servicio vencido'),
  urgente('Servicio urgente'),
  programar('Programar servicio'),
  atencion('Falta poco'),
  ok('OK'),
  sinDato('Sin datos');

  final Strin
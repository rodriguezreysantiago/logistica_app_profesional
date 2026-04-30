import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/vencimientos_config.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/prefs_service.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/app_widgets.dart';

/// Panel de administración — pantalla "Inicio" del shell admin.
///
/// Muestra un **dashboard de operación** con métricas en tiempo real:
/// choferes activos, unidades en flota, revisiones pendientes y
/// vencimientos por urgencia (vencidos / próximos 7d / próximos 30d).
/// Cada KPI es tappable y lleva a la sección correspondiente.
///
/// Debajo del dashboard, accesos directos compactos a las secciones
/// principales (legacy del menú anterior — siguen siendo útiles para
/// usuarios que ya tienen el flujo memorizado).
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  StreamSubscription? _revisionesSubscription;
  bool _esPrimeraCarga = true;

  late final Stream<QuerySnapshot> _empleadosStream;
  late final Stream<QuerySnapshot> _vehiculosStream;
  late final Stream<QuerySnapshot> _revisionesStream;

  /// Documentos de chofer auditados — replica del listado en
  /// `admin_vencimientos_choferes_screen.dart`. Si en el futuro se
  /// centraliza, mover a `vencimientos_config.dart`.
  static const Map<String, String> _docsEmpleado = {
    'Licencia de Conducir': 'LICENCIA_DE_CONDUCIR',
    'Preocupacional': 'PREOCUPACIONAL',
    'Manejo Defensivo': 'CURSO_DE_MANEJO_DEFENSIVO',
    'ART': 'ART',
    'F. 931': '931',
    'Seguro de Vida': 'SEGURO_DE_VIDA',
    'Sindicato': 'LIBRE_DE_DEUDA_SINDICAL',
  };

  @override
  void initState() {
    super.initState();
    final db = FirebaseFirestore.instance;
    _empleadosStream = db.collection('EMPLEADOS').snapshots();
    _vehiculosStream = db.collection('VEHICULOS').snapshots();
    _revisionesStream = db.collection('REVISIONES').snapshots();
    _activarEscuchaRevisiones();
  }

  @override
  void dispose() {
    _revisionesSubscription?.cancel();
    super.dispose();
  }

  /// Listener separado para disparar notificación push cuando llega una
  /// revisión nueva. La primera carga se ignora para no spamear al
  /// admin con todas las que ya estaban al abrir la pantalla.
  void _activarEscuchaRevisiones() {
    _revisionesSubscription?.cancel();
    _revisionesSubscription =
        FirebaseFirestore.instance.collection('REVISIONES').snapshots().listen(
      (snapshot) {
        if (_esPrimeraCarga) {
          _esPrimeraCarga = false;
          return;
        }
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            try {
              final data = change.doc.data();
              if (data != null) {
                NotificationService.mostrarAvisoAdmin(
                  chofer: data['nombre_usuario'] ?? 'Un chofer',
                  documento: data['etiqueta'] ?? 'documento',
                );
              }
            } catch (e) {
              debugPrint('Error en radar de notificaciones: $e');
            }
          }
        }
      },
      onError: (error) =>
          debugPrint('Error en stream de revisiones: $error'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'S.M.A.R.T. Logística',
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          const _Saludo(),
          const SizedBox(height: 16),
          // ------- KPIs en vivo -------
          StreamBuilder<QuerySnapshot>(
            stream: _empleadosStream,
            builder: (ctx, snapEmp) => StreamBuilder<QuerySnapshot>(
              stream: _vehiculosStream,
              builder: (ctx, snapVeh) => StreamBuilder<QuerySnapshot>(
                stream: _revisionesStream,
                builder: (ctx, snapRev) {
                  final stats = _Stats.from(
                    empleados: snapEmp.data,
                    vehiculos: snapVeh.data,
                    revisiones: snapRev.data,
                    docsEmpleado: _docsEmpleado,
                  );
                  return _GridKPIs(stats: stats);
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          // ------- Accesos directos (legacy) -------
          const _SeccionLabel('Accesos rápidos'),
          const SizedBox(height: 8),
          const _AdminTile(
            titulo: 'GESTIÓN DE PERSONAL',
            subtitulo: 'Lista de legajos y choferes',
            icono: Icons.badge_outlined,
            color: Colors.blueAccent,
            ruta: '/admin_personal_lista',
          ),
          const _AdminTile(
            titulo: 'GESTIÓN DE FLOTA',
            subtitulo: 'Control de camiones y acoplados',
            icono: Icons.local_shipping_outlined,
            color: Colors.purpleAccent,
            ruta: '/admin_vehiculos_lista',
          ),
          const _AdminTile(
            titulo: 'AUDITORÍA DE VENCIMIENTOS',
            subtitulo: 'Calendario y listas por categoría',
            icono: Icons.event_note,
            color: Colors.greenAccent,
            ruta: '/admin_vencimientos_menu',
          ),
          const _AdminTile(
            titulo: 'REVISIONES PENDIENTES',
            subtitulo: 'Aprobar/rechazar trámites cargados por choferes',
            icono: Icons.fact_check_outlined,
            color: Colors.tealAccent,
            ruta: '/admin_revisiones',
          ),
          const _AdminTile(
            titulo: 'CENTRO DE REPORTES',
            subtitulo: 'Exportar Excel y analítica de flota',
            icono: Icons.analytics_outlined,
            color: Colors.amberAccent,
            ruta: '/admin_reportes',
          ),
          const _AdminTile(
            titulo: 'MANTENIMIENTO PREVENTIVO',
            subtitulo: 'Próximos services de la flota Volvo',
            icono: Icons.build_circle_outlined,
            color: Colors.deepOrangeAccent,
            ruta: AppRoutes.adminMantenimiento,
          ),
          const _AdminTile(
            titulo: 'SYNC OBSERVABILITY',
            subtitulo: 'Monitoreo en tiempo real de sincronización',
            icono: Icons.monitor_heart_outlined,
            color: Colors.cyanAccent,
            ruta: AppRoutes.syncDashboard,
          ),
          const _AdminTile(
            titulo: 'ESTADO DEL BOT',
            subtitulo: 'Bot WhatsApp: cola, cron, errores y heartbeat',
            icono: Icons.smart_toy_outlined,
            color: Colors.lightGreenAccent,
            ruta: AppRoutes.adminEstadoBot,
          ),
          const SizedBox(height: 28),
          const Center(
            child: Text(
              'v 1.0.7 — Base Operativa',
              style: TextStyle(
                color: Colors.white24,
                fontSize: 11,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// =============================================================================
// SALUDO
// =============================================================================

/// Encabezado con saludo según hora del día + nombre del admin.
/// Toma `PrefsService.nombre` para personalizar.
class _Saludo extends StatelessWidget {
  const _Saludo();

  String _saludoHora() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Buen día';
    if (h < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  /// Para nombres "APELLIDO NOMBRE …", devuelve "Nombre" capitalizado.
  /// Igual a `_extraerPrimerNombre` de vencimiento_editor_sheet.dart.
  String? _primerNombre(String full) {
    final partes = full.trim().split(RegExp(r'\s+'));
    if (partes.length < 2) return null;
    final n = partes[1];
    if (n.isEmpty) return null;
    return '${n[0].toUpperCase()}${n.substring(1).toLowerCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final nombreFull = PrefsService.nombre;
    final nombre = _primerNombre(nombreFull);
    final saludo =
        nombre != null ? '${_saludoHora()}, $nombre' : _saludoHora();
    final fechaHoy =
        AppFormatters.formatearFecha(DateTime.now().toIso8601String());

    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            saludo,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            fechaHoy,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SeccionLabel extends StatelessWidget {
  final String texto;
  const _SeccionLabel(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, top: 4),
      child: Text(
        texto.toUpperCase(),
        style: const TextStyle(
          color: Colors.greenAccent,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

// =============================================================================
// CÁLCULO DE MÉTRICAS
// =============================================================================

/// Estadísticas agregadas que pinta el dashboard. Inmutable; se calcula
/// una vez por frame combinando los 3 snapshots.
class _Stats {
  final int choferesActivos;
  final int unidadesTotal;
  final int unidadesAsignadas;
  final int revisionesPendientes;
  final int vencidos;
  final int proximos7;
  final int proximos30;

  /// `true` mientras alguno de los streams todavía no tiene su primer
  /// snapshot — sirve para mostrar placeholders en lugar de "0" mentiroso.
  final bool cargando;

  const _Stats({
    required this.choferesActivos,
    required this.unidadesTotal,
    required this.unidadesAsignadas,
    required this.revisionesPendientes,
    required this.vencidos,
    required this.proximos7,
    required this.proximos30,
    required this.cargando,
  });

  factory _Stats.from({
    required QuerySnapshot? empleados,
    required QuerySnapshot? vehiculos,
    required QuerySnapshot? revisiones,
    required Map<String, String> docsEmpleado,
  }) {
    final cargando =
        empleados == null || vehiculos == null || revisiones == null;
    if (cargando) {
      return const _Stats(
        choferesActivos: 0,
        unidadesTotal: 0,
        unidadesAsignadas: 0,
        revisionesPendientes: 0,
        vencidos: 0,
        proximos7: 0,
        proximos30: 0,
        cargando: true,
      );
    }

    int activos = 0;
    int vencidos = 0;
    int prox7 = 0;
    int prox30 = 0;

    void contarFecha(String? fechaStr) {
      if (fechaStr == null || fechaStr.isEmpty) return;
      final dias = AppFormatters.calcularDiasRestantes(fechaStr);
      if (dias < 0) {
        vencidos++;
      } else if (dias <= 7) {
        prox7++;
      } else if (dias <= 30) {
        prox30++;
      }
    }

    // Empleados
    for (final doc in empleados.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final estado = (data['estado_cuenta'] ?? 'ACTIVO').toString();
      if (estado.toUpperCase() == 'ACTIVO') activos++;
      for (final campoBase in docsEmpleado.values) {
        contarFecha(data['VENCIMIENTO_$campoBase']?.toString());
      }
    }

    // Vehículos
    int unidadesAsignadas = 0;
    for (final doc in vehiculos.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final estado = (data['ESTADO'] ?? '').toString().toUpperCase();
      if (estado == 'OCUPADO' || estado == 'ASIGNADO') {
        unidadesAsignadas++;
      }
      final tipo = (data['TIPO'] ?? '').toString();
      for (final spec in AppVencimientos.forTipo(tipo)) {
        contarFecha(data[spec.campoFecha]?.toString());
      }
    }

    return _Stats(
      choferesActivos: activos,
      unidadesTotal: vehiculos.docs.length,
      unidadesAsignadas: unidadesAsignadas,
      revisionesPendientes: revisiones.docs.length,
      vencidos: vencidos,
      proximos7: prox7,
      proximos30: prox30,
      cargando: false,
    );
  }
}

// =============================================================================
// GRID DE KPIs
// =============================================================================

class _GridKPIs extends StatelessWidget {
  final _Stats stats;
  const _GridKPIs({required this.stats});

  @override
  Widget build(BuildContext context) {
    final esDesktop = MediaQuery.of(context).size.width >= 600;
    final cols = esDesktop ? 3 : 2;

    final tarjetas = <Widget>[
      _KpiCard(
        label: 'Choferes activos',
        valor: stats.cargando ? '…' : '${stats.choferesActivos}',
        icon: Icons.badge,
        color: Colors.blueAccent,
        ruta: '/admin_personal_lista',
      ),
      _KpiCard(
        label: 'Unidades en flota',
        valor: stats.cargando ? '…' : '${stats.unidadesTotal}',
        sublabel: stats.cargando
            ? null
            : '${stats.unidadesAsignadas} asignadas',
        icon: Icons.local_shipping,
        color: Colors.purpleAccent,
        ruta: '/admin_vehiculos_lista',
      ),
      _KpiCard(
        label: 'Trámites pendientes',
        valor:
            stats.cargando ? '…' : '${stats.revisionesPendientes}',
        icon: Icons.fact_check_outlined,
        // Naranja si hay pendientes — no es error, pero requiere atención.
        color: stats.revisionesPendientes > 0
            ? Colors.orangeAccent
            : Colors.greenAccent,
        urgente: stats.revisionesPendientes > 0,
        ruta: '/admin_revisiones',
      ),
      _KpiCard(
        label: 'Vencidos',
        valor: stats.cargando ? '…' : '${stats.vencidos}',
        sublabel: 'sin renovar',
        icon: Icons.error_outline,
        // Rojo si hay vencidos — esto sí es crítico.
        color:
            stats.vencidos > 0 ? Colors.redAccent : Colors.greenAccent,
        urgente: stats.vencidos > 0,
        ruta: '/vencimientos_calendario',
      ),
      _KpiCard(
        label: 'Vencen ≤ 7 días',
        valor: stats.cargando ? '…' : '${stats.proximos7}',
        icon: Icons.warning_amber_rounded,
        color: stats.proximos7 > 0
            ? Colors.orangeAccent
            : Colors.greenAccent,
        urgente: stats.proximos7 > 0,
        ruta: '/vencimientos_calendario',
      ),
      _KpiCard(
        label: 'Vencen ≤ 30 días',
        valor: stats.cargando ? '…' : '${stats.proximos30}',
        icon: Icons.event_note,
        color: Colors.tealAccent,
        ruta: '/vencimientos_calendario',
      ),
    ];

    return GridView.count(
      crossAxisCount: cols,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      // Cards más anchas que altas; ratio ajustado para que el número
      // grande tenga aire sin que la card crezca demasiado en alto.
      childAspectRatio: esDesktop ? 1.6 : 1.4,
      children: tarjetas,
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String valor;
  final String? sublabel;
  final IconData icon;
  final Color color;
  final String? ruta;

  /// Si es `true`, agrega un borde visible del color para que la card
  /// destaque entre las que están en estado normal.
  final bool urgente;

  const _KpiCard({
    required this.label,
    required this.valor,
    required this.icon,
    required this.color,
    this.sublabel,
    this.ruta,
    this.urgente = false,
  });

  @override
  Widget build(BuildContext context) {
    final tap = ruta != null
        ? () => Navigator.pushNamed(context, ruta!)
        : null;

    return AppCard(
      onTap: tap,
      padding: const EdgeInsets.all(14),
      highlighted: urgente,
      borderColor: urgente ? color.withAlpha(160) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              if (urgente)
                const Icon(Icons.priority_high,
                    color: Colors.white54, size: 14),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                valor,
                style: TextStyle(
                  color: color,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
              if (sublabel != null) ...[
                const SizedBox(height: 2),
                Text(
                  sublabel!,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// TILE DE ACCESO DIRECTO (legacy — secciones grandes del menú)
// =============================================================================

class _AdminTile extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final IconData icono;
  final Color color;
  final String ruta;

  const _AdminTile({
    required this.titulo,
    required this.subtitulo,
    required this.icono,
    required this.color,
    required this.ruta,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => Navigator.pushNamed(context, ruta),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: Icon(icono, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitulo,
   
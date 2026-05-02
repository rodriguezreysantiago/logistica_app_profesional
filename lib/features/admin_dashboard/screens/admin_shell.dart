import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/services/capabilities.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/prefs_service.dart';
import '../../../shared/widgets/app_widgets.dart';

import '../../employees/screens/admin_personal_lista_screen.dart';
import '../../expirations/screens/admin_vencimientos_menu_screen.dart';
import '../../reports/screens/admin_reports_screen.dart';
import '../../revisions/screens/admin_revisiones_screen.dart';
import '../../sync_dashboard/screens/sync_dashboard_screen.dart';
import '../../vehicles/screens/admin_mantenimiento_screen.dart';
import '../../vehicles/screens/admin_vehiculos_lista_screen.dart';

import 'admin_estado_bot_screen.dart';
import 'admin_panel_screen.dart';
import 'admin_volvo_alertas_screen.dart';

/// Shell principal del admin con navegación lateral.
///
/// - **Desktop (≥ 800px)**: NavigationRail a la izquierda con labels.
/// - **Mobile (< 800px)**: BottomNavigationBar abajo con iconos.
///
/// Cada sección renderiza la pantalla correspondiente "embebida"
/// (sin AppBar propio — el shell tiene su propio AppBar dinámico).
///
/// El badge de "Revisiones" se actualiza en tiempo real escuchando
/// la colección REVISIONES de Firestore.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _currentIndex = 0;

  // ============= LISTENER de notificaciones (avisos al admin) =============
  StreamSubscription? _revisionesSubscription;
  bool _esPrimeraCarga = true;

  /// Definición declarativa de las secciones del shell.
  /// Cada una incluye su pantalla, label, icon y un builder opcional
  /// para badges dinámicos.
  late final List<_ShellSection> _sections = [
    _ShellSection(
      label: 'Inicio',
      icon: Icons.dashboard_outlined,
      iconActive: Icons.dashboard,
      build: () => const AdminPanelScreen(),
      requiredCapability: Capability.verPanelAdmin,
    ),
    _ShellSection(
      label: 'Revisiones',
      icon: Icons.fact_check_outlined,
      iconActive: Icons.fact_check,
      requiredCapability: Capability.verRevisiones,
      badgeStream: FirebaseFirestore.instance
          .collection('REVISIONES')
          .snapshots(),
      build: () => const AdminRevisionesScreen(),
    ),
    _ShellSection(
      label: 'Flota',
      icon: Icons.local_shipping_outlined,
      iconActive: Icons.local_shipping,
      build: () => const AdminVehiculosListaScreen(),
      requiredCapability: Capability.verListaFlota,
    ),
    _ShellSection(
      label: 'Service',
      icon: Icons.build_circle_outlined,
      iconActive: Icons.build_circle,
      requiredCapability: Capability.verMantenimiento,
      // Badge: cuenta tractores que cruzaron a VENCIDO. La colección
      // se popula desde VehiculoManager._evaluarMantenimiento; al
      // sumar/sacar un tractor del estado, el badge se actualiza solo.
      // Filtro simple por un solo campo, no necesita índice compuesto.
      badgeStream: FirebaseFirestore.instance
          .collection('MANTENIMIENTOS_AVISADOS')
          .where('ultimo_estado', isEqualTo: 'VENCIDO')
          .snapshots(),
      build: () => const AdminMantenimientoScreen(),
    ),
    _ShellSection(
      label: 'Alertas',
      icon: Icons.notifications_active_outlined,
      iconActive: Icons.notifications_active,
      requiredCapability: Capability.verAlertasVolvo,
      // Badge: cuenta alertas pendientes (atendida == false). Single
      // field where → no necesita índice compuesto. Las popula el
      // poller cada 5 min desde el Vehicle Alerts API de Volvo.
      badgeStream: FirebaseFirestore.instance
          .collection('VOLVO_ALERTAS')
          .where('atendida', isEqualTo: false)
          .snapshots(),
      build: () => const AdminVolvoAlertasScreen(),
    ),
    _ShellSection(
      label: 'Personal',
      icon: Icons.badge_outlined,
      iconActive: Icons.badge,
      build: () => const AdminPersonalListaScreen(),
      requiredCapability: Capability.verListaPersonal,
    ),
    _ShellSection(
      label: 'Vencimientos',
      icon: Icons.assignment_late_outlined,
      iconActive: Icons.assignment_late,
      build: () => const AdminVencimientosMenuScreen(),
      requiredCapability: Capability.verVencimientos,
    ),
    _ShellSection(
      label: 'Reportes',
      icon: Icons.analytics_outlined,
      iconActive: Icons.analytics,
      build: () => const AdminReportsScreen(),
      requiredCapability: Capability.verReportes,
    ),
    _ShellSection(
      label: 'Sync',
      icon: Icons.monitor_heart_outlined,
      iconActive: Icons.monitor_heart,
      build: () => const SyncDashboardScreen(),
      requiredCapability: Capability.verSyncDashboard,
    ),
    _ShellSection(
      label: 'Estado Bot',
      icon: Icons.smart_toy_outlined,
      iconActive: Icons.smart_toy,
      build: () => const AdminEstadoBotScreen(),
      requiredCapability: Capability.verEstadoBot,
    ),
  ];

  /// Subset de `_sections` que el usuario logueado puede ver, segun
  /// las capabilities de su rol. Las secciones sin `requiredCapability`
  /// (ej. Inicio, si no la tuviera) se muestran siempre.
  List<_ShellSection> get _seccionesVisibles {
    final rol = PrefsService.rol;
    return _sections.where((s) {
      final cap = s.requiredCapability;
      return cap == null || Capabilities.can(rol, cap);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _activarEscuchaRevisiones();
  }

  @override
  void dispose() {
    _revisionesSubscription?.cancel();
    super.dispose();
  }

  /// Escucha nuevas revisiones para mostrar notificación push al admin.
  /// La primera carga se ignora para no spamear con todo lo que ya estaba.
  void _activarEscuchaRevisiones() {
    _revisionesSubscription = FirebaseFirestore.instance
        .collection('REVISIONES')
        .snapshots()
        .listen(
      (snapshot) {
        if (_esPrimeraCarga) {
          _esPrimeraCarga = false;
          return;
        }
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final data = change.doc.data();
            if (data != null) {
              NotificationService.mostrarAvisoAdmin(
                chofer: data['nombre_usuario'] ?? 'Un chofer',
                documento: data['etiqueta'] ?? 'documento',
              );
            }
          }
        }
      },
      onError: (e) => debugPrint('Error stream revisiones: $e'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final esDesktop = MediaQuery.of(context).size.width >= 800;
    final visibles = _seccionesVisibles;
    // Clamp defensivo: si el rol cambia mid-session y la seccion
    // actual deja de ser visible (caso raro), volvemos al primer
    // destino disponible.
    if (_currentIndex >= visibles.length) _currentIndex = 0;
    final section = visibles[_currentIndex];

    return Scaffold(
      // El shell tiene su propio AppBar y fondo
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          section.label.toUpperCase(),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        actions: [
          // Botón visible para abrir el palette desde la AppBar — además
          // de Ctrl+K — para que los admins que no recuerden el atajo
          // puedan acceder igual.
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Búsqueda rápida (Ctrl+K)',
            onPressed: () => CommandPalette.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            tooltip: 'Volver al menú principal',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: CommandPaletteShortcut(
        child: Stack(
          children: [
            // Fondo unificado (se ve a través del rail/bottombar)
            Positioned.fill(
              child: Image.asset(
                'assets/images/fondo_login.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Theme.of(context).scaffoldBackgroundColor,
                ),
              ),
            ),
            Positioned.fill(
              child: Container(color: Colors.black.withAlpha(200)),
            ),
            // Layout responsive
            SafeArea(
              child: esDesktop
                  ? _buildDesktopLayout(section)
                  : _buildMobileLayout(section),
            ),
          ],
        ),
      ),
      bottomNavigationBar: esDesktop ? null : _buildBottomBar(),
    );
  }

  // ===========================================================================
  // LAYOUT DESKTOP — Rail + contenido
  // ===========================================================================
  Widget _buildDesktopLayout(_ShellSection section) {
    return Row(
      children: [
        _buildNavigationRail(),
        Container(width: 1, color: Colors.white10),
        Expanded(
          child: AppShellContext(
            isEmbedded: true,
            child: section.build(),
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationRail() {
    return NavigationRail(
      selectedIndex: _currentIndex,
      onDestinationSelected: (i) => setState(() => _currentIndex = i),
      labelType: NavigationRailLabelType.all,
      backgroundColor: Colors.transparent,
      selectedIconTheme:
          const IconThemeData(color: Colors.greenAccent, size: 26),
      unselectedIconTheme:
          const IconThemeData(color: Colors.white54, size: 24),
      selectedLabelTextStyle: const TextStyle(
        color: Colors.greenAccent,
        fontWeight: FontWeight.bold,
        fontSize: 11,
      ),
      unselectedLabelTextStyle: const TextStyle(
        color: Colors.white54,
        fontSize: 11,
      ),
      indicatorColor: Colors.greenAccent.withAlpha(40),
      destinations: _seccionesVisibles
          .asMap()
          .entries
          .map(
            (e) => NavigationRailDestination(
              icon: _buildIconWithBadge(e.value, e.key, esActiva: false),
              selectedIcon:
                  _buildIconWithBadge(e.value, e.key, esActiva: true),
              label: Text(e.value.label),
            ),
          )
          .toList(),
    );
  }

  // ===========================================================================
  // LAYOUT MOBILE — solo contenido, BottomBar abajo
  // ===========================================================================
  Widget _buildMobileLayout(_ShellSection section) {
    return AppShellContext(
      isEmbedded: true,
      child: section.build(),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.white.withAlpha(15))),
      ),
      child: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        backgroundColor: Colors.transparent,
        height: 70,
        labelBehavior:
            NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: _seccionesVisibles
            .asMap()
            .entries
            .map(
              (e) => NavigationDestination(
                icon: _buildIconWithBadge(e.value, e.key, esActiva: false),
                selectedIcon:
                    _buildIconWithBadge(e.value, e.key, esActiva: true),
                label: e.value.label,
              ),
            )
            .toList(),
      ),
    );
  }

  // ===========================================================================
  // BADGE
  // ===========================================================================

  /// Renderiza el icono de la sección, agregando el badge rojo si tiene
  /// un stream de pendientes con docs > 0.
  Widget _buildIconWithBadge(
    _ShellSection section,
    int index, {
    required bool esActiva,
  }) {
    final icon = Icon(esActiva ? section.iconActive : section.icon);
    if (section.badgeStream == null) return icon;

    return StreamBuilder<QuerySnapshot>(
      stream: section.badgeStream,
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        if (count == 0) return icon;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            icon,
            Positioned(
              right: -6,
              top: -4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                constraints: const BoxConstraints(
                  minWidth: 18,
                  minHeight: 18,
                ),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Estructura interna que define cada sección del shell.
class _ShellSection {
  final String label;
  final IconData icon;
  final IconData iconActive;
  final Widget Function() build;
  final Stream<QuerySnapshot>? badgeStream;

  /// Capability requerida para que la seccion sea visible en el rail/
  /// bottombar. Si `null`, siempre se muestra (ej. 'Inicio').
  final Capability? requiredCapability;

  _ShellSection({
    required this.label,
    required this.icon,
    required this.iconActive,
    required this.build,
    this.badgeStream,
    this.requiredCapability,
  });
}


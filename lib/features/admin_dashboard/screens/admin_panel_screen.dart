import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/notification_service.dart';
import '../../../shared/widgets/app_widgets.dart';

/// Panel de administración — menú principal del rol ADMIN.
///
/// Muestra accesos a las distintas secciones de gestión, con un contador
/// reactivo de revisiones pendientes (badge rojo).
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  StreamSubscription? _revisionesSubscription;
  bool _esPrimeraCarga = true;

  late final Stream<QuerySnapshot> _pendientesStream;

  @override
  void initState() {
    super.initState();

    // Como al aprobar/rechazar las solicitudes se ELIMINAN del Firestore,
    // todo lo que existe en la colección está pendiente por definición.
    _pendientesStream = FirebaseFirestore.instance
        .collection('REVISIONES')
        .snapshots();

    _activarEscuchaRevisiones();
  }

  @override
  void dispose() {
    _revisionesSubscription?.cancel();
    super.dispose();
  }

  /// Listener separado para disparar notificación push cuando llega una
  /// revisión nueva. La primera carga se ignora para no spamear al admin
  /// con todas las que ya estaban al abrir la pantalla.
  void _activarEscuchaRevisiones() {
    _revisionesSubscription?.cancel();

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
      onError: (error) {
        debugPrint('Error en stream de revisiones: $error');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'S.M.A.R.T. Logística',
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        children: [
          const SizedBox(height: 8),

          // Tile especial: revisiones pendientes con badge reactivo
          StreamBuilder<QuerySnapshot>(
            stream: _pendientesStream,
            builder: (context, snap) {
              if (snap.hasError) {
                return const _AdminTile(
                  titulo: 'REVISIONES PENDIENTES',
                  subtitulo: 'Error de conexión',
                  icono: Icons.error_outline,
                  color: Colors.redAccent,
                  ruta: '/admin_revisiones',
                );
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return const _AdminTile(
                  titulo: 'REVISIONES PENDIENTES',
                  subtitulo: 'Sincronizando...',
                  icono: Icons.sync,
                  color: Colors.greenAccent,
                  ruta: '/admin_revisiones',
                );
              }
              final pendientes = snap.data?.docs.length ?? 0;
              return _AdminTile(
                titulo: 'REVISIONES PENDIENTES',
                subtitulo: pendientes > 0
                    ? 'Atención: hay $pendientes trámites'
                    : 'No hay trámites pendientes',
                icono: Icons.fact_check_outlined,
                color: pendientes > 0
                    ? Colors.orangeAccent
                    : Colors.greenAccent,
                ruta: '/admin_revisiones',
                badgeCount: pendientes,
              );
            },
          ),

          const _AdminTile(
            titulo: 'SYNC OBSERVABILITY',
            subtitulo: 'Monitoreo en tiempo real de sincronización',
            icono: Icons.monitor_heart_outlined,
            color: Colors.cyanAccent,
            ruta: AppRoutes.syncDashboard,
          ),
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
            subtitulo: 'Alertas críticas de documentos',
            icono: Icons.assignment_late_outlined,
            color: Colors.redAccent,
            ruta: '/admin_vencimientos_menu',
          ),
          const _AdminTile(
            titulo: 'CENTRO DE REPORTES',
            subtitulo: 'Exportar Excel y analítica de flota',
            icono: Icons.analytics_outlined,
            color: Colors.amberAccent,
            ruta: '/admin_reportes',
          ),

          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                'v 1.0.7 — Base Operativa',
                style: TextStyle(
                  color: Colors.white24,
                  fontSize: 11,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// TILE DEL MENÚ ADMIN (con badge opcional)
// =============================================================================

class _AdminTile extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final IconData icono;
  final Color color;
  final String ruta;
  final int badgeCount;

  const _AdminTile({
    required this.titulo,
    required this.subtitulo,
    required this.icono,
    required this.color,
    required this.ruta,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => Navigator.pushNamed(context, ruta),
      // Si tiene badge, destacamos la tarjeta con borde de color
      highlighted: badgeCount > 0,
      borderColor: badgeCount > 0 ? color.withAlpha(150) : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: Icon(icono, color: color, size: 26),
              ),
              if (badgeCount > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.surface,
                        width: 2,
                      ),
                    ),
                    child: Text(
                      '$badgeCount',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitulo,
                  style: const TextStyle(
                      color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios,
              color: Colors.white24, size: 16),
        ],
      ),
    );
  }
}

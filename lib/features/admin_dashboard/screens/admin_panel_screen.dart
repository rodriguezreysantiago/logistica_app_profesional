import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/constants/app_constants.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  StreamSubscription? _revisionesSubscription;
  bool _esPrimeraCarga = true; 
  
  // ✅ MENTOR: Stream en caché, excelente práctica.
  late Stream<QuerySnapshot> _pendientesStream;

  @override
  void initState() {
    super.initState();
    
    _pendientesStream = FirebaseFirestore.instance
        .collection('REVISIONES')
        .where('estado', isEqualTo: 'PENDIENTE') 
        .snapshots();

    _activarEscuchaRevisiones();
  }

  @override
  void dispose() {
    _revisionesSubscription?.cancel();
    super.dispose();
  }

  void _activarEscuchaRevisiones() {
    _revisionesSubscription?.cancel();
    
    _revisionesSubscription = FirebaseFirestore.instance
        .collection('REVISIONES')
        .where('estado', isEqualTo: 'PENDIENTE')
        .snapshots()
        .listen((snapshot) {
      
      if (_esPrimeraCarga) {
        _esPrimeraCarga = false;
        return;
      }

      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          try {
            final data = change.doc.data();
            if (data != null) {
              NotificationService.mostrarAvisoAdmin(
                chofer: data['nombre_usuario'] ?? "Un chofer",
                documento: data['etiqueta'] ?? "documento",
              );
            }
          } catch (e) {
            debugPrint("Error en radar de notificaciones: $e");
          }
        }
      }
    }, onError: (error) {
      debugPrint("Error en el stream de revisiones: $error");
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("S.M.A.R.T. Logística", 
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/fondo_login.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => 
                  Container(color: Theme.of(context).scaffoldBackgroundColor), 
            ),
          ),
          Positioned.fill(child: Container(color: Colors.black.withAlpha(200))),
          
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              children: [
                const SizedBox(height: 10),
                
                StreamBuilder<QuerySnapshot>(
                  stream: _pendientesStream,
                  builder: (context, snap) {
                    
                    if (snap.hasError) {
                      return _buildOption(
                        context,
                        "REVISIONES PENDIENTES",
                        "Error de conexión",
                        Icons.error_outline,
                        Colors.redAccent,
                        '/admin_revisiones',
                        badgeCount: 0,
                      );
                    }

                    if (snap.connectionState == ConnectionState.waiting) {
                       return _buildOption(
                        context,
                        "REVISIONES PENDIENTES",
                        "Sincronizando...",
                        Icons.sync,
                        Theme.of(context).colorScheme.primary,
                        '/admin_revisiones',
                        badgeCount: 0,
                      );
                    }

                    int pendientes = snap.data?.docs.length ?? 0;
                    
                    return _buildOption(
                      context,
                      "REVISIONES PENDIENTES",
                      pendientes > 0 ? "Atención: hay $pendientes trámites" : "No hay trámites pendientes",
                      Icons.fact_check_outlined,
                      pendientes > 0 ? Colors.orangeAccent : Colors.greenAccent,
                      '/admin_revisiones',
                      badgeCount: pendientes,
                    );
                  }
                ),
                const SizedBox(height: 15),

_buildOption(
  context,
  "SYNC OBSERVABILITY",
  "Monitoreo en tiempo real de sincronización (Grafana Mode)",
  Icons.monitor_heart_outlined,
  Colors.cyanAccent,
  AppRoutes.syncDashboard,
),
                const SizedBox(height: 15),
                _buildOption(context, "GESTIÓN DE PERSONAL", "Lista de legajos y choferes", Icons.badge_outlined, Colors.blueAccent, '/admin_personal_lista'),
                const SizedBox(height: 15),
                _buildOption(context, "GESTIÓN DE FLOTA", "Control de camiones y acoplados", Icons.local_shipping_outlined, Colors.purpleAccent, '/admin_vehiculos_lista'),
                const SizedBox(height: 15),
                _buildOption(context, "AUDITORÍA DE VENCIMIENTOS", "Alertas críticas de documentos", Icons.assignment_late_outlined, Colors.redAccent, '/admin_vencimientos_menu'),
                const SizedBox(height: 15),
                
                _buildOption(
                  context, 
                  "CENTRO DE REPORTES", 
                  "Exportar Excel y analítica de flota", 
                  Icons.analytics_outlined, 
                  Colors.amberAccent, 
                  '/admin_reportes'
                ),

                const SizedBox(height: 30),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text("v 1.0.7 - Base Operativa", 
                      style: TextStyle(color: Colors.white24, fontSize: 11, letterSpacing: 1))
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ✅ MENTOR: Ajuste estético para heredar el Theme y perfeccionar el Ripple Effect
  Widget _buildOption(BuildContext context, String titulo, String subtitulo, IconData icono, Color color, String ruta, {int badgeCount = 0}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface, // Cristal oscuro global
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: badgeCount > 0 ? color.withAlpha(150) : Colors.white.withAlpha(15), 
          width: badgeCount > 0 ? 1.5 : 1
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => Navigator.pushNamed(context, ruta),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            leading: Stack(
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
                    right: -4, top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.redAccent, 
                        shape: BoxShape.circle,
                        border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2)
                      ),
                      child: Text("$badgeCount", style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
            title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14, letterSpacing: 0.5)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(subtitulo, style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ),
            trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 16),
          ),
        ),
      ),
    );
  }
}


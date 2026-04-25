import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/services/notification_service.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  StreamSubscription? _revisionesSubscription;
  bool _esPrimeraCarga = true; // ✅ ESCUDO ANTI-SPAM

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

  void _activarEscuchaRevisiones() {
    _revisionesSubscription?.cancel();
    _revisionesSubscription = FirebaseFirestore.instance
        .collection('REVISIONES')
        .snapshots()
        .listen((snapshot) {
      
      // ✅ Si es la primera vez que carga, marcamos false y abortamos.
      // Así evitamos que salten notificaciones por trámites viejos.
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
                  Container(color: const Color(0xFF0D1D2D)),
            ),
          ),
          Positioned.fill(child: Container(color: Colors.black.withAlpha(180))),
          
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              children: [
                const SizedBox(height: 10),
                
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('REVISIONES').snapshots(),
                  builder: (context, snap) {
                    int pendientes = snap.hasData ? snap.data!.docs.length : 0;
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
                _buildOption(context, "GESTIÓN DE PERSONAL", "Lista de legajos y choferes", Icons.badge_outlined, Colors.blue.shade400, '/admin_personal_lista'),
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
                    child: Text("v 1.0.7 - Flete MB", 
                      style: TextStyle(color: Colors.white24, fontSize: 10))
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOption(BuildContext context, String titulo, String subtitulo, IconData icono, Color color, String ruta, {int badgeCount = 0}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withAlpha(badgeCount > 0 ? 180 : 40), width: badgeCount > 0 ? 1.5 : 0.8),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              backgroundColor: color.withAlpha(40), 
              child: Icon(icono, color: color)
            ),
            if (badgeCount > 0)
              Positioned(
                right: -4, top: -4,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: Text("$badgeCount", style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15)),
        subtitle: Text(subtitulo, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 16),
        onTap: () => Navigator.pushNamed(context, ruta),
      ),
    );
  }
}
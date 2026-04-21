import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// 1. IMPORTANTE: Verificá que esta ruta sea la correcta en tu proyecto
import '../../core/services/volvo_api_service.dart'; 
import '../../core/services/notification_service.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  StreamSubscription? _revisionesSubscription;

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
    _revisionesSubscription = FirebaseFirestore.instance
        .collection('REVISIONES')
        .snapshots()
        .listen((snapshot) {
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
            debugPrint("Error en radar: $e");
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
        title: const Text("S.M.A.R.T. Logística"),
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
          Positioned.fill(
            child: Container(color: Colors.black.withAlpha(160)),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              children: [
                const SizedBox(height: 10),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('REVISIONES').snapshots(),
                  builder: (context, snap) {
                    int pendientes = snap.hasData ? snap.data!.docs.length : 0;
                    return _buildOption(
                      context,
                      "REVISIONES PENDIENTES",
                      pendientes > 0 ? "Hay $pendientes trámites por validar" : "Todo al día",
                      Icons.fact_check,
                      pendientes > 0 ? Colors.orangeAccent : Colors.greenAccent,
                      '/admin_revisiones',
                      badgeCount: pendientes,
                    );
                  }
                ),
                const SizedBox(height: 15),
                _buildOption(context, "GESTIÓN DE PERSONAL", "Lista de legajos y choferes", Icons.badge, Colors.blue.shade400, '/admin_personal_lista'),
                const SizedBox(height: 15),
                _buildOption(context, "GESTIÓN DE FLOTA", "Control de camiones y acoplados", Icons.local_shipping, Colors.purpleAccent, '/admin_vehiculos_lista'),
                const SizedBox(height: 15),
                _buildOption(context, "AUDITORÍA DE VENCIMIENTOS", "Alertas críticas de documentos", Icons.assignment_late, Colors.redAccent, '/admin_vencimientos_menu'),
                const SizedBox(height: 40),
                
                _buildVolvoTestButton(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOption(BuildContext context, String titulo, String subtitulo, IconData icono, Color color, String ruta, {int badgeCount = 0}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(40)),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(backgroundColor: color.withAlpha(200), child: Icon(icono, color: Colors.white)),
              if (badgeCount > 0)
                Positioned(
                  right: -5,
                  top: -5,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: Text("$badgeCount", style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          subtitle: Text(subtitulo, style: const TextStyle(color: Colors.white70)),
          trailing: const Icon(Icons.chevron_right, color: Colors.white54),
          onTap: () {
            if (mounted) Navigator.pushNamed(context, ruta);
          },
        ),
      ),
    );
  }

  Widget _buildVolvoTestButton(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.withAlpha(25),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.blueAccent.withAlpha(75)),
      ),
      child: ListTile(
        onTap: () => _ejecutarTestVolvo(context),
        leading: const Icon(Icons.api, color: Colors.blueAccent),
        title: const Text("TEST API VOLVO CONNECT",
          style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: const Text("Prueba de conexión y lectura de datos en tiempo real",
          style: TextStyle(color: Colors.white54, fontSize: 11),
        ),
        trailing: const Icon(Icons.play_circle_fill, color: Colors.blueAccent),
      ),
    );
  }

  // MÉTODO CORREGIDO PARA FUNCIONAR CON TU CONFIGURACIÓN DE VOLVO
  void _ejecutarTestVolvo(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text("Consultando datos en Volvo Cloud..."), backgroundColor: Colors.blue),
    );

    try {
      // 1. Instanciamos el servicio oficial
      final service = VolvoApiService();
      
      // 2. Llamamos al método que trae los datos de la flota
      final unidades = await service.traerDatosFlota();

      if (mounted) {
        if (unidades.isNotEmpty) {
          // Si encontró camiones, mostramos el éxito
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text("¡Éxito! Se conectó con Volvo y leyó ${unidades.length} camiones."),
              backgroundColor: Colors.green,
            ),
          );
          
          // Imprimimos en la consola los detalles para que los veas
          debugPrint("--- DATOS VOLVO RECIBIDOS ---");
          for (var u in unidades) {
            debugPrint("VIN: ${u['vin']} | KM: ${u['hrTotalVehicleDistance'] / 1000}km");
          }
        } else {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text("Conectado a Volvo, pero la lista de camiones está vacía."),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error detallado en la UI: $e");
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text("Error en el test: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }
}
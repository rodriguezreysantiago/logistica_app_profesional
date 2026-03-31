import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/utils/formatters.dart';

class UserMiEquipoScreen extends StatelessWidget {
  final String dniUser;

  const UserMiEquipoScreen({super.key, required this.dniUser});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mi Equipo"),
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<DocumentSnapshot>(
        // 1. Buscamos primero al EMPLEADO para saber qué patentes tiene asignadas
        future: FirebaseFirestore.instance.collection('EMPLEADOS').doc(dniUser).get(),
        builder: (context, empleadoSnapshot) {
          if (empleadoSnapshot.hasError) return const Center(child: Text("Error al cargar empleado"));
          if (empleadoSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!empleadoSnapshot.hasData || !empleadoSnapshot.data!.exists) {
            return const Center(child: Text("No se encontró el perfil del usuario"));
          }

          var empleadoData = empleadoSnapshot.data!.data() as Map<String, dynamic>;
          String patenteTractor = empleadoData['TRACTOR'] ?? "";
          String patenteAcoplado = empleadoData['BATEA_TOLVA'] ?? "";

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // SECCIÓN CHASIS (TRACTOR)
              _buildSeccionUnidad("CHASIS (TRACTOR)", patenteTractor),
              const SizedBox(height: 25),
              // SECCIÓN ACOPLADO (BATEA / TOLVA)
              _buildSeccionUnidad("ACOPLADO (BATEA/TOLVA)", patenteAcoplado),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSeccionUnidad(String titulo, String patente) {
    if (patente.isEmpty || patente == "SIN ASIGNAR") {
      return _cardVacia(titulo);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A3A5A))),
        const Divider(),
        StreamBuilder<DocumentSnapshot>(
          // 2. Buscamos en la colección VEHICULOS usando la patente como ID
          stream: FirebaseFirestore.instance.collection('VEHICULOS').doc(patente).snapshots(),
          builder: (context, vehiculoSnapshot) {
            if (!vehiculoSnapshot.hasData || !vehiculoSnapshot.data!.exists) {
              return _cardVacia(titulo, sub: "Datos de $patente no encontrados en VEHICULOS");
            }

            var v = vehiculoSnapshot.data!.data() as Map<String, dynamic>;
            int diasRto = AppFormatters.calcularDiasRestantes(v['VENCIMIENTO_RTO']);

            return Card(
              elevation: 4,
              child: ListTile(
                leading: Icon(Icons.local_shipping, 
                  color: diasRto < 0 ? Colors.red : (diasRto < 15 ? Colors.orange : Colors.green), size: 35),
                title: Text(patente, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                subtitle: Text("${v['MARCA']} ${v['MODELO']}\nVto. RTO: ${AppFormatters.formatearFecha(v['VENCIMIENTO_RTO'])}"),
                isThreeLine: true,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _cardVacia(String titulo, {String sub = "Sin unidad asignada"}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
        Card(
          color: Colors.grey.shade100,
          child: ListTile(
            leading: const Icon(Icons.not_interested, color: Colors.grey),
            title: Text(sub, style: const TextStyle(color: Colors.grey)),
          ),
        ),
      ],
    );
  }
}
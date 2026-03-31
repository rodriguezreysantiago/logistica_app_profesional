import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/utils/formatters.dart';

class UserMisVencimientosScreen extends StatelessWidget {
  final String dniUser;

  const UserMisVencimientosScreen({super.key, required this.dniUser});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mis Vencimientos"),
        backgroundColor: Colors.teal.shade700,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('EMPLEADOS').doc(dniUser).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text("Error al cargar datos"));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("No se encontraron datos"));
          }

          var data = snapshot.data!.data() as Map<String, dynamic>;
          String patenteTractor = data['TRACTOR'] ?? "";
          String patenteAcoplado = data['BATEA_TOLVA'] ?? "";

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // --- SECCIÓN PERSONAL ---
              _buildTituloPrincipal("DOCUMENTACIÓN PERSONAL"),
              _buildCardVencimiento("Licencia de Conducir", data['LIC_COND']),
              _buildCardVencimiento("Curso de Manejo (LINTI)", data['CURSO_MANEJO']),
              _buildCardVencimiento("EPAP / Psicofísico", data['EPAP']),

              const SizedBox(height: 30),

              // --- SECCIÓN EQUIPO ASIGNADO ---
              _buildTituloPrincipal("VENCIMIENTOS DE EQUIPO"),
              
              // Bloque del CHASIS
              _buildSubtituloUnidad("CHASIS", patenteTractor),
              if (patenteTractor.isNotEmpty && patenteTractor != "SIN ASIGNAR")
                _buildDetalleVehiculo(patenteTractor)
              else
                _buildCardVacia("No hay chasis asignado"),

              const SizedBox(height: 20),

              // Bloque del ACOPLADO
              _buildSubtituloUnidad("ACOPLADO", patenteAcoplado),
              if (patenteAcoplado.isNotEmpty && patenteAcoplado != "SIN ASIGNAR")
                _buildDetalleVehiculo(patenteAcoplado)
              else
                _buildCardVacia("No hay acoplado asignado"),
            ],
          );
        },
      ),
    );
  }

  // --- COMPONENTES VISUALES ---

  Widget _buildTituloPrincipal(String titulo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        titulo,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A3A5A)),
      ),
    );
  }

  Widget _buildSubtituloUnidad(String tipo, String patente) {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(tipo, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          Text(patente.isNotEmpty ? patente : "S/D", style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDetalleVehiculo(String patente) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('VEHICULOS').doc(patente).snapshots(),
      builder: (context, vehiculoSnap) {
        if (!vehiculoSnap.hasData || !vehiculoSnap.data!.exists) {
          return _buildCardVacia("Patente $patente no encontrada en sistema");
        }

        var vData = vehiculoSnap.data!.data() as Map<String, dynamic>;
        return Column(
          children: [
            _buildCardVencimiento("RTO", vData['VENCIMIENTO_RTO']),
            _buildCardVencimiento("Póliza de Seguro", vData['VENCIMIENTO_POLIZA']),
          ],
        );
      },
    );
  }

  Widget _buildCardVencimiento(String titulo, String? fecha) {
    int dias = AppFormatters.calcularDiasRestantes(fecha);
    Color colorEstado = dias < 0 ? Colors.red : (dias < 15 ? Colors.orange : Colors.green);
    
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        dense: true,
        leading: Icon(Icons.circle, color: colorEstado, size: 12),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text("Vence: ${AppFormatters.formatearFecha(fecha)}"),
        trailing: Text(
          dias < 0 ? "VENCIDO" : "$dias días",
          style: TextStyle(color: colorEstado, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildCardVacia(String mensaje) {
    return Card(
      color: Colors.grey.shade50,
      child: ListTile(
        dense: true,
        title: Text(mensaje, style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
      ),
    );
  }
}
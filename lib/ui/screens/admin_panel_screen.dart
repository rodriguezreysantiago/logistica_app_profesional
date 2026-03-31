import 'package:flutter/material.dart';

class AdminPanelScreen extends StatelessWidget {
  const AdminPanelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Panel de Control Administrativo"),
        backgroundColor: const Color(0xFFB71C1C),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildOption(
            context, 
            "GESTIÓN DE PERSONAL", 
            "Lista de legajos y choferes", 
            Icons.badge, 
            Colors.blue.shade900, 
            '/admin_personal_lista'
          ),
          const SizedBox(height: 15),
          _buildOption(
            context, 
            "GESTIÓN DE FLOTA", 
            "Control de camiones y acoplados", 
            Icons.local_shipping, 
            Colors.orange.shade900, 
            '/admin_vehiculos_lista'
          ),
          const SizedBox(height: 15),
          _buildOption(
            context, 
            "AUDITORÍA DE VENCIMIENTOS", 
            "Alertas críticas de documentos", 
            Icons.fact_check, 
            Colors.red.shade700, 
            '/admin_vencimientos_menu'
          ),
        ],
      ),
    );
  }

  Widget _buildOption(BuildContext context, String titulo, String subtitulo, IconData icono, Color color, String ruta) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(15),
        leading: CircleAvatar(
          backgroundColor: color, 
          child: Icon(icono, color: Colors.white)
        ),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitulo),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.pushNamed(context, ruta);
        },
      ),
    );
  }
}
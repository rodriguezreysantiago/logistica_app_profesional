import 'package:flutter/material.dart';

class AdminVencimientosMenuScreen extends StatelessWidget {
  const AdminVencimientosMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Auditoría Crítica"),
        backgroundColor: const Color(0xFF1A3A5A),
        foregroundColor: Colors.white,
      ),
      body: ListView( // Cambiado a ListView para mejor scroll si crece el menú
        children: [
          // SECCIÓN DE SOLICITUDES ENTRANTES (Lo que envían los choferes)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text("PENDIENTES DE APROBACIÓN", 
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ),
          _tile(
            context, 
            "Revisiones de Choferes", 
            Icons.notification_important, 
            '/admin_revisiones', // Asegurate de registrar esta ruta en tu main.dart
            colorIcon: Colors.orange.shade700
          ),
          
          const Divider(),

          // SECCIÓN DE CONSULTA GENERAL
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Text("AUDITORÍA GENERAL", 
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ),
          _tile(context, "Vencimientos de Choferes", Icons.person_search, '/vencimientos_choferes'),
          _tile(context, "Vencimientos de Chasis", Icons.engineering, '/vencimientos_chasis'),
          _tile(context, "Vencimientos de Acoplados", Icons.ad_units, '/vencimientos_acoplados'),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, String t, IconData i, String r, {Color colorIcon = Colors.red}) {
    return Card( // Agregamos un Card para que se vea más moderno
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0.5,
      child: ListTile(
        leading: Icon(i, color: colorIcon),
        title: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
        onTap: () => Navigator.pushNamed(context, r),
      ),
    );
  }
}
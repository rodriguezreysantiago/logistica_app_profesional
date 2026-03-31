import 'package:flutter/material.dart';

class AdminVencimientosMenuScreen extends StatelessWidget {
  const AdminVencimientosMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Auditoría Crítica")),
      body: Column(
        children: [
          _tile(context, "Vencimientos de Choferes", Icons.person_search, '/vencimientos_choferes'),
          _tile(context, "Vencimientos de Chasis", Icons.engineering, '/vencimientos_chasis'),
          _tile(context, "Vencimientos de Acoplados", Icons.ad_units, '/vencimientos_acoplados'),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, String t, IconData i, String r) {
    return ListTile(
      leading: Icon(i, color: Colors.red),
      title: Text(t),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () => Navigator.pushNamed(context, r),
    );
  }
}
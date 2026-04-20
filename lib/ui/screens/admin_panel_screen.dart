import 'package:flutter/material.dart';
import '../../migration_service.dart';

class AdminPanelScreen extends StatelessWidget {
  const AdminPanelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Panel de Control Administrativo"),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // 1. Imagen de fondo
          Positioned.fill(
            child: Image.asset(
              'assets/images/fondo_login.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: Colors.blueGrey.shade900),
            ),
          ),

          // 2. Filtro oscuro
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.6),
            ),
          ),

          // 3. Contenido del Menú
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              children: [
                const SizedBox(height: 10),
                _buildOption(
                    context,
                    "GESTIÓN DE PERSONAL",
                    "Lista de legajos y choferes",
                    Icons.badge,
                    Colors.blue.shade400,
                    '/admin_personal_lista'),
                const SizedBox(height: 15),
                _buildOption(
                    context,
                    "GESTIÓN DE FLOTA",
                    "Control de camiones y acoplados",
                    Icons.local_shipping,
                    Colors.orangeAccent,
                    '/admin_vehiculos_lista'),
                const SizedBox(height: 15),
                _buildOption(
                    context,
                    "AUDITORÍA DE VENCIMIENTOS",
                    "Alertas críticas de documentos",
                    Icons.fact_check,
                    Colors.redAccent,
                    '/admin_vencimientos_menu'),
                
                const SizedBox(height: 40), // Espacio extra antes del botón técnico
                
                // --- BOTÓN TEMPORAL DE MIGRACIÓN ---
                _buildMigrationButton(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOption(BuildContext context, String titulo, String subtitulo,
      IconData icono, Color color, String ruta) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.8),
              child: Icon(icono, color: Colors.white)),
          title: Text(titulo,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.white)),
          subtitle: Text(subtitulo,
              style: const TextStyle(color: Colors.white70)),
          trailing: const Icon(Icons.chevron_right, color: Colors.white54),
          onTap: () {
            Navigator.pushNamed(context, ruta);
          },
        ),
      ),
    );
  }

  // Widget separado para el botón de migración
  Widget _buildMigrationButton(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        onTap: () async {
          _confirmarMigracion(context);
        },
        leading: const Icon(Icons.data_exploration, color: Colors.redAccent),
        title: const Text(
          "MIGRAR BASE DE DATOS",
          style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
        ),
        subtitle: const Text(
          "Cambio masivo de campos (Batea/Tractor)",
          style: TextStyle(color: Colors.white54, fontSize: 11),
        ),
        trailing: const Icon(Icons.play_circle_fill, color: Colors.redAccent),
      ),
    );
  }

  // Cuadro de diálogo para evitar errores por accidente
  void _confirmarMigracion(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text("Confirmar Migración", style: TextStyle(color: Colors.white)),
        content: const Text(
            "Se renombrarán los campos de todos los empleados en Firebase. ¿Deseas continuar?",
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
                 await MigrationService.ejecutarMigracionCamposEmpleados();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Migración finalizada")),
                );
              }
            },
            child: const Text("EJECUTAR"),
          ),
        ],
      ),
    );
  }
}
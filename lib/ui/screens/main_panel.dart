import 'package:flutter/material.dart';
import '../widgets/menu_card.dart';

class MainPanel extends StatefulWidget {
  final String dni;
  final String nombre;
  final String rol;

  const MainPanel({
    super.key,
    required this.dni,
    required this.nombre,
    required this.rol,
  });

  @override
  State<MainPanel> createState() => _MainPanelState();
}

class _MainPanelState extends State<MainPanel> {
  // ✅ Se eliminó la función _mostrarSubMenuAdmin porque ahora usamos una pantalla completa

  @override
  Widget build(BuildContext context) {
    // Normalizamos el rol a mayúsculas
    final bool isAdmin = widget.rol.toUpperCase() == 'ADMIN';

    return Scaffold(
      appBar: AppBar(
        title: const Text('S.M.A.R.T. Logística'),
        centerTitle: true,
        backgroundColor: const Color(0xFF1A3A5A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: 'Cerrar Sesión',
            onPressed: () => Navigator.pushReplacementNamed(context, '/'),
          ),
        ],
      ),
      body: Container(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Bienvenido, ${widget.nombre}",
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A3A5A)),
            ),
            const Text(
              "Gestión de flota y documentación",
              style: TextStyle(color: Colors.blueGrey, fontSize: 14),
            ),
            const SizedBox(height: 25),
            Expanded(
              child: GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
                crossAxisSpacing: 18,
                mainAxisSpacing: 18,
                children: [
                  // 1. MI PERFIL
                  MenuCard(
                    titulo: "MI PERFIL",
                    icono: Icons.person_outline,
                    color: Colors.blue.shade700,
                    onTap: () => Navigator.pushNamed(context, '/perfil',
                        arguments: widget.dni),
                  ),

                  // 2. MI EQUIPO
                  MenuCard(
                    titulo: "MI EQUIPO",
                    icono: Icons.local_shipping_outlined,
                    color: Colors.indigo.shade600,
                    onTap: () => Navigator.pushNamed(context, '/equipo',
                        arguments: widget.dni),
                  ),

                  // 3. MIS VENCIMIENTOS
                  MenuCard(
                    titulo: "MIS VENCIMIENTOS",
                    icono: Icons.event_note_outlined,
                    color: Colors.teal.shade700,
                    onTap: () => Navigator.pushNamed(context, '/mis_vencimientos',
                        arguments: widget.dni),
                  ),

                  // 4. ADMINISTRADOR (Ahora lleva al nuevo PANEL DE CONTROL)
                  if (isAdmin)
                    MenuCard(
                      titulo: "ADMINISTRADOR",
                      icono: Icons.admin_panel_settings_outlined,
                      color: Colors.red.shade900,
                      // ✅ CAMBIO CLAVE: Ahora navega a la ruta del panel admin
                      onTap: () => Navigator.pushNamed(context, '/admin_panel'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
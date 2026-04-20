import 'package:flutter/material.dart';
import '../../core/services/prefs_service.dart'; // <--- IMPORTANTE: TU NUEVO SERVICIO

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
  @override
  Widget build(BuildContext context) {
    final bool isAdmin = widget.rol.toUpperCase() == 'ADMIN';

    return Scaffold(
      extendBodyBehindAppBar: true, 
      appBar: AppBar(
        title: const Text('S.M.A.R.T. Logística'),
        centerTitle: true,
        backgroundColor: Colors.transparent, 
        elevation: 0,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: 'Cerrar Sesión',
            onPressed: () async {
              // --- NUEVO: LIMPIAR SESIÓN LOCAL AL SALIR ---
              await PrefsService.clear();
              if (!mounted) return;
              
              // VOLVEMOS AL LOGIN Y LIMPIAMOS EL HISTORIAL DE RUTAS
              Navigator.pushReplacementNamed(context, '/');
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Imagen de Fondo
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/fondo_login.jpg'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          
          // 2. Capa de oscurecimiento
          Container(color: Colors.black.withValues(alpha: 0.45)),

          // 3. Contenido Principal
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: kToolbarHeight + 40), 
                
                // Cabecera Bienvenida
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Bienvenido, ${widget.nombre}",
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        "Gestión de flota y documentación",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7), 
                          fontSize: 14,
                          letterSpacing: 0.5
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 30),

                // 4. Grid de Menú con ICONOS MÁS GRANDES
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 4, 
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.78, 
                    children: [
                      _buildMenuButton(
                        titulo: "MI PERFIL",
                        icono: Icons.person_outline,
                        color: Colors.blueAccent,
                        onTap: () => Navigator.pushNamed(context, '/perfil', arguments: widget.dni),
                      ),
                      _buildMenuButton(
                        titulo: "MI EQUIPO",
                        icono: Icons.local_shipping_outlined,
                        color: Colors.orangeAccent,
                        onTap: () => Navigator.pushNamed(context, '/equipo', arguments: widget.dni),
                      ),
                      _buildMenuButton(
                        titulo: "MIS VENCIMIENTOS",
                        icono: Icons.event_note_outlined,
                        color: Colors.greenAccent,
                        onTap: () => Navigator.pushNamed(context, '/mis_vencimientos', arguments: widget.dni),
                      ),
                      if (isAdmin)
                        _buildMenuButton(
                          titulo: "PANEL ADMINISTRADOR",
                          icono: Icons.admin_panel_settings_outlined,
                          color: Colors.redAccent,
                          onTap: () => Navigator.pushNamed(context, '/admin_panel'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuButton({
    required String titulo,
    required IconData icono,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18), 
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icono, color: color, size: 38), 
            const SizedBox(height: 10),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
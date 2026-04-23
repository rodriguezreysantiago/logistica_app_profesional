import 'package:flutter/material.dart';
import '../../core/services/prefs_service.dart';

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
    final bool isAdmin = widget.rol.trim().toUpperCase() == 'ADMIN';

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
              final navigator = Navigator.of(context);
              await PrefsService.clear();
              if (!mounted) return;
              navigator.pushReplacementNamed('/');
            },
          ),
        ],
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
            child: Center( // Center ayuda a que en Windows no se pegue a la izquierda
              child: ConstrainedBox(
                // LIMITADOR: En Windows no pasará de 600px, en celu usa el ancho disponible
                constraints: const BoxConstraints(maxWidth: 600), 
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      
                      _buildWelcomeHeader(),
                      
                      const SizedBox(height: 30),

                      Expanded(
                        child: GridView.count(
                          // Mantenemos 2 columnas, pero al estar en un contenedor de 600px,
                          // los botones ahora tendrán un tamaño humano en la PC.
                          crossAxisCount: 2, 
                          crossAxisSpacing: 15,
                          mainAxisSpacing: 15,
                          childAspectRatio: 1.2, 
                          children: [
                            _buildMenuButton(
                              titulo: "MI PERFIL",
                              icono: Icons.person_pin_outlined,
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
                              icono: Icons.assignment_late_outlined,
                              color: Colors.greenAccent,
                              onTap: () => Navigator.pushNamed(context, '/mis_vencimientos', arguments: widget.dni),
                            ),
                            if (isAdmin)
                              _buildMenuButton(
                                titulo: "ADMINISTRACIÓN",
                                icono: Icons.admin_panel_settings_sharp,
                                color: Colors.redAccent,
                                onTap: () => Navigator.pushNamed(context, '/admin_panel'),
                              ),
                          ],
                        ),
                      ),
                      
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 15),
                          child: Text(
                            "Legajo: ${widget.dni} | Rol: ${widget.rol}",
                            style: const TextStyle(color: Colors.white38, fontSize: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_circle, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Text(
                "BIENVENIDO",
                style: TextStyle(
                  color: Colors.white.withAlpha(180),
                  letterSpacing: 2,
                  fontSize: 10,
                  fontWeight: FontWeight.bold
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            widget.nombre.split(' ')[0],
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => WidgetsBinding.instance.addPostFrameCallback((_) => onTap()),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(25), 
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withAlpha(30)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10), // Un poquito más chico el padding del icono
                decoration: BoxDecoration(
                  color: color.withAlpha(40),
                  shape: BoxShape.circle,
                ),
                child: Icon(icono, color: color, size: 28), // Icono de 28px en lugar de 32px
              ),
              const SizedBox(height: 10),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11, // Texto un punto más chico
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
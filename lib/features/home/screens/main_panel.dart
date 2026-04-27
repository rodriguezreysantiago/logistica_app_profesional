import 'package:flutter/material.dart';
import '../../auth/services/auth_service.dart';

class MainPanel extends StatelessWidget {
  final String dni;
  final String nombre;
  final String rol;

  MainPanel({
    super.key,
    required this.dni,
    required this.nombre,
    required this.rol,
  });

  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = rol.trim().toUpperCase() == 'ADMIN';

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'S.M.A.R.T. Logística',
          style: TextStyle(letterSpacing: 1.2),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: 'Cerrar Sesión',
            onPressed: () async {
              final navigator = Navigator.of(context);

              await _authService.logout();

              if (!context.mounted) return;

              navigator.pushNamedAndRemoveUntil(
                '/',
                (route) => false,
              );
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
                  Container(color: Theme.of(context).scaffoldBackgroundColor),
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withAlpha(180),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      _buildWelcomeHeader(context),
                      const SizedBox(height: 30),
                      Expanded(
                        child: GridView.count(
                          crossAxisCount: 2,
                          crossAxisSpacing: 15,
                          mainAxisSpacing: 15,
                          childAspectRatio: 1.2,
                          children: [
                            _buildMenuButton(
                              context,
                              titulo: "MI PERFIL",
                              icono: Icons.person_pin_outlined,
                              color: Colors.blueAccent,
                              onTap: () => Navigator.pushNamed(
                                context,
                                '/perfil',
                                arguments: dni,
                              ),
                            ),
                            _buildMenuButton(
                              context,
                              titulo: "MI UNIDAD",
                              icono: Icons.local_shipping_outlined,
                              color: Colors.orangeAccent,
                              onTap: () => Navigator.pushNamed(
                                context,
                                '/equipo',
                                arguments: dni,
                              ),
                            ),
                            _buildMenuButton(
                              context,
                              titulo: "MIS VENCIMIENTOS",
                              icono: Icons.assignment_late_outlined,
                              color: Colors.greenAccent,
                              onTap: () => Navigator.pushNamed(
                                context,
                                '/mis_vencimientos',
                                arguments: dni,
                              ),
                            ),
                            if (isAdmin)
                              _buildMenuButton(
                                context,
                                titulo: "ADMINISTRACIÓN",
                                icono: Icons.admin_panel_settings_sharp,
                                color: Colors.redAccent,
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  '/admin_panel',
                                ),
                              ),
                          ],
                        ),
                      ),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Text(
                            "Legajo: $dni | Rol: $rol",
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                              letterSpacing: 1,
                            ),
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

  Widget _buildWelcomeHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_circle,
                color: Colors.greenAccent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                "BIENVENIDO",
                style: TextStyle(
                  color: Colors.white.withAlpha(150),
                  letterSpacing: 2,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            nombre.split(' ')[0],
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuButton(
    BuildContext context, {
    required String titulo,
    required IconData icono,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: Icon(icono, color: color, size: 30),
              ),
              const SizedBox(height: 12),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

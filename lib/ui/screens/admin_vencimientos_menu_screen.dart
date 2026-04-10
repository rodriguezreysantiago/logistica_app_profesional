import 'package:flutter/material.dart';

class AdminVencimientosMenuScreen extends StatelessWidget {
  const AdminVencimientosMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, // Para que el fondo llegue hasta arriba
      appBar: AppBar(
        title: const Text("Auditoría Crítica"),
        centerTitle: true,
        backgroundColor: Colors.transparent, // AppBar invisible
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
          
          // 2. Overlay oscuro
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.65),
            ),
          ),

          // 3. Contenido
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10),
              children: [
                // SECCIÓN DE SOLICITUDES ENTRANTES
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 16, 12),
                  child: Text(
                    "PENDIENTES DE APROBACIÓN", 
                    style: TextStyle(
                      fontSize: 13, 
                      fontWeight: FontWeight.bold, 
                      color: Colors.orangeAccent, // Resaltado para llamar la atención
                      letterSpacing: 1.1
                    )
                  ),
                ),
                _tile(
                  context, 
                  "Revisiones de Choferes", 
                  Icons.notification_important, 
                  '/admin_revisiones', 
                  colorIcon: Colors.orangeAccent
                ),
                
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  child: Divider(color: Colors.white24),
                ),

                // SECCIÓN DE CONSULTA GENERAL
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 10, 16, 12),
                  child: Text(
                    "AUDITORÍA GENERAL", 
                    style: TextStyle(
                      fontSize: 13, 
                      fontWeight: FontWeight.bold, 
                      color: Colors.white54,
                      letterSpacing: 1.1
                    )
                  ),
                ),
                _tile(context, "Vencimientos de Choferes", Icons.person_search, '/vencimientos_choferes'),
                _tile(context, "Vencimientos de Chasis", Icons.engineering, '/vencimientos_chasis'),
                _tile(context, "Vencimientos de Acoplados", Icons.ad_units, '/vencimientos_acoplados'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, String t, IconData i, String r, {Color colorIcon = Colors.redAccent}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1), // Transparencia del item
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorIcon.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(i, color: colorIcon),
          ),
          title: Text(
            t, 
            style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)
          ),
          trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white38),
          onTap: () => Navigator.pushNamed(context, r),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';

class AdminVencimientosMenuScreen extends StatelessWidget {
  const AdminVencimientosMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, 
      appBar: AppBar(
        title: const Text("Auditoría de Vencimientos"),
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
              color: Colors.black.withAlpha(200), // Oscurecemos un poco más para resaltar los botones
            ),
          ),

          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 20),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 10, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "AUDITORÍA PREVENTIVA (60 DÍAS)", 
                        style: TextStyle(
                          fontSize: 11, 
                          fontWeight: FontWeight.bold, 
                          color: Colors.greenAccent, // Alineado al color primario del Theme
                          letterSpacing: 1.5
                        )
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Control proactivo de documentación próxima a vencer.",
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // TILES DE AUDITORÍA
                _tile(
                  context, 
                  "VENCIMIENTOS DE PERSONAL", 
                  Icons.person_search, 
                  '/vencimientos_choferes', 
                  colorIcon: Colors.blueAccent,
                  subtitulo: "Seguimiento de Carnets, LINTI y ART"
                ),
                
                _tile(
                  context, 
                  "VENCIMIENTOS DE TRACTORES", 
                  Icons.local_shipping, 
                  '/vencimientos_chasis', 
                  colorIcon: Colors.orangeAccent,
                  subtitulo: "Control de RTO y Seguros de Camiones"
                ),
                
                _tile(
                  context, 
                  "VENCIMIENTOS DE ENGANCHES", 
                  Icons.grid_view, 
                  '/vencimientos_acoplados', 
                  colorIcon: Colors.tealAccent,
                  subtitulo: "Auditoría de Bateas, Tolvas y Acoplados"
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 25, vertical: 30),
                  child: Divider(color: Colors.white10),
                ),

                const Center(
                  child: Text(
                    "S.M.A.R.T. - Gestión de Flota",
                    style: TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 1),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ✅ MENTOR: El Tile ahora usa el Theme Global y tiene un efecto táctil perfecto
  Widget _tile(BuildContext context, String titulo, IconData icono, String ruta, {required Color colorIcon, String? subtitulo}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface, // Extrae el color de main.dart
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16), // Asegura que el click respete la curva
          onTap: () => Navigator.pushNamed(context, ruta),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorIcon.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icono, color: colorIcon, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        titulo, 
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)
                      ),
                      if (subtitulo != null) ...[
                        const SizedBox(height: 4),
                        Text(subtitulo, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ]
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
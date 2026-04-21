import 'package:flutter/material.dart';

class AdminVencimientosMenuScreen extends StatelessWidget {
  const AdminVencimientosMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, 
      appBar: AppBar(
        title: const Text("Auditoría de Vencimientos"),
        centerTitle: true,
        backgroundColor: Colors.transparent, 
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // FONDO
          Positioned.fill(
            child: Image.asset(
              'assets/images/fondo_login.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => 
                  Container(color: const Color(0xFF0D1D2D)),
            ),
          ),
          
          // CAPA OSCURA
          Positioned.fill(
            child: Container(
              color: Colors.black.withAlpha(180),
            ),
          ),

          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 20),
              children: [
                // CABECERA DE SECCIÓN
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
                          color: Colors.orangeAccent,
                          letterSpacing: 1.5
                        )
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Control proactivo de documentación próxima a vencer.",
                        style: TextStyle(color: Colors.white38, fontSize: 12),
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
                  colorIcon: Colors.greenAccent,
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
                  child: Divider(color: Colors.white12),
                ),

                const Center(
                  child: Text(
                    "S.M.A.R.T. - Gestión de Flota",
                    style: TextStyle(color: Colors.white10, fontSize: 10, letterSpacing: 1),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, String t, IconData i, String r, {Color colorIcon = Colors.redAccent, String? subtitulo}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withAlpha(30)),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorIcon.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(i, color: colorIcon, size: 24),
          ),
          title: Text(
            t, 
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)
          ),
          subtitle: subtitulo != null 
            ? Text(subtitulo, style: const TextStyle(color: Colors.white54, fontSize: 12)) 
            : null,
          trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white24),
          onTap: () {
            // BLINDAJE WINDOWS
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.pushNamed(context, r);
            });
          },
        ),
      ),
    );
  }
}
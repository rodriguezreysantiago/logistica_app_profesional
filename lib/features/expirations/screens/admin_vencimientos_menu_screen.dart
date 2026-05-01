import 'package:flutter/material.dart';

import '../../../shared/widgets/app_widgets.dart';

/// Menú principal de auditoría de vencimientos.
class AdminVencimientosMenuScreen extends StatelessWidget {
  const AdminVencimientosMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Auditoría de Vencimientos',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        children: const [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 10, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AUDITORÍA PREVENTIVA (60 DÍAS)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.greenAccent,
                    letterSpacing: 1.5,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Control proactivo de documentación próxima a vencer.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          SizedBox(height: 10),
          _MenuTile(
            titulo: 'CALENDARIO MENSUAL',
            subtitulo: 'Vista global con todos los vencimientos por día',
            icono: Icons.event_note,
            colorIcono: Colors.greenAccent,
            ruta: '/vencimientos_calendario',
          ),
          _MenuTile(
            titulo: 'VENCIMIENTOS DE PERSONAL',
            subtitulo: 'Seguimiento de carnets, preocupacional y ART',
            icono: Icons.person_search,
            colorIcono: Colors.blueAccent,
            ruta: '/vencimientos_choferes',
          ),
          _MenuTile(
            titulo: 'VENCIMIENTOS DE TRACTORES',
            subtitulo: 'Control de RTO y seguros de camiones',
            icono: Icons.local_shipping,
            colorIcono: Colors.orangeAccent,
            ruta: '/vencimientos_chasis',
          ),
          _MenuTile(
            titulo: 'VENCIMIENTOS DE ENGANCHES',
            subtitulo: 'Auditoría de bateas, tolvas, bivuelcos y tanques',
            icono: Icons.grid_view,
            colorIcono: Colors.tealAccent,
            ruta: '/vencimientos_acoplados',
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 25, vertical: 30),
            child: Divider(color: Colors.white10),
          ),
          Center(
            child: Text(
              'S.M.A.R.T. — Gestión de Flota',
              style: TextStyle(
                color: Colors.white24,
                fontSize: 10,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final IconData icono;
  final Color colorIcono;
  final String ruta;

  const _MenuTile({
    required this.titulo,
    required this.subtitulo,
    required this.icono,
    required this.colorIcono,
    required this.ruta,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AppCard(
        onTap: () => Navigator.pushNamed(context, ruta),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorIcono.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: Icon(icono, color: colorIcono, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitulo,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                size: 16, color: Colors.white24),
          ],
        ),
      ),
    );
  }
}

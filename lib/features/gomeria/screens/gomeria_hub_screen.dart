import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/constants/app_colors.dart';
import '../../../shared/widgets/app_widgets.dart';

/// Pantalla de entrada del módulo Gomería. Hub con 4 accesos: Unidades
/// (la pantalla principal del operador, tipo "qué cubiertas tiene cada
/// camión"), Stock (cubiertas en depósito + alta), Recapados (envíos
/// pendientes y recepción) y Marcas y Modelos (catálogo, ABM admin).
///
/// Optimizada para tablet pegada en la pared del taller: tiles grandes,
/// labels legibles a 1m de distancia.
class GomeriaHubScreen extends StatelessWidget {
  const GomeriaHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Gomería',
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.4,
          children: const [
            _HubTile(
              titulo: 'UNIDADES',
              subtitulo: 'Cambiar cubiertas por posición',
              icono: Icons.local_shipping_outlined,
              color: AppColors.accentOrange,
              ruta: AppRoutes.adminGomeriaUnidades,
            ),
            _HubTile(
              titulo: 'STOCK',
              subtitulo: 'Cubiertas en depósito',
              icono: Icons.inventory_2_outlined,
              color: AppColors.accentBlue,
              ruta: AppRoutes.adminGomeriaStock,
            ),
            _HubTile(
              titulo: 'RECAPADOS',
              subtitulo: 'Envíos al proveedor',
              icono: Icons.swap_horiz_outlined,
              color: AppColors.accentTeal,
              ruta: AppRoutes.adminGomeriaRecapados,
            ),
            _HubTile(
              titulo: 'MARCAS Y MODELOS',
              subtitulo: 'Catálogo (ABM)',
              icono: Icons.category_outlined,
              color: AppColors.accentPurple,
              ruta: AppRoutes.adminGomeriaMarcasModelos,
            ),
          ],
        ),
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final IconData icono;
  final Color color;
  final String ruta;

  const _HubTile({
    required this.titulo,
    required this.subtitulo,
    required this.icono,
    required this.color,
    required this.ruta,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => Navigator.pushNamed(context, ruta),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icono, size: 36, color: color),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitulo,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

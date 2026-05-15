import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/constants/app_colors.dart';
import '../../../shared/widgets/app_widgets.dart';

/// Hub del módulo ICM (Índice de Conducta de Manejo). 3 sub-pantallas:
///
/// - **RANKING**: choferes ordenados del mejor al peor según ICM
///   calculado del rango seleccionado.
/// - **MAPA DE CALOR**: distribución geográfica + horaria de las
///   infracciones (placeholder hasta tener data acumulada).
/// - **DETALLE POR CHOFER**: drill-down con histórico, distribución
///   por tipo de evento, lugares más conflictivos.
///
/// Esto es lo que YPF audita en su Tablero ICM (ver doc de norma YPF
/// NO_0002913 sec 5.6.2). El módulo unifica eventos Sitrack peligrosos
/// (sobrevelocidad cartográfica, frenadas/aceleraciones bruscas, salida
/// de carril, etc) que ya nos llegan filtrados por las reglas YPF.
class IcmHubScreen extends StatelessWidget {
  const IcmHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'ICM — Conducta de Manejo',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _BannerInfo(),
            const SizedBox(height: 16),
            Expanded(
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  final w = constraints.maxWidth;
                  final cols = w >= 800 ? 3 : (w >= 540 ? 3 : 1);
                  return GridView.count(
                    crossAxisCount: cols,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: cols == 1 ? 2.4 : 1.3,
                    children: const [
                      _HubTile(
                        titulo: 'RANKING',
                        subtitulo: 'Choferes ordenados por ICM',
                        icono: Icons.leaderboard_outlined,
                        color: AppColors.accentBlue,
                        ruta: AppRoutes.adminIcmRanking,
                      ),
                      _HubTile(
                        titulo: 'MAPA DE CALOR',
                        subtitulo: 'Lugares y horarios con más infracciones',
                        icono: Icons.map_outlined,
                        color: AppColors.accentOrange,
                        ruta: AppRoutes.adminIcmMapaCalor,
                      ),
                      _HubTile(
                        titulo: 'DETALLE POR CHOFER',
                        subtitulo: 'Drill-down individual',
                        icono: Icons.person_search_outlined,
                        color: AppColors.accentTeal,
                        ruta: AppRoutes.adminIcmDetalleChofer,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerInfo extends StatelessWidget {
  const _BannerInfo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.accentBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.accentBlue.withValues(alpha: 0.30),
        ),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: AppColors.accentBlue, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Mismos eventos que YPF audita en su Tablero ICM '
              '(reportados por Sitrack). Verde = ICM ≥ 80, '
              'Amarillo = 60-79, Rojo = < 60.',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
        ],
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
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icono, color: color, size: 36),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              titulo,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitulo,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white60,
            ),
          ),
        ],
      ),
    );
  }
}

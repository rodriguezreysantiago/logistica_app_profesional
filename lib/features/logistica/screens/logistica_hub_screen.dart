import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/constants/app_colors.dart';
import '../../../shared/widgets/app_widgets.dart';

/// Hub del módulo Logística. 3 catálogos que arman la base del futuro
/// sistema de planeamiento de viajes:
///
/// - **EMPRESAS**: clientes (origen/destino del flete) + dadores de
///   transporte (otros transportistas que nos ceden cargas).
/// - **UBICACIONES**: puntos físicos de carga/descarga (silos, plantas,
///   puertos). Reusables entre tarifas.
/// - **TARIFAS**: rutas con precio (origen → destino, tarifa real +
///   tarifa chofer). El corazón del módulo. Cuando armemos el módulo
///   de viajes, cada viaje seleccionará una tarifa y queda atribuido.
class LogisticaHubScreen extends StatelessWidget {
  const LogisticaHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Logística',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _BannerInfo(),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.4,
              children: const [
                _HubTile(
                  titulo: 'TARIFAS',
                  subtitulo: 'Origen → destino con precio',
                  icono: Icons.price_change_outlined,
                  color: AppColors.accentGreen,
                  ruta: AppRoutes.adminLogisticaTarifas,
                ),
                _HubTile(
                  titulo: 'EMPRESAS',
                  subtitulo: 'Clientes y dadores',
                  icono: Icons.business_outlined,
                  color: AppColors.accentBlue,
                  ruta: AppRoutes.adminLogisticaEmpresas,
                ),
                _HubTile(
                  titulo: 'UBICACIONES',
                  subtitulo: 'Puntos de carga/descarga',
                  icono: Icons.place_outlined,
                  color: AppColors.accentTeal,
                  ruta: AppRoutes.adminLogisticaUbicaciones,
                ),
                _HubTile(
                  titulo: 'VIAJES',
                  subtitulo: 'Próximamente',
                  icono: Icons.route_outlined,
                  color: Colors.white24,
                  ruta: '',
                  deshabilitado: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner informativo en la cabecera del hub. Aclara para qué sirve el
/// módulo y por qué hay catálogos antes que viajes.
class _BannerInfo extends StatelessWidget {
  const _BannerInfo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accentGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.4)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline,
              color: AppColors.accentGreen, size: 26),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BASE DEL FUTURO PLANEAMIENTO DE VIAJES',
                  style: TextStyle(
                    color: AppColors.accentGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Cargá empresas y ubicaciones, después armá tarifas '
                  '(rutas con precio). Cuando arranque el módulo de '
                  'viajes, cada viaje va a apuntar a una tarifa.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
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
  final bool deshabilitado;

  const _HubTile({
    required this.titulo,
    required this.subtitulo,
    required this.icono,
    required this.color,
    required this.ruta,
    this.deshabilitado = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: deshabilitado
          ? null
          : () => Navigator.pushNamed(context, ruta),
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
                style: TextStyle(
                  color: deshabilitado ? Colors.white38 : Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitulo,
                style: TextStyle(
                  color: deshabilitado ? Colors.white24 : Colors.white60,
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

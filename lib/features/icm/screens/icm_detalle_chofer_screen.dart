import 'package:flutter/material.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/app_widgets.dart';

/// Detalle individual de ICM por chofer. Hoy solo muestra info básica
/// del DNI seleccionado — placeholder hasta implementar:
///
/// - Histórico de ICM mensual (gráfico de línea).
/// - Distribución por tipo de evento (gráfico de barras).
/// - Lista paginada de últimas infracciones con mini-mapa por evento
///   (lat/lng + cartographyLimitSpeed + gpsSpeed).
/// - Comparativa contra promedio de la flota.
/// - Botón "Exportar Excel para conversación con chofer".
class IcmDetalleChoferScreen extends StatelessWidget {
  const IcmDetalleChoferScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final dni = args is String ? args : '';
    return AppScaffold(
      title: dni.isNotEmpty
          ? 'Detalle ICM — DNI ${AppFormatters.formatearDNI(dni)}'
          : 'Detalle ICM',
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_search_outlined,
                  size: 80, color: Colors.white24),
              const SizedBox(height: 20),
              Text(
                dni.isEmpty
                    ? 'Detalle por chofer — Próximamente'
                    : 'Detalle de DNI ${AppFormatters.formatearDNI(dni)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Drill-down individual: histórico mensual, distribución '
                'de infracciones por tipo, mini-mapa de últimos eventos '
                'y comparativa contra promedio de la flota.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

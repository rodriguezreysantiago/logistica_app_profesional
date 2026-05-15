import 'package:flutter/material.dart';

import '../../../shared/widgets/app_widgets.dart';

/// Mapa de calor de infracciones — placeholder hasta tener data
/// acumulada (≥ 1 mes de eventos Sitrack peligrosos georreferenciados).
///
/// Plan al implementar:
/// - Heatmap layer sobre flutter_map agrupando eventos peligrosos
///   por celda geográfica (bins de ~500 m).
/// - Filtros: tipo de evento (sobrevelocidad / frenada brusca / etc),
///   rango de fechas, hora del día (slider 00-23).
/// - Hover/click sobre celda → popup con detalle de eventos.
/// - Top 5 lugares con más infracciones como lista lateral.
class IcmMapaCalorScreen extends StatelessWidget {
  const IcmMapaCalorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'Mapa de calor — ICM',
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map_outlined, size: 80, color: Colors.white24),
              SizedBox(height: 20),
              Text(
                'Mapa de calor — Próximamente',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Necesitamos acumular ≥ 1 mes de eventos Sitrack '
                'georreferenciados antes de generar un mapa útil. '
                'Mientras tanto, los eventos individuales aparecen en '
                'el resumen diario a Molina y en el ranking de choferes.',
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

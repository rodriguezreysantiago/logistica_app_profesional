// Gráfico de línea para la tendencia del ICM promedio de la flota.
// Misma estética que el del módulo ICM (icm_reporte_semanal_screen)
// para coherencia visual — diferencia: aquí mostramos 12 puntos
// (vs 12 también allá), pero más compacto porque va al lado de otros
// elementos del tablero.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../shared/constants/app_colors.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../services/vista_ejecutiva_service.dart';

class TendenciaIcmChart extends StatelessWidget {
  final List<PuntoTendencia> puntos;
  final String titulo;

  const TendenciaIcmChart({
    super.key,
    required this.puntos,
    this.titulo = 'ICM promedio · últimas semanas',
  });

  @override
  Widget build(BuildContext context) {
    final hayDatos = puntos.any((p) => p.valor > 0);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up,
                  color: AppColors.accentTeal, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 180,
            child: hayDatos
                ? _buildChart(context)
                : const Center(
                    child: Text(
                      'Sin datos de semanas cerradas\n(esperar el cron del lunes 6 AM)',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(BuildContext context) {
    final spots = <FlSpot>[];
    for (var i = 0; i < puntos.length; i++) {
      spots.add(FlSpot(i.toDouble(), puntos[i].valor));
    }
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        gridData: FlGridData(
          show: true,
          horizontalInterval: 20,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(
            color: Colors.white.withValues(alpha: 0.05),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 20,
              reservedSize: 28,
              getTitlesWidget: (v, m) => Text(
                v.toInt().toString(),
                style:
                    const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 2,
              reservedSize: 22,
              getTitlesWidget: (v, m) {
                final idx = v.toInt();
                if (idx < 0 || idx >= puntos.length) {
                  return const SizedBox.shrink();
                }
                // 1 cada 2 puntos para no saturar (12 puntos → 6 labels).
                if (idx % 2 != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    puntos[idx].label,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 9),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            left: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            bottom:
                BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: AppColors.accentTeal,
            barWidth: 3,
            isCurved: true,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) {
                final icm = puntos[spot.x.toInt()].valor;
                return FlDotCirclePainter(
                  radius: 3.5,
                  color: _colorIcm(icm),
                  strokeColor: Colors.white,
                  strokeWidth: 1,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.accentTeal.withValues(alpha: 0.12),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) =>
                Colors.black.withValues(alpha: 0.85),
            getTooltipItems: (touches) => touches.map((s) {
              final p = puntos[s.x.toInt()];
              return LineTooltipItem(
                '${p.label}\nICM ${p.valor.toStringAsFixed(1)}',
                const TextStyle(color: Colors.white, fontSize: 11),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Color _colorIcm(double icm) {
    if (icm == 0) return Colors.white24;
    if (icm >= 80) return AppColors.accentGreen;
    if (icm >= 60) return AppColors.accentAmber;
    return AppColors.accentRed;
  }
}

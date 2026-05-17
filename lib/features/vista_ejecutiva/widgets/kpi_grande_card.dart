// Card grande de KPI para el tablero ejecutivo. Diseño tipo Apple
// Health / iOS Wallet: número GRANDE en el centro, label arriba en
// minúsculas espaciadas, flecha de tendencia (verde si mejora, roja
// si empeora) abajo a la derecha.
//
// Tres variantes:
//   - `KpiGrandeCard.mes(...)`     — número entero + variación %.
//   - `KpiGrandeCard.icm(...)`     — promedio decimal + variación en pts.
//   - `KpiGrandeCard.simple(...)`  — solo el número, sin comparativa.

import 'package:flutter/material.dart';

import '../../../shared/constants/app_colors.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../services/vista_ejecutiva_service.dart';

class KpiGrandeCard extends StatelessWidget {
  final String label;
  final String valorTexto;
  final IconData icono;
  final Color color;
  /// Texto pequeño bajo el número grande (ej. "vs mes anterior" o
  /// "20 con unidad asignada").
  final String? sublabel;
  /// Indicador de tendencia: positivo = subió, negativo = bajó, null = sin dato.
  /// Si `mejorEsSubir` está en true, positivo se pinta verde y negativo
  /// rojo; con false se invierte (útil para "alertas críticas" donde
  /// bajar es bueno).
  final double? variacion;
  /// Texto formateado de la variación: "+12%" o "-3 pts".
  final String? variacionTexto;
  final bool mejorEsSubir;
  final VoidCallback? onTap;

  const KpiGrandeCard({
    super.key,
    required this.label,
    required this.valorTexto,
    required this.icono,
    required this.color,
    this.sublabel,
    this.variacion,
    this.variacionTexto,
    this.mejorEsSubir = true,
    this.onTap,
  });

  /// Constructor a partir de `KpiMes` (viajes del mes — entero +
  /// comparativa %).
  factory KpiGrandeCard.mes({
    Key? key,
    required String label,
    required KpiMes kpi,
    required IconData icono,
    required Color color,
    String? sublabel,
    bool mejorEsSubir = true,
    VoidCallback? onTap,
  }) {
    final pct = kpi.variacionPct;
    final pctTexto = pct == null
        ? null
        : (pct >= 0
            ? '+${pct.toStringAsFixed(0)}%'
            : '${pct.toStringAsFixed(0)}%');
    return KpiGrandeCard(
      key: key,
      label: label,
      valorTexto: '${kpi.actual}',
      icono: icono,
      color: color,
      sublabel: sublabel ?? 'vs mes anterior (${kpi.anterior})',
      variacion: pct,
      variacionTexto: pctTexto,
      mejorEsSubir: mejorEsSubir,
      onTap: onTap,
    );
  }

  /// Constructor a partir de `KpiIcm` (ICM flota — decimal +
  /// comparativa en puntos).
  factory KpiGrandeCard.icm({
    Key? key,
    required String label,
    required KpiIcm kpi,
    required IconData icono,
    String? sublabel,
    VoidCallback? onTap,
  }) {
    final v = kpi.variacionAbs;
    final vTexto = v == null
        ? null
        : (v >= 0
            ? '+${v.toStringAsFixed(1)} pts'
            : '${v.toStringAsFixed(1)} pts');
    final colorIcm = kpi.actual >= 80
        ? AppColors.accentGreen
        : (kpi.actual >= 60 ? AppColors.accentAmber : AppColors.accentRed);
    return KpiGrandeCard(
      key: key,
      label: label,
      valorTexto: kpi.actual > 0 ? kpi.actual.toStringAsFixed(1) : '—',
      icono: icono,
      color: colorIcm,
      sublabel: sublabel ??
          (kpi.choferesEnPromedio > 0
              ? '${kpi.choferesEnPromedio} choferes · semana cerrada'
              : 'sin datos de la semana cerrada'),
      variacion: v,
      variacionTexto: vTexto,
      mejorEsSubir: true,
      onTap: onTap,
    );
  }

  /// Constructor a partir de `KpiSimple` (solo número, sin tendencia).
  factory KpiGrandeCard.simple({
    Key? key,
    required String label,
    required KpiSimple kpi,
    required IconData icono,
    required Color color,
    VoidCallback? onTap,
  }) {
    return KpiGrandeCard(
      key: key,
      label: label,
      valorTexto: '${kpi.valor}',
      icono: icono,
      color: color,
      sublabel: kpi.sublabel,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Color de la variación: verde si "buena", rojo si "mala".
    Color? colorVariacion;
    IconData? iconoVariacion;
    if (variacion != null) {
      final esPositivo = variacion! > 0;
      final esCero = variacion! == 0;
      if (esCero) {
        colorVariacion = Colors.white54;
        iconoVariacion = Icons.remove;
      } else {
        final esBueno = mejorEsSubir ? esPositivo : !esPositivo;
        colorVariacion =
            esBueno ? AppColors.accentGreen : AppColors.accentRed;
        iconoVariacion =
            esPositivo ? Icons.arrow_upward : Icons.arrow_downward;
      }
    }

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: icono coloreado + label en uppercase pequeño.
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icono, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Número grande — FittedBox para que escale en mobile chico
          // sin overflowear.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valorTexto,
              style: TextStyle(
                color: color,
                fontSize: 42,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
          ),
          if (sublabel != null) ...[
            const SizedBox(height: 6),
            Text(
              sublabel!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
          // Variación opcional — flecha + texto, alineado a la derecha.
          if (variacion != null && variacionTexto != null) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(iconoVariacion, color: colorVariacion, size: 14),
                const SizedBox(width: 3),
                Text(
                  variacionTexto!,
                  style: TextStyle(
                    color: colorVariacion,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

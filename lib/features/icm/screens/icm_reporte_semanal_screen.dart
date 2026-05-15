import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../services/icm_calculator.dart';
import '../services/icm_historico_service.dart';

/// Reporte Semanal completo del ICM de la flota:
///   - Header: ICM promedio de la semana actual + delta vs anterior.
///   - Stats: total eventos, choferes verdes/amarillos/rojos.
///   - Pie: distribución de categorías esta semana.
///   - Línea: ICM promedio últimas 12 semanas.
///   - Top 5 mejores + top 5 peores choferes (esta semana).
///
/// Sin filtros — siempre muestra "esta semana" + "últimas 12 semanas".
/// Si Santiago quiere agregar selección de semana, se hace después.
class IcmReporteSemanalScreen extends StatefulWidget {
  const IcmReporteSemanalScreen({super.key});

  @override
  State<IcmReporteSemanalScreen> createState() =>
      _IcmReporteSemanalScreenState();
}

class _IcmReporteSemanalScreenState extends State<IcmReporteSemanalScreen> {
  Future<List<IcmSemanaFlota>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _cargar();
  }

  Future<List<IcmSemanaFlota>> _cargar() async {
    final db = FirebaseFirestore.instance;
    final empSnap = await db.collection('EMPLEADOS').get();
    final nombrePorDni = <String, String>{};
    for (final d in empSnap.docs) {
      final data = d.data();
      final dni = (data['DNI'] ?? d.id).toString();
      final nombre = (data['NOMBRE'] ?? '').toString().trim();
      if (nombre.isNotEmpty) nombrePorDni[dni] = nombre;
    }
    return IcmHistoricoService.historicoFlota(
      db: db,
      nombrePorDni: nombrePorDni,
      cantidadSemanas: 12,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Reporte Semanal — ICM',
      body: FutureBuilder<List<IcmSemanaFlota>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error: ${snap.error}',
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            );
          }
          final lista = snap.data ?? const [];
          if (lista.isEmpty) {
            return const Center(
              child: Text('Sin datos suficientes',
                  style: TextStyle(color: Colors.white54)),
            );
          }
          final actual = lista.last;
          final anterior =
              lista.length >= 2 ? lista[lista.length - 2] : null;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeaderSemana(actual: actual, anterior: anterior),
                const SizedBox(height: 16),
                _StatsRow(actual: actual),
                const SizedBox(height: 20),
                const _SeccionTitulo('Distribución de categorías — semana actual'),
                const SizedBox(height: 8),
                _GraficoPieCategorias(actual: actual),
                const SizedBox(height: 24),
                const _SeccionTitulo(
                    'ICM promedio de la flota — últimas 12 semanas'),
                const SizedBox(height: 8),
                _GraficoLineaIcmFlota(historico: lista),
                const SizedBox(height: 24),
                const _SeccionTitulo('Top 5 mejores — semana actual'),
                const SizedBox(height: 8),
                _ListaChoferes(
                  choferes: actual.top5Mejores,
                  esTopMejores: true,
                ),
                const SizedBox(height: 24),
                const _SeccionTitulo('Top 5 peores — semana actual'),
                const SizedBox(height: 8),
                _ListaChoferes(
                  choferes: actual.top5Peores,
                  esTopMejores: false,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Widgets internos ───────────────────────────────────────────────

class _HeaderSemana extends StatelessWidget {
  final IcmSemanaFlota actual;
  final IcmSemanaFlota? anterior;

  const _HeaderSemana({required this.actual, this.anterior});

  @override
  Widget build(BuildContext context) {
    final delta = anterior != null
        ? (actual.icmPromedio - anterior!.icmPromedio)
        : 0.0;
    final deltaStr =
        delta == 0.0 ? '—' : '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)}';
    final deltaColor = delta > 0
        ? Colors.greenAccent
        : delta < 0
            ? Colors.redAccent
            : Colors.white54;
    final color = _colorIcm(actual.icmPromedio);
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    actual.icmPromedio.toStringAsFixed(0),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'ICM promedio',
                    style: TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Semana ${actual.labelSemana}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${actual.choferesActivos} choferes con eventos · '
                    '${actual.totalEventos} infracciones',
                    style:
                        const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Text(
                        'Δ vs anterior: ',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                      Text(
                        deltaStr,
                        style: TextStyle(
                          color: deltaColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final IcmSemanaFlota actual;

  const _StatsRow({required this.actual});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatBox(
          label: 'Verdes',
          valor: actual.choferesVerdes.toString(),
          color: Colors.green.shade600,
        ),
        const SizedBox(width: 8),
        _StatBox(
          label: 'Amarillos',
          valor: actual.choferesAmarillos.toString(),
          color: Colors.amber.shade700,
        ),
        const SizedBox(width: 8),
        _StatBox(
          label: 'Rojos',
          valor: actual.choferesRojos.toString(),
          color: Colors.red.shade600,
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String valor;
  final Color color;

  const _StatBox({
    required this.label,
    required this.valor,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AppCard(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                valor,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeccionTitulo extends StatelessWidget {
  final String texto;
  const _SeccionTitulo(this.texto);

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _GraficoPieCategorias extends StatelessWidget {
  final IcmSemanaFlota actual;

  const _GraficoPieCategorias({required this.actual});

  @override
  Widget build(BuildContext context) {
    final total = actual.choferesVerdes +
        actual.choferesAmarillos +
        actual.choferesRojos;
    if (total == 0) {
      return const SizedBox(
        height: 160,
        child: Center(
          child: Text('Sin choferes con eventos esta semana ✅',
              style: TextStyle(color: Colors.greenAccent)),
        ),
      );
    }
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 36,
              sections: [
                if (actual.choferesVerdes > 0)
                  PieChartSectionData(
                    value: actual.choferesVerdes.toDouble(),
                    color: Colors.green.shade600,
                    title: '${actual.choferesVerdes}',
                    radius: 56,
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (actual.choferesAmarillos > 0)
                  PieChartSectionData(
                    value: actual.choferesAmarillos.toDouble(),
                    color: Colors.amber.shade700,
                    title: '${actual.choferesAmarillos}',
                    radius: 56,
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (actual.choferesRojos > 0)
                  PieChartSectionData(
                    value: actual.choferesRojos.toDouble(),
                    color: Colors.red.shade600,
                    title: '${actual.choferesRojos}',
                    radius: 56,
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GraficoLineaIcmFlota extends StatelessWidget {
  final List<IcmSemanaFlota> historico;

  const _GraficoLineaIcmFlota({required this.historico});

  @override
  Widget build(BuildContext context) {
    if (historico.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Text('Sin data histórica',
              style: TextStyle(color: Colors.white54)),
        ),
      );
    }
    final spots = <FlSpot>[];
    for (var i = 0; i < historico.length; i++) {
      spots.add(FlSpot(i.toDouble(), historico[i].icmPromedio));
    }
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
        child: SizedBox(
          height: 220,
          child: LineChart(
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
                    reservedSize: 32,
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
                    reservedSize: 28,
                    getTitlesWidget: (v, m) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= historico.length) {
                        return const SizedBox.shrink();
                      }
                      if (idx % 2 != 0) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          historico[idx].labelSemana,
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
                  left: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1)),
                  bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1)),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  color: Colors.lightBlueAccent,
                  barWidth: 3,
                  isCurved: true,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, _, __, ___) {
                      final icm = historico[spot.x.toInt()].icmPromedio;
                      return FlDotCirclePainter(
                        radius: 4,
                        color: _colorIcm(icm),
                        strokeColor: Colors.white,
                        strokeWidth: 1,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Colors.lightBlueAccent.withValues(alpha: 0.10),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) =>
                      Colors.black.withValues(alpha: 0.85),
                  getTooltipItems: (spots) => spots.map((s) {
                    final w = historico[s.x.toInt()];
                    return LineTooltipItem(
                      '${w.labelSemana}\nICM ${w.icmPromedio.toStringAsFixed(1)}\n'
                      '${w.choferesActivos} choferes · ${w.totalEventos} eventos',
                      const TextStyle(color: Colors.white, fontSize: 11),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ListaChoferes extends StatelessWidget {
  final List<IcmChofer> choferes;
  final bool esTopMejores;

  const _ListaChoferes({
    required this.choferes,
    required this.esTopMejores,
  });

  @override
  Widget build(BuildContext context) {
    if (choferes.isEmpty) {
      return const SizedBox(
        height: 60,
        child: Center(
          child: Text('Sin choferes en este top',
              style: TextStyle(color: Colors.white54)),
        ),
      );
    }
    return Column(
      children: choferes.asMap().entries.map((e) {
        final pos = e.key + 1;
        final c = e.value;
        return Card(
          elevation: 1,
          margin: const EdgeInsets.symmetric(vertical: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(
              color: _colorCategoria(c.categoria).withValues(alpha: 0.40),
              width: 1,
            ),
          ),
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: _colorCategoria(c.categoria),
              child: Text(
                esTopMejores ? '$pos' : '$pos',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              c.choferNombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'DNI ${AppFormatters.formatearDNI(c.choferDni)} · '
              '${c.totalEventos} eventos',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _colorCategoria(c.categoria),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                c.icm.toStringAsFixed(0),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            onTap: () => Navigator.pushNamed(
              context,
              AppRoutes.adminIcmDetalleChofer,
              arguments: c.choferDni,
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Helpers de color ───────────────────────────────────────────────

Color _colorIcm(double icm) {
  if (icm >= 80) return Colors.green.shade600;
  if (icm >= 60) return Colors.amber.shade700;
  return Colors.red.shade600;
}

Color _colorCategoria(CategoriaIcm c) {
  switch (c) {
    case CategoriaIcm.bajo:
      return Colors.green.shade600;
    case CategoriaIcm.medio:
      return Colors.amber.shade700;
    case CategoriaIcm.alto:
      return Colors.red.shade600;
    case CategoriaIcm.sinDatos:
      return Colors.blueGrey.shade600;
  }
}

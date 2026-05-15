import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../services/icm_calculator.dart';
import '../services/icm_historico_service.dart';

/// Detalle ICM individual de un chofer:
///   - Header: nombre + DNI + última semana (ICM + categoría).
///   - Gráfico de línea: ICM últimas 12 semanas.
///   - Gráfico de barras: top 5 tipos de infracción del último mes.
///   - Stats: total eventos / km / mejor semana / peor semana.
class IcmDetalleChoferScreen extends StatefulWidget {
  const IcmDetalleChoferScreen({super.key});

  @override
  State<IcmDetalleChoferScreen> createState() =>
      _IcmDetalleChoferScreenState();
}

class _IcmDetalleChoferScreenState extends State<IcmDetalleChoferScreen> {
  Future<_DetalleData>? _future;
  String _dni = '';
  String _nombre = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_future != null) return; // Cargar 1 sola vez
    final args = ModalRoute.of(context)?.settings.arguments;
    _dni = args is String ? args : '';
    if (_dni.isEmpty) return;
    _future = _cargar(_dni);
  }

  Future<_DetalleData> _cargar(String dni) async {
    final db = FirebaseFirestore.instance;
    // Nombre desde EMPLEADOS
    final empSnap = await db.collection('EMPLEADOS').doc(dni).get();
    _nombre = (empSnap.data()?['NOMBRE'] ?? '').toString().trim();
    // Histórico (12 semanas)
    final historico = await IcmHistoricoService.historicoChofer(
      db: db,
      choferDni: dni,
      cantidadSemanas: 12,
    );
    // Distribución por tipo del último mes (últimas 4 semanas)
    final hace4Sem = DateTime.now()
        .subtract(const Duration(days: 28))
        .millisecondsSinceEpoch;
    final ahora = DateTime.now().millisecondsSinceEpoch;
    final evSnap = await db
        .collection('SITRACK_EVENTOS')
        .where('driver_dni', isEqualTo: dni)
        .where('report_date',
            isGreaterThanOrEqualTo:
                Timestamp.fromMillisecondsSinceEpoch(hace4Sem))
        .where('report_date',
            isLessThan: Timestamp.fromMillisecondsSinceEpoch(ahora))
        .get();
    final porTipo = <String, int>{};
    for (final d in evSnap.docs) {
      final eventId = d.data()['event_id'];
      if (eventId is! int || !kTiposInfraccionIcm.contains(eventId)) continue;
      final n = (d.data()['event_name'] ?? 'Evento $eventId').toString();
      porTipo[n] = (porTipo[n] ?? 0) + 1;
    }
    return _DetalleData(historico: historico, porTipoUltMes: porTipo);
  }

  @override
  Widget build(BuildContext context) {
    if (_dni.isEmpty) {
      return const AppScaffold(
        title: 'Detalle ICM',
        body: Center(
          child: Text(
            'Vení desde el ranking — el detalle requiere un chofer seleccionado.',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }
    return AppScaffold(
      title: 'Detalle ICM',
      body: FutureBuilder<_DetalleData>(
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
          final data = snap.data!;
          final ultima = data.historico.isNotEmpty
              ? data.historico.last
              : null;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  nombre: _nombre.isEmpty ? 'DNI $_dni' : _nombre,
                  dni: _dni,
                  ultima: ultima,
                ),
                const SizedBox(height: 20),
                _StatsRow(historico: data.historico),
                const SizedBox(height: 20),
                const _SeccionTitulo('Evolución ICM — últimas 12 semanas'),
                const SizedBox(height: 8),
                _GraficoLineaIcm(historico: data.historico),
                const SizedBox(height: 24),
                const _SeccionTitulo('Distribución de infracciones (último mes)'),
                const SizedBox(height: 8),
                _GraficoBarrasTipos(porTipo: data.porTipoUltMes),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DetalleData {
  final List<IcmSemanaChofer> historico;
  final Map<String, int> porTipoUltMes;

  const _DetalleData({required this.historico, required this.porTipoUltMes});
}

class _Header extends StatelessWidget {
  final String nombre;
  final String dni;
  final IcmSemanaChofer? ultima;

  const _Header({required this.nombre, required this.dni, this.ultima});

  @override
  Widget build(BuildContext context) {
    final icm = ultima?.icm ?? 0;
    final color = _colorCategoria(ultima?.categoria ?? CategoriaIcm.bajo);
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    icm.toStringAsFixed(0),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'ICM últ. semana',
                    style: TextStyle(color: Colors.white70, fontSize: 9),
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
                    nombre,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'DNI ${AppFormatters.formatearDNI(dni)}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                  if (ultima != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Semana ${ultima!.labelSemana} · ${ultima!.totalEventos} '
                      'eventos · ${ultima!.infraccionesPor100Km.toStringAsFixed(2)}/100km',
                      style: TextStyle(color: color, fontSize: 11),
                    ),
                  ],
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
  final List<IcmSemanaChofer> historico;

  const _StatsRow({required this.historico});

  @override
  Widget build(BuildContext context) {
    if (historico.isEmpty) return const SizedBox.shrink();
    final totalEv = historico.fold<int>(0, (acc, s) => acc + s.totalEventos);
    final mejor =
        historico.fold<IcmSemanaChofer>(historico.first,
            (best, s) => s.icm > best.icm ? s : best);
    final peor = historico.fold<IcmSemanaChofer>(historico.first,
        (worst, s) => s.icm < worst.icm ? s : worst);
    return Row(
      children: [
        _StatCard(label: 'Total eventos', valor: totalEv.toString()),
        const SizedBox(width: 8),
        _StatCard(label: 'Mejor semana', valor: '${mejor.icm.toStringAsFixed(0)} · ${mejor.labelSemana}'),
        const SizedBox(width: 8),
        _StatCard(label: 'Peor semana', valor: '${peor.icm.toStringAsFixed(0)} · ${peor.labelSemana}'),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String valor;

  const _StatCard({required this.label, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AppCard(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(color: Colors.white54, fontSize: 10)),
              const SizedBox(height: 4),
              Text(
                valor,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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

class _GraficoLineaIcm extends StatelessWidget {
  final List<IcmSemanaChofer> historico;

  const _GraficoLineaIcm({required this.historico});

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
      spots.add(FlSpot(i.toDouble(), historico[i].icm));
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
                      // Solo cada 2 semanas para que no se amontone.
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
                      final cat = historico[spot.x.toInt()].categoria;
                      return FlDotCirclePainter(
                        radius: 4,
                        color: _colorCategoria(cat),
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
                      '${w.labelSemana}\nICM ${w.icm.toStringAsFixed(0)}\n'
                      '${w.totalEventos} eventos',
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

class _GraficoBarrasTipos extends StatelessWidget {
  final Map<String, int> porTipo;

  const _GraficoBarrasTipos({required this.porTipo});

  @override
  Widget build(BuildContext context) {
    if (porTipo.isEmpty) {
      return const SizedBox(
        height: 160,
        child: Center(
          child: Text('Sin infracciones en el último mes ✅',
              style: TextStyle(color: Colors.greenAccent)),
        ),
      );
    }
    // Top 5 por count
    final ordenados = porTipo.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = ordenados.take(5).toList();
    final maxValor = top.first.value.toDouble();
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 16, 8),
        child: SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxValor * 1.2,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (v, m) => Text(
                      v.toInt().toString(),
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 10),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 42,
                    getTitlesWidget: (v, m) {
                      final i = v.toInt();
                      if (i < 0 || i >= top.length) {
                        return const SizedBox.shrink();
                      }
                      // Acortamos a 12 chars + ellipsis para que entre
                      final nombre = top[i].key;
                      final short = nombre.length > 12
                          ? '${nombre.substring(0, 12)}…'
                          : nombre;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          short,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 9),
                          textAlign: TextAlign.center,
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: List.generate(top.length, (i) {
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: top[i].value.toDouble(),
                      color: Colors.redAccent.withValues(alpha: 0.8),
                      width: 22,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ],
                );
              }),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) =>
                      Colors.black.withValues(alpha: 0.85),
                  getTooltipItem: (g, gIdx, r, rIdx) => BarTooltipItem(
                    '${top[g.x].key}\n${top[g.x].value} infracciones',
                    const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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

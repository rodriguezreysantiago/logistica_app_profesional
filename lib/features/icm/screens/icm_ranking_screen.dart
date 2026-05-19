import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/excluidos_service.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../services/icm_calculator.dart';

/// Ranking de choferes ordenado del peor al mejor según ICM. Filtros
/// rápidos por rango (esta semana / este mes / mes anterior /
/// personalizado). Click en una fila → drill-down al detalle.
class IcmRankingScreen extends StatefulWidget {
  const IcmRankingScreen({super.key});

  @override
  State<IcmRankingScreen> createState() => _IcmRankingScreenState();
}

enum _Rango { semana, mes, mesAnterior }

class _IcmRankingScreenState extends State<IcmRankingScreen> {
  _Rango _rango = _Rango.mes;
  Future<List<IcmChofer>>? _futureRanking;

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  void _recargar() {
    final (desde, hasta) = _calcularRango(_rango);
    _futureRanking = _cargarRanking(desde, hasta);
  }

  /// Devuelve `(desdeMs, hastaMs)` según el rango seleccionado, en ART.
  (int, int) _calcularRango(_Rango r) {
    final ahora = DateTime.now();
    switch (r) {
      case _Rango.semana:
        // Últimos 7 días.
        return (ahora.subtract(const Duration(days: 7)).millisecondsSinceEpoch,
            ahora.millisecondsSinceEpoch);
      case _Rango.mes:
        // Mes calendario actual.
        final inicio = DateTime(ahora.year, ahora.month, 1);
        return (inicio.millisecondsSinceEpoch, ahora.millisecondsSinceEpoch);
      case _Rango.mesAnterior:
        final inicioMesActual = DateTime(ahora.year, ahora.month, 1);
        final inicioMesAnterior =
            DateTime(ahora.year, ahora.month - 1, 1);
        return (inicioMesAnterior.millisecondsSinceEpoch,
            inicioMesActual.millisecondsSinceEpoch);
    }
  }

  Future<List<IcmChofer>> _cargarRanking(int desdeMs, int hastaMs) async {
    final db = FirebaseFirestore.instance;
    // Cargar excluidos (tanqueros + testers) ANTES de queryear ranking.
    // Si están en cache se resuelve sincrónico; sino paga 2 queries
    // (~60 docs) amortizadas en todas las pantallas de la sesión.
    final excluidos = await ExcluidosService.cargar(db: db);
    // Lookup de nombres de empleados (1 query a EMPLEADOS, ~60 docs).
    final empSnap = await db.collection('EMPLEADOS').get();
    final nombrePorDni = <String, String>{};
    for (final d in empSnap.docs) {
      final data = d.data();
      final dni = (data['DNI'] ?? d.id).toString();
      final nombre = (data['NOMBRE'] ?? '').toString().trim();
      if (nombre.isNotEmpty) nombrePorDni[dni] = nombre;
    }
    final ranking = await IcmCalculator.calcularRanking(
      db: db,
      desdeMs: desdeMs,
      hastaMs: hastaMs,
      nombrePorDni: nombrePorDni,
    );
    // Removemos a los tanqueros y testers del ranking visible. Sus
    // eventos no son nuestros (tanqueros) o son ficticios (testers),
    // así que mezclarlos rompe el ranking de los choferes reales.
    // El CF `recomputeIcmSemanalScheduled` ya hace el mismo filtro
    // server-side para el reporte semanal a Molina — esto cubre la
    // vista en vivo del admin.
    ranking.removeWhere((c) => ExcluidosService.esExcluido(
          excluidos,
          dni: c.choferDni,
        ));
    return ranking;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Ranking ICM',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BarraFiltros(
            rangoActual: _rango,
            onChanged: (r) {
              setState(() {
                _rango = r;
                _recargar();
              });
            },
          ),
          Expanded(
            child: FutureBuilder<List<IcmChofer>>(
              future: _futureRanking,
              builder: (ctx, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Error cargando ranking: ${snap.error}',
                        style: const TextStyle(color: Colors.redAccent),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                final lista = snap.data ?? const [];
                if (lista.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Sin datos en el rango seleccionado.',
                        style: TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: lista.length,
                  itemBuilder: (ctx, i) => _FilaChofer(
                    posicion: i + 1,
                    chofer: lista[i],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BarraFiltros extends StatelessWidget {
  final _Rango rangoActual;
  final ValueChanged<_Rango> onChanged;

  const _BarraFiltros({required this.rangoActual, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Wrap(
        spacing: 8,
        children: [
          _ChipRango(
              label: 'Últimos 7 días',
              activo: rangoActual == _Rango.semana,
              onTap: () => onChanged(_Rango.semana)),
          _ChipRango(
              label: 'Mes actual',
              activo: rangoActual == _Rango.mes,
              onTap: () => onChanged(_Rango.mes)),
          _ChipRango(
              label: 'Mes anterior',
              activo: rangoActual == _Rango.mesAnterior,
              onTap: () => onChanged(_Rango.mesAnterior)),
        ],
      ),
    );
  }
}

class _ChipRango extends StatelessWidget {
  final String label;
  final bool activo;
  final VoidCallback onTap;

  const _ChipRango({
    required this.label,
    required this.activo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: activo,
      onSelected: (_) => onTap(),
    );
  }
}

class _FilaChofer extends StatelessWidget {
  final int posicion;
  final IcmChofer chofer;

  const _FilaChofer({required this.posicion, required this.chofer});

  @override
  Widget build(BuildContext context) {
    final color = _colorCategoria(chofer.categoria);
    final icmStr = chofer.categoria == CategoriaIcm.sinDatos
        ? '—'
        : chofer.icm.toStringAsFixed(0);
    final ratioStr =
        chofer.infraccionesPor100Km.toStringAsFixed(2);
    final patentePrincipal =
        chofer.patentes.isNotEmpty ? chofer.patentes.first : '—';
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color.withValues(alpha: 0.40), width: 1),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: SizedBox(
          width: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '#$posicion',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  icmStr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        title: Text(
          chofer.choferNombre,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DNI ${AppFormatters.formatearDNI(chofer.choferDni)} · '
                'Patente principal: $patentePrincipal',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(height: 2),
              Text(
                '${chofer.totalEventos} eventos · '
                '$ratioStr cada 100 km · '
                'Categoría: ${_labelCategoria(chofer.categoria)}',
                style: TextStyle(color: color, fontSize: 11),
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: () => Navigator.pushNamed(
          context,
          AppRoutes.adminIcmDetalleChofer,
          arguments: chofer.choferDni,
        ),
      ),
    );
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

  String _labelCategoria(CategoriaIcm c) {
    switch (c) {
      case CategoriaIcm.bajo:
        return 'BAJO (verde)';
      case CategoriaIcm.medio:
        return 'MEDIO (amarillo)';
      case CategoriaIcm.alto:
        return 'ALTO (rojo)';
      case CategoriaIcm.sinDatos:
        return 'sin datos';
    }
  }
}

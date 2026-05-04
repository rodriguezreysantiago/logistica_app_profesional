import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/constants/app_colors.dart';
import '../../../shared/widgets/app_widgets.dart';

/// Pantalla "Descargas por unidad" — lista de eventos PTO (toma de fuerza)
/// del Vehicle Alerts API.
///
/// En la flota de Coopertrans, un evento PTO = batea levantada para
/// descargar carga (ningún tractor tiene grúa hidráulica). Cada evento
/// queda registrado por Volvo con timestamp, geo-coords, patente y un
/// snapshot del chofer asignado (cruce automático en `volvoAlertasPoller`
/// con el log de `ASIGNACIONES_VEHICULO`).
///
/// Casos de uso:
///   - Anti-fraude: validar que la descarga ocurrió donde dice el remito.
///   - Tiempo retenido por cliente: cuántos minutos en descarga por sitio.
///   - Productividad por chofer: comparar tiempos de descarga.
///   - Insumo del módulo de planeamiento de viajes futuro.
class AdminDescargasPtoScreen extends StatefulWidget {
  const AdminDescargasPtoScreen({super.key});

  @override
  State<AdminDescargasPtoScreen> createState() =>
      _AdminDescargasPtoScreenState();
}

class _AdminDescargasPtoScreenState extends State<AdminDescargasPtoScreen> {
  /// Día seleccionado — por default hoy. El operador puede cambiar a
  /// cualquier día anterior con el botón calendario del AppBar.
  late DateTime _fecha;
  String? _filtroPatente;

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    _fecha = DateTime(ahora.year, ahora.month, ahora.day);
  }

  bool get _esHoy {
    final hoy = DateTime.now();
    return _fecha.year == hoy.year &&
        _fecha.month == hoy.month &&
        _fecha.day == hoy.day;
  }

  String get _etiquetaFecha {
    final d = _fecha.day.toString().padLeft(2, '0');
    final m = _fecha.month.toString().padLeft(2, '0');
    return _esHoy ? 'HOY ($d-$m-${_fecha.year})' : '$d-$m-${_fecha.year}';
  }

  Future<void> _elegirFecha() async {
    final ahora = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2024),
      lastDate: ahora,
      helpText: 'Elegir día de descargas',
      cancelText: 'CANCELAR',
      confirmText: 'VER',
      locale: const Locale('es', 'AR'),
    );
    if (picked != null && mounted) {
      setState(() {
        _fecha = picked;
        _filtroPatente = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final inicio = DateTime(_fecha.year, _fecha.month, _fecha.day);
    final fin = inicio.add(const Duration(days: 1));
    return AppScaffold(
      title: 'Descargas (PTO)',
      actions: [
        IconButton(
          icon: const Icon(Icons.calendar_month_outlined),
          tooltip: 'Elegir día',
          onPressed: _elegirFecha,
        ),
        if (!_esHoy)
          IconButton(
            icon: const Icon(Icons.today_outlined),
            tooltip: 'Volver a hoy',
            onPressed: () {
              final hoy = DateTime.now();
              setState(() {
                _fecha = DateTime(hoy.year, hoy.month, hoy.day);
                _filtroPatente = null;
              });
            },
          ),
      ],
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection(AppCollections.volvoAlertas)
            .where('tipo', isEqualTo: 'PTO')
            .where('creado_en',
                isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
            .where('creado_en', isLessThan: Timestamp.fromDate(fin))
            .orderBy('creado_en', descending: true)
            .snapshots(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accentGreen),
            );
          }
          if (snap.hasError) {
            return AppErrorState(
              title: 'No pudimos cargar las descargas',
              subtitle: snap.error.toString(),
            );
          }
          final docs = snap.data?.docs ?? const [];
          if (docs.isEmpty) {
            return AppEmptyState(
              icon: Icons.local_shipping_outlined,
              title: 'Sin descargas el $_etiquetaFecha',
              subtitle: _esHoy
                  ? 'Todavía no hubo eventos PTO hoy. Probá con otro día.'
                  : 'No hay eventos PTO ese día. Elegí otra fecha.',
            );
          }

          // Patentes únicas para el filtro.
          final patentes = <String>{
            for (final d in docs)
              if ((d.data()['patente'] ?? '').toString().isNotEmpty)
                d.data()['patente'].toString()
          }.toList()
            ..sort();

          // Filtrar in-memory por patente si hay filtro.
          final visibles = _filtroPatente == null
              ? docs
              : docs
                  .where((d) =>
                      (d.data()['patente'] ?? '').toString() == _filtroPatente)
                  .toList();

          return Column(
            children: [
              _Toolbar(
                totalEventos: docs.length,
                visibles: visibles.length,
                patentes: patentes,
                filtroPatente: _filtroPatente,
                onFiltroChange: (p) => setState(() => _filtroPatente = p),
                etiquetaFecha: _etiquetaFecha,
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                  itemCount: visibles.length,
                  itemBuilder: (_, i) => _EventoPtoCard(
                    data: visibles[i].data(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final int totalEventos;
  final int visibles;
  final List<String> patentes;
  final String? filtroPatente;
  final ValueChanged<String?> onFiltroChange;
  final String etiquetaFecha;

  const _Toolbar({
    required this.totalEventos,
    required this.visibles,
    required this.patentes,
    required this.filtroPatente,
    required this.onFiltroChange,
    required this.etiquetaFecha,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$visibles de $totalEventos descargas · $etiquetaFecha',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _ChipFiltro(
                  label: 'TODAS',
                  selected: filtroPatente == null,
                  onTap: () => onFiltroChange(null),
                ),
                const SizedBox(width: 6),
                ...patentes.map((p) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _ChipFiltro(
                        label: p,
                        selected: filtroPatente == p,
                        onTap: () => onFiltroChange(p),
                      ),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipFiltro extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChipFiltro({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accentGreen : Colors.white38;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentGreen.withAlpha(25)
              : Colors.white.withAlpha(8),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withAlpha(80)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _EventoPtoCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _EventoPtoCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final creado = (data['creado_en'] as Timestamp?)?.toDate();
    final patente = (data['patente'] ?? '—').toString();
    final choferNombre = (data['chofer_nombre'] ?? '').toString();
    final choferDni = (data['chofer_dni'] ?? '').toString();
    final chofer = choferNombre.isNotEmpty
        ? choferNombre
        : choferDni.isNotEmpty
            ? 'DNI $choferDni'
            : 'Chofer no asignado';

    final gps = data['posicion_gps'] as Map<String, dynamic>?;
    final lat = (gps?['lat'] as num?)?.toDouble();
    final lng = (gps?['lng'] as num?)?.toDouble();

    final detalle = data['detalle_pto'] as Map<String, dynamic>?;

    return AppCard(
      borderColor: AppColors.accentGreen.withAlpha(40),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_shipping, color: AppColors.accentGreen, size: 18),
              const SizedBox(width: 8),
              Text(
                patente,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (creado != null)
                Text(
                  fmt.format(creado),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Chofer: $chofer',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (detalle != null && detalle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _resumirDetalle(detalle),
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
          if (lat != null && lng != null) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => _abrirMaps(lat, lng),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.accentBlue.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.accentBlue.withAlpha(60)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.place, color: AppColors.accentBlue, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                      style: const TextStyle(
                        color: AppColors.accentBlue,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.open_in_new,
                        color: AppColors.accentBlue, size: 12),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _resumirDetalle(Map<String, dynamic> det) {
    // El sub-objeto detalle_pto puede traer mode/duration/etc. según Volvo
    // entrega. Mostramos los más útiles si están — el resto se ignora.
    final partes = <String>[];
    final mode = det['mode']?.toString();
    if (mode != null && mode.isNotEmpty) partes.add('Modo: $mode');
    final duration = det['duration'];
    if (duration is num) {
      final mins = (duration / 60).toStringAsFixed(0);
      partes.add('Duración: ${mins}min');
    }
    if (partes.isEmpty) {
      return 'Detalle: ${det.keys.take(3).join(', ')}';
    }
    return partes.join(' · ');
  }

  Future<void> _abrirMaps(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps?q=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

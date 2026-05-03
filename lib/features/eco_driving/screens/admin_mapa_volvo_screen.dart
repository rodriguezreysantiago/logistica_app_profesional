import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/constants/app_colors.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../widgets/evento_volvo_detalle_sheet.dart';

/// Pantalla "Mapa Volvo" — visualización geográfica de todos los eventos
/// del Vehicle Alerts API sobre OpenStreetMap.
///
/// Para qué sirve:
///   - Detectar PATRONES geográficos: "todos los OVERSPEED están en el
///     tramo entre planta y ruta 5 → ahí los choferes saben que no hay
///     control".
///   - Detectar accesos a clientes congestionados (DISTANCE_ALERT en
///     bocacalles concretas).
///   - Anti-fraude visual: ver dónde se levantó la batea (PTO) — si
///     aparece en una banquina rara, es bandera roja.
///   - Vista de plata: el admin ve la flota completa de un vistazo.
///
/// Diseño:
///   - Mapa centrado en Bahía Blanca (centro operativo de Vecchi).
///   - Pins coloreados por SEVERIDAD (rojo HIGH, amarillo MEDIUM,
///     verde LOW).
///   - Filtros: rango temporal (popup AppBar), tipos de evento
///     (chips horizontales), patente (chips horizontales).
///   - Tap en pin → bottom sheet con detalle + acción "Marcar atendida".
class AdminMapaVolvoScreen extends StatefulWidget {
  const AdminMapaVolvoScreen({super.key});

  @override
  State<AdminMapaVolvoScreen> createState() => _AdminMapaVolvoScreenState();
}

class _AdminMapaVolvoScreenState extends State<AdminMapaVolvoScreen> {
  // Bahía Blanca centro — operación de Vecchi. Razonable como centro
  // inicial; el zoom muestra la región.
  static const _centroInicial = LatLng(-38.7196, -62.2724);
  static const _zoomInicial = 8.0;

  int _diasRango = 30;
  String? _filtroTipo; // null = todos los tipos
  String? _filtroPatente; // null = todas las patentes

  final _mapController = MapController();

  DateTime get _desde => DateTime.now().subtract(Duration(days: _diasRango));

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Mapa Volvo',
      actions: [
        PopupMenuButton<int>(
          icon: const Icon(Icons.calendar_today),
          tooltip: 'Rango temporal',
          initialValue: _diasRango,
          onSelected: (v) => setState(() => _diasRango = v),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 7, child: Text('Últimos 7 días')),
            PopupMenuItem(value: 15, child: Text('Últimos 15 días')),
            PopupMenuItem(value: 30, child: Text('Últimos 30 días')),
            PopupMenuItem(value: 60, child: Text('Últimos 60 días')),
            PopupMenuItem(value: 90, child: Text('Últimos 90 días')),
          ],
        ),
      ],
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection(AppCollections.volvoAlertas)
            .where('creado_en',
                isGreaterThanOrEqualTo: Timestamp.fromDate(_desde))
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
              title: 'No pudimos cargar el mapa',
              subtitle: snap.error.toString(),
            );
          }

          final allDocs = snap.data?.docs ?? const [];
          // Filtramos in-memory por tipo y patente. Eventos sin GPS
          // válido los descartamos (no se pueden mapear).
          final docsConGps = allDocs.where(_tieneGpsValido).toList();
          final tiposDisponibles = <String>{
            for (final d in docsConGps)
              if ((d.data()['tipo'] ?? '').toString().isNotEmpty)
                d.data()['tipo'].toString()
          }.toList()
            ..sort();
          final patentesDisponibles = <String>{
            for (final d in docsConGps)
              if ((d.data()['patente'] ?? '').toString().isNotEmpty)
                d.data()['patente'].toString()
          }.toList()
            ..sort();

          final visibles = docsConGps.where((d) {
            final data = d.data();
            if (_filtroTipo != null &&
                (data['tipo'] ?? '').toString() != _filtroTipo) {
              return false;
            }
            if (_filtroPatente != null &&
                (data['patente'] ?? '').toString() != _filtroPatente) {
              return false;
            }
            return true;
          }).toList();

          return Column(
            children: [
              _Toolbar(
                totalEventos: allDocs.length,
                conGps: docsConGps.length,
                visibles: visibles.length,
                tipos: tiposDisponibles,
                patentes: patentesDisponibles,
                filtroTipo: _filtroTipo,
                filtroPatente: _filtroPatente,
                onTipoChange: (v) => setState(() => _filtroTipo = v),
                onPatenteChange: (v) => setState(() => _filtroPatente = v),
                rangoDias: _diasRango,
              ),
              Expanded(
                child: _Mapa(
                  controller: _mapController,
                  centroInicial: _centroInicial,
                  zoomInicial: _zoomInicial,
                  docs: visibles,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static bool _tieneGpsValido(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final gps = d.data()['posicion_gps'];
    if (gps is! Map) return false;
    final lat = gps['lat'];
    final lng = gps['lng'];
    return lat is num && lng is num;
  }
}

// =============================================================================
// TOOLBAR (filtros + contador)
// =============================================================================

class _Toolbar extends StatelessWidget {
  final int totalEventos;
  final int conGps;
  final int visibles;
  final List<String> tipos;
  final List<String> patentes;
  final String? filtroTipo;
  final String? filtroPatente;
  final ValueChanged<String?> onTipoChange;
  final ValueChanged<String?> onPatenteChange;
  final int rangoDias;

  const _Toolbar({
    required this.totalEventos,
    required this.conGps,
    required this.visibles,
    required this.tipos,
    required this.patentes,
    required this.filtroTipo,
    required this.filtroPatente,
    required this.onTipoChange,
    required this.onPatenteChange,
    required this.rangoDias,
  });

  @override
  Widget build(BuildContext context) {
    final sinGps = totalEventos - conGps;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(80),
        border: Border(
          bottom: BorderSide(color: Colors.white.withAlpha(20)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$visibles de $conGps eventos georref. (${sinGps > 0 ? "$sinGps sin GPS · " : ""}rango $rangoDias d)',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 6),
          // Filtros de tipo (chip horizontal scrolleable).
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _Chip(
                  label: 'TODOS',
                  selected: filtroTipo == null,
                  onTap: () => onTipoChange(null),
                ),
                const SizedBox(width: 4),
                for (final t in tipos)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _Chip(
                      label: t,
                      selected: filtroTipo == t,
                      onTap: () => onTipoChange(t),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Filtros de patente.
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _Chip(
                  label: 'TODAS',
                  selected: filtroPatente == null,
                  onTap: () => onPatenteChange(null),
                ),
                const SizedBox(width: 4),
                for (final p in patentes)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _Chip(
                      label: p,
                      selected: filtroPatente == p,
                      onTap: () => onPatenteChange(p),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accentGreen : Colors.white38;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentGreen.withAlpha(25)
              : Colors.white.withAlpha(8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withAlpha(80)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// MAPA
// =============================================================================

class _Mapa extends StatelessWidget {
  final MapController controller;
  final LatLng centroInicial;
  final double zoomInicial;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  const _Mapa({
    required this.controller,
    required this.centroInicial,
    required this.zoomInicial,
    required this.docs,
  });

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: centroInicial,
        initialZoom: zoomInicial,
        minZoom: 4,
        maxZoom: 18,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.coopertrans.movil',
          // Tiles se descargan on-demand. La cache la maneja flutter_map
          // internamente — queda en memoria por defecto. Suficiente para
          // sesiones admin de minutos.
        ),
        MarkerLayer(
          markers: docs
              .map((d) => _markerDeDoc(context, d))
              .whereType<Marker>()
              .toList(),
        ),
        // Atribución obligatoria de OpenStreetMap. Required by their TOS.
        const RichAttributionWidget(
          attributions: [
            TextSourceAttribution(
              '© OpenStreetMap',
            ),
          ],
        ),
      ],
    );
  }

  Marker? _markerDeDoc(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final gps = data['posicion_gps'];
    if (gps is! Map) return null;
    final lat = (gps['lat'] as num?)?.toDouble();
    final lng = (gps['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    final severidad = (data['severidad'] ?? '').toString().toUpperCase();
    final atendida = data['atendida'] == true;
    final color = atendida
        ? Colors.white38
        : severidad == 'HIGH'
            ? AppColors.accentRed
            : severidad == 'MEDIUM'
                ? AppColors.accentOrange
                : AppColors.accentGreen;

    return Marker(
      point: LatLng(lat, lng),
      width: 28,
      height: 28,
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: () => _mostrarDetalle(context, doc),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withAlpha(220),
            border: Border.all(color: Colors.black.withAlpha(120), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(80),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.warning_amber_rounded,
            color: Colors.black,
            size: 14,
          ),
        ),
      ),
    );
  }

  void _mostrarDetalle(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => EventoVolvoDetalleSheet(
        alertId: doc.id,
        data: doc.data(),
      ),
    );
  }
}

// =============================================================================
// HELPER: formato de fecha para etiquetas
// =============================================================================

// Exportado para reuso en el bottom sheet del detalle.
String formatearFechaHoraEvento(Timestamp? ts) {
  if (ts == null) return '—';
  return DateFormat('dd/MM HH:mm').format(ts.toDate());
}

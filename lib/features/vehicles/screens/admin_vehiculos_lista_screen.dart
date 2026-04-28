import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../providers/vehiculo_provider.dart';

import 'admin_vehiculo_alta_screen.dart';
import 'admin_vehiculo_form_screen.dart';

/// Pantalla de Gestión de Flota.
///
/// Migrada al sistema de diseño unificado (AppScaffold + AppListPage +
/// AppCard + AppDetailSheet + VencimientoBadge + AppFileThumbnail).
class AdminVehiculosListaScreen extends StatefulWidget {
  const AdminVehiculosListaScreen({super.key});

  @override
  State<AdminVehiculosListaScreen> createState() =>
      _AdminVehiculosListaScreenState();
}

class _AdminVehiculosListaScreenState
    extends State<AdminVehiculosListaScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<VehiculoProvider>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: AppScaffold(
        title: 'Gestión de Flota',
        bottom: const TabBar(
          tabs: [
            Tab(text: 'TRACTORES'),
            Tab(text: 'BATEAS'),
            Tab(text: 'TOLVAS'),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminVehiculoAltaScreen(),
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text('NUEVO'),
        ),
        body: const TabBarView(
          children: [
            _ListaPorTipo(tipo: 'TRACTOR'),
            _ListaPorTipo(tipo: 'BATEA'),
            _ListaPorTipo(tipo: 'TOLVA'),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// LISTA POR TIPO (un AppListPage por tab)
// =============================================================================

class _ListaPorTipo extends StatelessWidget {
  final String tipo;
  const _ListaPorTipo({required this.tipo});

  @override
  Widget build(BuildContext context) {
    return Consumer<VehiculoProvider>(
      builder: (ctx, provider, _) => AppListPage(
        stream: provider.getVehiculosPorTipo(tipo),
        searchHint: 'Buscar patente, marca, modelo o VIN...',
        emptyTitle: 'Sin ${_pluralPretty(tipo)} cargados',
        emptySubtitle: 'Tocá el botón + para agregar uno',
        emptyIcon: Icons.local_shipping_outlined,
        filter: (doc, q) {
          final data = doc.data() as Map<String, dynamic>;
          final hay = '${doc.id} ${data['MARCA'] ?? ''} '
                  '${data['MODELO'] ?? ''} ${data['VIN'] ?? ''}'
              .toUpperCase();
          return hay.contains(q);
        },
        itemBuilder: (ctx, doc) => _VehiculoCard(doc: doc),
      ),
    );
  }

  String _pluralPretty(String tipo) {
    switch (tipo) {
      case 'TRACTOR':
        return 'tractores';
      case 'BATEA':
        return 'bateas';
      case 'TOLVA':
        return 'tolvas';
      default:
        return tipo.toLowerCase();
    }
  }
}

// =============================================================================
// TARJETA DE VEHÍCULO (vista colapsada)
// =============================================================================

class _VehiculoCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  const _VehiculoCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final patente = doc.id;
    final marca = (data['MARCA'] ?? 'S/D').toString();
    final modelo = (data['MODELO'] ?? 'S/D').toString();
    final estado = (data['ESTADO'] ?? 'LIBRE').toString().toUpperCase();
    final km = data['KM_ACTUAL'];

    return Selector<VehiculoProvider,
        ({bool loading, bool success, String? error})>(
      selector: (_, p) => (
        loading: p.isLoading(patente),
        success: p.isSuccess(patente),
        error: p.getError(patente),
      ),
      builder: (ctx, state, _) {
        return AppCard(
          onTap: () => _abrirDetalle(context, patente, data),
          highlighted: state.success || state.error != null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: patente + badge estado + indicadores
              Row(
                children: [
                  Text(
                    patente.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _EstadoBadge(estado: estado),
                  const Spacer(),
                  if (state.loading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  if (state.success)
                    const Icon(Icons.check_circle,
                        color: Colors.greenAccent, size: 16),
                  if (state.error != null)
                    const Icon(Icons.error_outline,
                        color: Colors.redAccent, size: 16),
                ],
              ),
              const SizedBox(height: 6),
              // Subtítulo: marca/modelo + km
              Row(
                children: [
                  Icon(Icons.local_shipping,
                      size: 12, color: Colors.white.withAlpha(120)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$marca $modelo',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.speed,
                      size: 12, color: Colors.white.withAlpha(120)),
                  const SizedBox(width: 4),
                  Text(
                    '${AppFormatters.formatearKilometraje(km)} km',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Vista rápida de vencimientos (badges compactos)
              Row(
                children: [
                  _MiniVencimiento(
                      label: 'RTO', fecha: data['VENCIMIENTO_RTO']),
                  const SizedBox(width: 14),
                  _MiniVencimiento(
                      label: 'Seguro', fecha: data['VENCIMIENTO_SEGURO']),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Dispara el sync con Volvo si corresponde y abre el bottom sheet de detalle.
  void _abrirDetalle(BuildContext context, String patente,
      Map<String, dynamic> data) {
    final marca = (data['MARCA'] ?? '').toString().toUpperCase();
    final vin = (data['VIN'] ?? '').toString();

    // Sync no bloqueante: si es Volvo y tiene VIN, refrescamos el KM en
    // segundo plano. El stream del documento se actualiza solo cuando termina.
    if (marca == 'VOLVO' && vin.isNotEmpty) {
      final p = context.read<VehiculoProvider>();
      if (!p.isLoading(patente) && p.debeSincronizar(patente)) {
        p.sync(patente, vin);
      }
    }

    AppDetailSheet.show(
      context: context,
      title: 'Ficha $patente',
      icon: Icons.local_shipping,
      actions: [
        IconButton(
          icon: const Icon(Icons.edit, color: Colors.greenAccent, size: 20),
          tooltip: 'Editar ficha',
          onPressed: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminVehiculoFormScreen(
                  vehiculoId: patente,
                  datosIniciales: data,
                ),
              ),
            );
          },
        ),
      ],
      builder: (sheetCtx, scrollCtl) => _DetalleVehiculo(
        patente: patente,
        dataInicial: data,
        scrollController: scrollCtl,
      ),
    );
  }
}

// =============================================================================
// DETALLE DEL VEHÍCULO (contenido del bottom sheet)
// =============================================================================

class _DetalleVehiculo extends StatelessWidget {
  final String patente;
  final Map<String, dynamic> dataInicial;
  final ScrollController scrollController;

  const _DetalleVehiculo({
    required this.patente,
    required this.dataInicial,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('VEHICULOS')
          .doc(patente)
          .snapshots(),
      builder: (ctx, snap) {
        // Mientras llega el primer snapshot mostramos los datos que
        // teníamos del listado, así no parpadea el sheet.
        final data = snap.hasData && snap.data!.exists
            ? snap.data!.data() as Map<String, dynamic>
            : dataInicial;

        return _buildBody(data);
      },
    );
  }

  Widget _buildBody(Map<String, dynamic> data) {
    final marca = (data['MARCA'] ?? 'S/D').toString();
    final modelo = (data['MODELO'] ?? 'S/D').toString();
    final anio = (data['ANIO'] ?? data['AÑO'] ?? '').toString();
    final estado = (data['ESTADO'] ?? 'LIBRE').toString().toUpperCase();
    final vin = (data['VIN'] ?? '').toString();
    final km = data['KM_ACTUAL'];

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        // Header con marca + modelo + estado
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$marca $modelo'.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (anio.isNotEmpty && anio != '0')
                    Text(
                      'Año $anio',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                ],
              ),
            ),
            _EstadoBadge(estado: estado),
          ],
        ),
        const SizedBox(height: 16),

        // Tarjeta de KM destacada
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.greenAccent.withAlpha(15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.greenAccent.withAlpha(40)),
          ),
          child: Row(
            children: [
              const Icon(Icons.speed, color: Colors.greenAccent),
              const SizedBox(width: 10),
              const Text('Kilometraje',
                  style: TextStyle(color: Colors.white60, fontSize: 12)),
              const Spacer(),
              Text(
                '${AppFormatters.formatearKilometraje(km)} km',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),
        const _SectionTitle(icon: Icons.fingerprint, label: 'Datos técnicos'),
        _InfoRow(
            label: 'VIN',
            valor: vin.isEmpty ? '—' : vin,
            monoespaciado: true),
        _InfoRow(
            label: 'Empresa', valor: (data['EMPRESA'] ?? '—').toString()),

        const SizedBox(height: 18),
        const _SectionTitle(icon: Icons.event, label: 'Vencimientos'),
        _VencimientoRow(
          etiqueta: 'RTO / VTV',
          fecha: data['VENCIMIENTO_RTO'],
          url: data['ARCHIVO_RTO'],
          tituloVisor: 'RTO $patente',
        ),
        _VencimientoRow(
          etiqueta: 'Póliza Seguro',
          fecha: data['VENCIMIENTO_SEGURO'],
          url: data['ARCHIVO_SEGURO'],
          tituloVisor: 'Seguro $patente',
        ),

        if (data['ULTIMA_SINCRO'] != null) ...[
          const SizedBox(height: 18),
          const _SectionTitle(icon: Icons.sync, label: 'Sincronización Volvo'),
          Row(
            children: [
              Text(
                _formatTimestamp(data['ULTIMA_SINCRO']),
                style:
                    const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(width: 8),
              if ((data['SINCRO_TIPO'] ?? '') != '')
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    (data['SINCRO_TIPO'] ?? '').toString(),
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ],

        const SizedBox(height: 30),
      ],
    );
  }

  String _formatTimestamp(dynamic ts) {
    DateTime? d;
    if (ts is Timestamp) {
      d = ts.toDate();
    } else if (ts is DateTime) {
      d = ts;
    } else if (ts is String) {
      d = DateTime.tryParse(ts);
    }
    if (d == null) {
      return '—';
    }

    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) {
      return 'hace ${diff.inSeconds}s';
    }
    if (diff.inMinutes < 60) {
      return 'hace ${diff.inMinutes}min';
    }
    if (diff.inHours < 24) {
      return 'hace ${diff.inHours}h';
    }
    if (diff.inDays < 7) {
      return 'hace ${diff.inDays}d';
    }
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}

// =============================================================================
// WIDGETS PRIVADOS DE ESTA PANTALLA (no se reutilizan en otras)
// =============================================================================

class _EstadoBadge extends StatelessWidget {
  final String estado;
  const _EstadoBadge({required this.estado});

  Color get _color {
    switch (estado.toUpperCase()) {
      case 'LIBRE':
        return Colors.greenAccent;
      case 'OCUPADO':
      case 'ASIGNADO':
        return Colors.blueAccent;
      case 'TALLER':
      case 'MANTENIMIENTO':
        return Colors.orangeAccent;
      case 'BAJA':
      case 'INACTIVO':
        return Colors.redAccent;
      default:
        return Colors.white54;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withAlpha(80)),
      ),
      child: Text(
        estado,
        style: TextStyle(
          color: _color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _MiniVencimiento extends StatelessWidget {
  final String label;
  final dynamic fecha;
  const _MiniVencimiento({required this.label, required this.fecha});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.event, size: 12, color: Colors.white38),
        const SizedBox(width: 4),
        Text(label,
            style:
                const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(width: 6),
        VencimientoBadge(fecha: fecha, compact: true),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.greenAccent, size: 16),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String valor;
  final bool monoespaciado;
  const _InfoRow({
    required this.label,
    required this.valor,
    this.monoespaciado = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFamily: monoespaciado ? 'monospace' : null,
                letterSpacing: monoespaciado ? 0.5 : 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VencimientoRow extends StatelessWidget {
  final String etiqueta;
  final dynamic fecha;
  final String? url;
  final String tituloVisor;

  const _VencimientoRow({
    required this.etiqueta,
    required this.fecha,
    required this.url,
    required this.tituloVisor,
  });

  @override
  Widget build(BuildContext context) {
    final tieneFecha = fecha != null && fecha.toString().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          AppFileThumbnail(url: url, tituloVisor: tituloVisor),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: Text(
              etiqueta,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              tieneFecha ? AppFormatters.formatearFecha(fecha) : '—',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          VencimientoBadge(fecha: fecha),
        ],
      ),
    );
  }
}

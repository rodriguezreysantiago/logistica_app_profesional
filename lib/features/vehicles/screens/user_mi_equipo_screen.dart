import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/app_widgets.dart';

/// Pantalla del chofer: ver y gestionar su equipo asignado (tractor + enganche).
///
/// Permite solicitar un cambio de unidad. La solicitud queda pendiente
/// hasta que el admin la apruebe.
class UserMiEquipoScreen extends StatefulWidget {
  final String dniUser;

  const UserMiEquipoScreen({super.key, required this.dniUser});

  @override
  State<UserMiEquipoScreen> createState() => _UserMiEquipoScreenState();
}

class _UserMiEquipoScreenState extends State<UserMiEquipoScreen> {
  late final Stream<DocumentSnapshot> _empleadoStream;
  late final Stream<QuerySnapshot> _solicitudesStream;

  @override
  void initState() {
    super.initState();
    _empleadoStream = FirebaseFirestore.instance
        .collection('EMPLEADOS')
        .doc(widget.dniUser)
        .snapshots();
    _solicitudesStream = FirebaseFirestore.instance
        .collection('REVISIONES')
        .where('dni', isEqualTo: widget.dniUser)
        .where('tipo_solicitud', isEqualTo: 'CAMBIO_EQUIPO')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Mi Equipo Asignado',
      body: StreamBuilder<DocumentSnapshot>(
        stream: _empleadoStream,
        builder: (context, empSnap) {
          if (empSnap.connectionState == ConnectionState.waiting) {
            return const AppLoadingState();
          }
          if (!empSnap.hasData || !empSnap.data!.exists) {
            return const AppErrorState(
              title: 'Error al cargar perfil',
              subtitle: 'No se encontraron tus datos.',
            );
          }

          final empleado = empSnap.data!.data() as Map<String, dynamic>;
          final nombreChofer = (empleado['NOMBRE'] ?? 'Chofer').toString();
          final patenteVehiculo =
              (empleado['VEHICULO'] ?? '').toString().trim();
          final patenteEnganche =
              (empleado['ENGANCHE'] ?? '').toString().trim();

          return StreamBuilder<QuerySnapshot>(
            stream: _solicitudesStream,
            builder: (context, soliSnap) {
              final solicitudes = soliSnap.data?.docs ?? [];

              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _SeccionUnidad(
                    titulo: 'TRACTOR / CHASIS',
                    icono: Icons.local_shipping_outlined,
                    patente: patenteVehiculo,
                    solicitudes: solicitudes,
                    claveSolicitud: 'SOLICITUD_VEHICULO',
                    nombreChofer: nombreChofer,
                  ),
                  const SizedBox(height: 24),
                  _SeccionUnidad(
                    titulo: 'ENGANCHE (Batea/Tolva)',
                    icono: Icons.grid_view_rounded,
                    patente: patenteEnganche,
                    solicitudes: solicitudes,
                    claveSolicitud: 'SOLICITUD_ENGANCHE',
                    nombreChofer: nombreChofer,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// =============================================================================
// SECCIÓN DE UNA UNIDAD (TRACTOR o ENGANCHE)
// =============================================================================

class _SeccionUnidad extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final String patente;
  final List<QueryDocumentSnapshot> solicitudes;
  final String claveSolicitud;
  final String nombreChofer;

  const _SeccionUnidad({
    required this.titulo,
    required this.icono,
    required this.patente,
    required this.solicitudes,
    required this.claveSolicitud,
    required this.nombreChofer,
  });

  @override
  Widget build(BuildContext context) {
    final solicitudPendiente = solicitudes.where((s) {
      final data = s.data() as Map<String, dynamic>;
      return data['campo'] == claveSolicitud;
    }).toList();

    final tienePendiente = solicitudPendiente.isNotEmpty;
    final estaVacia =
        patente.isEmpty || patente == '-' || patente == 'SIN ASIGNAR';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header de la sección
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.greenAccent,
                  letterSpacing: 2,
                ),
              ),
              if (!estaVacia && !tienePendiente)
                TextButton.icon(
                  onPressed: () => _SelectorCambio.abrir(
                    context,
                    titulo: titulo,
                    patenteActual: patente,
                    nombreChofer: nombreChofer,
                  ),
                  icon: const Icon(Icons.swap_horiz,
                      size: 16, color: Colors.orangeAccent),
                  label: const Text(
                    'SOLICITAR CAMBIO',
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Contenido según estado
        if (tienePendiente)
          _CardEnRevision(solicitud: solicitudPendiente.first)
        else if (estaVacia)
          const _CardSinAsignacion()
        else
          _CardUnidad(patente: patente, icono: icono),
      ],
    );
  }
}

// =============================================================================
// CARDS DE LAS DISTINTAS SITUACIONES
// =============================================================================

/// Card que muestra cuando hay una solicitud de cambio en revisión.
class _CardEnRevision extends StatelessWidget {
  final QueryDocumentSnapshot solicitud;
  const _CardEnRevision({required this.solicitud});

  @override
  Widget build(BuildContext context) {
    final data = solicitud.data() as Map<String, dynamic>;
    final patenteSolicitada = (data['patente'] ?? '—').toString();

    return AppCard(
      highlighted: true,
      borderColor: Colors.orangeAccent.withAlpha(150),
      child: Row(
        children: [
          const Icon(Icons.history_toggle_off,
              color: Colors.orangeAccent, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CAMBIO A $patenteSolicitada',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'VALIDACIÓN PENDIENTE...',
                  style: TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
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

class _CardSinAsignacion extends StatelessWidget {
  const _CardSinAsignacion();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.white24),
          SizedBox(width: 12),
          Text(
            'Sin unidad asignada',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// Card de la unidad asignada con sus datos y vencimientos.
class _CardUnidad extends StatelessWidget {
  final String patente;
  final IconData icono;

  const _CardUnidad({required this.patente, required this.icono});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('VEHICULOS')
          .doc(patente)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const _CardSinAsignacion();
        }
        final v = snap.data!.data() as Map<String, dynamic>;

        return AppCard(
          padding: EdgeInsets.zero,
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              // Header con patente grande
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    Icon(icono, color: Colors.white70, size: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            patente.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Text(
                                'MARCA: ',
                                style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                (v['MARCA'] ?? 'S/D').toString(),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'MODELO: ',
                                style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  (v['MODELO'] ?? 'S/D').toString(),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
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
              const Divider(color: Colors.white10, height: 1),
              // Vencimientos
              _FilaVencimiento(
                etiqueta: 'RTO / VTV',
                fecha: v['VENCIMIENTO_RTO'],
                url: v['ARCHIVO_RTO']?.toString(),
                tituloVisor: 'RTO $patente',
              ),
              _FilaVencimiento(
                etiqueta: 'Póliza Seguro',
                fecha: v['VENCIMIENTO_SEGURO'],
                url: v['ARCHIVO_SEGURO']?.toString(),
                tituloVisor: 'Seguro $patente',
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _FilaVencimiento extends StatelessWidget {
  final String etiqueta;
  final dynamic fecha;
  final String? url;
  final String tituloVisor;

  const _FilaVencimiento({
    required this.etiqueta,
    required this.fecha,
    required this.url,
    required this.tituloVisor,
  });

  @override
  Widget build(BuildContext context) {
    final tieneFecha = fecha != null && fecha.toString().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          AppFileThumbnail(url: url, tituloVisor: tituloVisor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiqueta,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tieneFecha
                      ? AppFormatters.formatearFecha(fecha)
                      : 'Sin fecha',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          VencimientoBadge(fecha: fecha),
        ],
      ),
    );
  }
}

// =============================================================================
// SELECTOR DE NUEVA UNIDAD (al solicitar cambio)
// =============================================================================

class _SelectorCambio {
  _SelectorCambio._();

  /// Abre un bottom sheet con las unidades LIBRES del tipo correspondiente.
  static Future<void> abrir(
    BuildContext context, {
    required String titulo,
    required String patenteActual,
    required String nombreChofer,
  }) {
    final esTractor = titulo.contains('TRACTOR');
    final tipoBusqueda = esTractor ? 'TRACTOR' : null;

    return AppDetailSheet.show(
      context: context,
      title: 'Seleccionar nuevo $titulo',
      icon: Icons.swap_horiz,
      builder: (sheetCtx, scrollCtl) => _ListaUnidadesLibres(
        scrollController: scrollCtl,
        tipoBusqueda: tipoBusqueda,
        patenteActual: patenteActual,
        titulo: titulo,
        nombreChofer: nombreChofer,
      ),
    );
  }
}

class _ListaUnidadesLibres extends StatelessWidget {
  final ScrollController scrollController;
  final String? tipoBusqueda;
  final String patenteActual;
  final String titulo;
  final String nombreChofer;

  const _ListaUnidadesLibres({
    required this.scrollController,
    required this.tipoBusqueda,
    required this.patenteActual,
    required this.titulo,
    required this.nombreChofer,
  });

  @override
  Widget build(BuildContext context) {
    final stream = tipoBusqueda != null
        ? FirebaseFirestore.instance
            .collection('VEHICULOS')
            .where('TIPO', isEqualTo: tipoBusqueda)
            .where('ESTADO', isEqualTo: 'LIBRE')
            .snapshots()
        : FirebaseFirestore.instance
            .collection('VEHICULOS')
            .where('TIPO', whereIn: const ['BATEA', 'TOLVA', 'ACOPLADO'])
            .where('ESTADO', isEqualTo: 'LIBRE')
            .snapshots();

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text(
            'Solo se muestran unidades disponibles (LIBRE)',
            style: TextStyle(color: Colors.greenAccent, fontSize: 11),
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: stream,
            builder: (context, snap) {
              if (!snap.hasData) return const AppLoadingState();
              final unidades = snap.data!.docs
                  .where((d) => d.id != patenteActual)
                  .toList();

              if (unidades.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.directions_car_outlined,
                  title: 'No hay unidades libres',
                  subtitle:
                      'Volvé a intentarlo más tarde o consultá con tu administrador.',
                );
              }

              return ListView.builder(
                controller: scrollController,
                itemCount: unidades.length,
                itemBuilder: (ctx, idx) {
                  final unidad = unidades[idx];
                  final data = unidad.data() as Map<String, dynamic>;
                  return ListTile(
                    leading: const Icon(Icons.check_circle_outline,
                        color: Colors.white38),
                    title: Text(
                      unidad.id,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '${data['MARCA'] ?? 'S/D'} ${data['MODELO'] ?? ''}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                    trailing: const Icon(Icons.add_circle,
                        color: Colors.orangeAccent),
                    onTap: () {
                      Navigator.pop(context);
                      _enviarSolicitud(
                        context,
                        titulo: titulo,
                        actual: patenteActual,
                        nueva: unidad.id,
                        nombre: nombreChofer,
                        dni: _dniFromContext(context),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Helper: extrae el DNI del state padre (UserMiEquipoScreen).
  String _dniFromContext(BuildContext context) {
    final state =
        context.findAncestorStateOfType<_UserMiEquipoScreenState>();
    return state?.widget.dniUser ?? '';
  }

  Future<void> _enviarSolicitud(
    BuildContext context, {
    required String titulo,
    required String actual,
    required String nueva,
    required String nombre,
    required String dni,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final esTractor = titulo.contains('TRACTOR');

    try {
      await FirebaseFirestore.instance.collection('REVISIONES').add({
        'dni': dni,
        'nombre_usuario': nombre,
        'etiqueta':
            'CAMBIO DE ${esTractor ? "UNIDAD" : "EQUIPO"}',
        'campo': esTractor ? 'SOLICITUD_VEHICULO' : 'SOLICITUD_ENGANCHE',
        'patente': nueva,
        'unidad_actual': actual,
        'fecha_vencimiento': '2026-12-31',
        'tipo_solicitud': 'CAMBIO_EQUIPO',
        'coleccion_destino': 'EMPLEADOS',
        'url_archivo': '',
        // ✅ Campo necesario para que el contador del panel admin la cuente.
        'estado': 'PENDIENTE',
        'fecha_solicitud': FieldValue.serverTimestamp(),
      });

      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Solicitud enviada. Aguarde aprobación de oficina.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      debugPrint('Error solicitud: $e');
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error al enviar solicitud: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}

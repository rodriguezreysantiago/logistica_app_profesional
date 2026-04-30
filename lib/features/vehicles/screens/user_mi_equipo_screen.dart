import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/vencimientos_config.dart';
import '../../../shared/utils/app_feedback.dart';
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
                    dni: widget.dniUser,
                  ),
                  const SizedBox(height: 24),
                  _SeccionUnidad(
                    titulo: 'ENGANCHE (Batea/Tolva)',
                    icono: Icons.grid_view_rounded,
                    patente: patenteEnganche,
                    solicitudes: solicitudes,
                    claveSolicitud: 'SOLICITUD_ENGANCHE',
                    nombreChofer: nombreChofer,
                    dni: widget.dniUser,
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
  final String dni;

  const _SeccionUnidad({
    required this.titulo,
    required this.icono,
    required this.patente,
    required this.solicitudes,
    required this.claveSolicitud,
    required this.nombreChofer,
    required this.dni,
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
                    dni: dni,
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
              // Telemetría en vivo (combustible + autonomía).
              // Solo se renderiza si la unidad reporta esos datos vía
              // Volvo Connect — para marcas no-Volvo o sincros viejas
              // queda colapsado y no muestra nada.
              _BloqueTelemetria(data: v),
              // Vencimientos: lista construida desde AppVencimientos
              // según el TIPO de la unidad. Tractor → 4 (RTO, Seguro,
              // Extintor Cabina, Extintor Exterior). Enganche → 2.
              for (final spec
                  in AppVencimientos.forTipo(v['TIPO']?.toString()))
                _FilaVencimiento(
                  etiqueta: spec.etiqueta,
                  fecha: v[spec.campoFecha],
                  url: v[spec.campoArchivo]?.toString(),
                  tituloVisor: '${spec.etiqueta} $patente',
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

/// Bloque de telemetría en vivo del vehículo: nivel de combustible y
/// autonomía estimada. Lee los campos `NIVEL_COMBUSTIBLE` y `AUTONOMIA_KM`
/// que el AutoSyncService va escribiendo en Firestore desde Volvo Connect.
///
/// Si la unidad no reporta esos datos (marca no-Volvo, telemetría
/// desconectada, sincronización vieja), el bloque entero no se muestra
/// para no llenar la UI con "—" sin sentido.
class _BloqueTelemetria extends StatelessWidget {
  final Map<String, dynamic> data;

  const _BloqueTelemetria({required this.data});

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  @override
  Widget build(BuildContext context) {
    // La telemetría aplica SOLO a tractores: los enganches (bateas,
    // tolvas, bivuelcos, tanques) no tienen motor ni computadora a
    // bordo, así que no reportan odómetro, combustible ni autonomía.
    final tipo = (data['TIPO'] ?? '').toString().toUpperCase();
    if (tipo != 'TRACTOR' && tipo != 'CHASIS') {
      return const SizedBox.shrink();
    }

    final fuel = _toDouble(data['NIVEL_COMBUSTIBLE']);
    final auton = _toDouble(data['AUTONOMIA_KM']);
    final km = _toDouble(data['KM_ACTUAL']);

    // Tratamos el odómetro 0 como "no hay lectura todavía" (cualquier
    // tractor en operación tiene km > 0; el 0 viene del valor inicial
    // que se setea al crear el vehículo).
    final mostrarKm = km != null && km > 0;

    // Si no tenemos NINGÚN dato útil, no renderizamos nada.
    if (fuel == null && auton == null && !mostrarKm) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          if (mostrarKm)
            Expanded(
              child: _DatoTelemetria(
                icono: Icons.speed,
                color: Colors.white70,
                valor: '${km.toStringAsFixed(0)} km',
                etiqueta: 'ODÓMETRO',
              ),
            ),
          if (fuel != null)
            Expanded(
              child: _DatoCombustible(porcentaje: fuel),
            ),
          if (auton != null)
            Expanded(
              child: _DatoTelemetria(
                icono: Icons.route,
                color: Colors.cyanAccent,
                valor: '${auton.toStringAsFixed(0)} km',
                etiqueta: 'AUTONOMÍA',
              ),
            ),
        ],
      ),
    );
  }
}

class _DatoTelemetria extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String valor;
  final String etiqueta;

  const _DatoTelemetria({
    required this.icono,
    required this.color,
    required this.valor,
    required this.etiqueta,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icono, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          valor,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          etiqueta,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

/// Muestra el % de combustible con una barra horizontal. Cambia de color
/// según el nivel: verde > 50%, naranja 20-50%, rojo < 20%.
class _DatoCombustible extends StatelessWidget {
  final double porcentaje;

  const _DatoCombustible({required this.porcentaje});

  Color get _color {
    if (porcentaje >= 50) return Colors.greenAccent;
    if (porcentaje >= 20) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final pct = porcentaje.clamp(0.0, 100.0);
    return Column(
      children: [
        Icon(Icons.local_gas_station, color: _color, size: 22),
        const SizedBox(height: 6),
        Text(
          '${pct.toStringAsFixed(0)}%',
          style: TextStyle(
            color: _color,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        // Barra horizontal mini que refuerza visualmente el nivel.
        SizedBox(
          width: 60,
          height: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: pct / 100,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(_color),
            ),
          ),
        ),
      ],
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
    required String dni,
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
        dni: dni,
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
  final String dni;

  const _ListaUnidadesLibres({
    required this.scrollController,
    required this.tipoBusqueda,
    required this.patenteActual,
    required this.titulo,
    required this.nombreChofer,
    required this.dni,
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
            .where('TIPO', whereIn: AppTiposVehiculo.enganches)
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
                        // dni se pasa explícito desde el ancestor — antes
                        // se buscaba con findAncestorStateOfType, pero
                        // como el sheet vive en su propio Overlay esa
                        // búsqueda fallaba y devolvía '' (string vacío).
                        dni: dni,
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

    // Defensa profunda: si por algún motivo (refactor futuro, bug en el
    // árbol de widgets) llegáramos acá con campos vacíos, no creamos
    // una solicitud "envenenada" que el admin no pueda aprobar después.
    final cleanDni = dni.trim();
    final cleanNueva = nueva.trim();
    if (cleanDni.isEmpty || cleanNueva.isEmpty) {
      debugPrint(
          'Solicitud bloqueada: dni="$cleanDni" nueva="$cleanNueva"');
      AppFeedback.errorOn(messenger, 'No se pudo enviar la solicitud (faltan datos del chofer o la unidad). Cerrá la app y volvé a iniciar sesión.');
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('REVISIONES').add({
        'dni': cleanDni,
        'nombre_usuario': nombre,
        'etiqueta':
            'CAMBIO DE ${esTractor ? "UNIDAD" : "EQUIPO"}',
        'campo': esTractor ? 'SOLICITUD_VEHICULO' : 'SOLICITUD_ENGANCHE',
        'patente': cleanNueva,
        'unidad_actual': actual.trim(),
        'fecha_vencimiento': '2026-12-31',
        'tipo_solicitud': 'CAMBIO_EQUIPO',
        'coleccion_destino': 'EMPLEADOS',
        'url_archivo': '',
        // ✅ Campo necesario para que el contador del panel admin la cuente.
        'estado': 'PENDIENTE',
        'fecha_solicitud': FieldValue.serverTimestamp(),
      });

      if (!context.mounted) return;
      AppFeedback.warningOn(messenger, 'Solicitud enviada. Aguarde aprobación de oficina.');
    } catch (e) {
      debugPrint('Error solicitud: $e');
      if (!context.mounted) return;
      AppFeedback.errorOn(messenger, 'Error al enviar solicitud: $e');
    }
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/utils/app_feedback.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/fecha_dialog.dart';
import '../widgets/mantenimiento_badge.dart';
import 'admin_vehiculos_lista_screen.dart' show abrirDetalleVehiculo;

/// Pantalla de mantenimiento preventivo.
///
/// Lista los TRACTORES ordenados por urgencia de service (vencidos
/// primero, después por menor `SERVICE_DISTANCE_KM`). Los datos
/// vienen de la colección `VEHICULOS`, donde `SERVICE_DISTANCE_KM`
/// se actualiza automáticamente por el `AutoSyncService` cada vez
/// que sincroniza con Volvo.
///
/// **Ordenamiento client-side** (no orderBy Firestore): la flota es
/// chica (<100 tractores) y evitar el índice compuesto
/// `TIPO + SERVICE_DISTANCE_KM` simplifica la rule de seguridad.
///
/// **Wrapper público** para abrir desde otros features (ej. CommandPalette
/// o el panel admin).
Future<void> abrirMantenimientoPreventivo(BuildContext context) async {
  await Navigator.pushNamed(context, AppRoutes.adminMantenimiento);
}

class AdminMantenimientoScreen extends StatefulWidget {
  const AdminMantenimientoScreen({super.key});

  @override
  State<AdminMantenimientoScreen> createState() =>
      _AdminMantenimientoScreenState();
}

class _AdminMantenimientoScreenState extends State<AdminMantenimientoScreen> {
  late final Stream<QuerySnapshot> _tractoresStream;
  final TextEditingController _searchCtl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Solo TRACTORES — los enganches no tienen telemetría Volvo (no
    // tienen motor / VIN registrado en Volvo Connect).
    _tractoresStream = FirebaseFirestore.instance
        .collection(AppCollections.vehiculos)
        .where('TIPO', isEqualTo: AppTiposVehiculo.tractor)
        .snapshots();

    _searchCtl.addListener(() {
      if (!mounted) return;
      setState(() => _query = _searchCtl.text.toUpperCase().trim());
    });
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Mantenimiento preventivo',
      body: StreamBuilder<QuerySnapshot>(
        stream: _tractoresStream,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const AppLoadingState();
          }
          if (snap.hasError) {
            return AppErrorState(
              title: 'No se pudo cargar la flota',
              subtitle: snap.error.toString(),
            );
          }

          final docs = snap.data?.docs ?? [];

          // Sort alfabético por patente (doc.id). Más predecible para el
          // admin que ya conoce las patentes de memoria. Los chips del
          // resumen siguen mostrando el conteo por urgencia, así que la
          // info crítica (cuántos vencidos hay) sigue visible arriba.
          final sorted = [...docs]
            ..sort((a, b) => a.id.compareTo(b.id));

          // Filtro de búsqueda por patente / marca / modelo.
          final filtrados = sorted.where((doc) {
            if (_query.isEmpty) return true;
            final data = doc.data() as Map<String, dynamic>;
            final hay = '${doc.id} '
                    '${data['MARCA'] ?? ''} '
                    '${data['MODELO'] ?? ''}'
                .toUpperCase();
            return hay.contains(_query);
          }).toList();

          // Resumen agregado: cuántos vencidos / urgentes / etc.
          final resumen = _Resumen.from(sorted);

          if (docs.isEmpty) {
            return const AppEmptyState(
              title: 'Sin tractores cargados',
              subtitle:
                  'Cuando agregues TRACTORES con VIN, su mantenimiento aparecerá acá.',
              icon: Icons.local_shipping_outlined,
            );
          }

          return Column(
            children: [
              _BarraResumen(resumen: resumen),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  controller: _searchCtl,
                  decoration: const InputDecoration(
                    hintText: 'Buscar patente, marca o modelo...',
                    prefixIcon: Icon(Icons.search, color: Colors.white38),
                    isDense: true,
                  ),
                ),
              ),
              Expanded(
                child: filtrados.isEmpty
                    ? const AppEmptyState(
                        title: 'No se encontraron coincidencias',
                        subtitle: 'Probá con otro término.',
                        icon: Icons.search_off,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(10, 4, 10, 80),
                        itemCount: filtrados.length,
                        itemBuilder: (ctx, idx) =>
                            _TractorCard(doc: filtrados[idx]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// =============================================================================
// RESOLUCIÓN DE serviceDistance: API > MANUAL > NINGUNO
// =============================================================================

enum _FuenteServiceDistance { api, manual, ninguno }

/// Resultado del cálculo de `serviceDistance` para un tractor.
/// `km` puede ser negativo (vencido). Si la fuente es `ninguno`, `km` es null.
class _ResolucionServiceDistance {
  final double? km;
  final _FuenteServiceDistance fuente;
  const _ResolucionServiceDistance(this.km, this.fuente);
}

/// Decide qué `serviceDistance` mostrar para un tractor:
/// 1. Si el doc tiene `SERVICE_DISTANCE_KM` (vino del API Volvo) → API.
/// 2. Si tiene `ULTIMO_SERVICE_KM` cargado manualmente + `KM_ACTUAL` →
///    calcula `(ULTIMO_SERVICE_KM + 50.000) − KM_ACTUAL`.
/// 3. Si nada → ninguno (la pantalla muestra un hint).
///
/// Vecchi cae en path 2 porque el paquete API actual no entrega
/// `uptimeData.serviceDistance`. Si en el futuro Volvo lo habilita,
/// el path 1 toma prioridad sin tocar nada en la app.
_ResolucionServiceDistance _resolverServiceDistance(
    Map<String, dynamic> data) {
  final api = (data['SERVICE_DISTANCE_KM'] as num?)?.toDouble();
  if (api != null) {
    return _ResolucionServiceDistance(api, _FuenteServiceDistance.api);
  }
  final calculado = AppMantenimiento.serviceDistanceDesdeManual(
    ultimoServiceKm: (data['ULTIMO_SERVICE_KM'] as num?)?.toDouble(),
    kmActual: (data['KM_ACTUAL'] as num?)?.toDouble(),
  );
  if (calculado != null) {
    return _ResolucionServiceDistance(
        calculado, _FuenteServiceDistance.manual);
  }
  return const _ResolucionServiceDistance(null,
      _FuenteServiceDistance.ninguno);
}

// =============================================================================
// CARD DE TRACTOR
// =============================================================================

class _TractorCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  const _TractorCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final patente = doc.id;
    final marca = (data['MARCA'] ?? '').toString();
    final modelo = (data['MODELO'] ?? '').toString();
    final kmActual = (data['KM_ACTUAL'] as num?)?.toDouble();
    final manualUltimoKm =
        (data['ULTIMO_SERVICE_KM'] as num?)?.toDouble();

    // serviceDistance "efectivo": prefiere el del API; si no existe,
    // calcula desde ULTIMO_SERVICE_KM (manual) + 50.000 − KM_ACTUAL.
    // Vecchi cae en el segundo caso porque el plan API no entrega
    // `uptimeData.serviceDistance`.
    final servicio = _resolverServiceDistance(data);
    final serviceDistanceKm = servicio.km;
    final fuenteApi = servicio.fuente == _FuenteServiceDistance.api;
    final estado = AppMantenimiento.clasificar(serviceDistanceKm);

    // ─── Último service y km recorridos ──────────────────────────────
    // Si el admin lo cargó manualmente, eso es la verdad. Si no,
    // calculamos desde KM_ACTUAL + serviceDistance API − intervalo.
    // Si vinimos por path manual ya sabemos el último, no hace falta
    // calcularlo otra vez.
    double? ultimoServiceKm;
    bool ultimoServiceFuenteManual = false;
    if (manualUltimoKm != null) {
      ultimoServiceKm = manualUltimoKm;
      ultimoServiceFuenteManual = true;
    } else if (fuenteApi) {
      ultimoServiceKm = AppMantenimiento.calcularKmUltimoService(
        kmActual: kmActual,
        serviceDistanceKm: serviceDistanceKm,
      );
    }

    double? kmRecorridos;
    if (ultimoServiceKm != null && kmActual != null) {
      kmRecorridos = kmActual - ultimoServiceKm;
    }

    // Fecha del último service (solo si la cargó el admin a mano).
    final ultimoServiceFechaRaw =
        data['ULTIMO_SERVICE_FECHA']?.toString() ?? '';
    final ultimoServiceFecha = ultimoServiceFechaRaw.isNotEmpty
        ? DateTime.tryParse(ultimoServiceFechaRaw)
        : null;

    // Si no hay datos suficientes (sin API y sin manual cargado), la
    // card muestra un hint para que el admin cargue el último service.
    final faltaCargaInicial =
        servicio.fuente == _FuenteServiceDistance.ninguno;

    return AppCard(
      onTap: () {
        // Abre directo la ficha del tractor en un sheet (mismo flujo
        // que la lista de Flota). Reusamos el helper público
        // `abrirDetalleVehiculo` para no duplicar la lógica del sheet.
        abrirDetalleVehiculo(context, patente, data);
      },
      child: Row(
        children: [
          // Avatar con icono según estado.
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: estado.color.withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _iconoSegunEstado(estado),
              color: estado.color,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patente,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$marca $modelo'.trim().isEmpty
                      ? 'Sin marca/modelo'
                      : '$marca $modelo',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  estado.etiqueta,
                  style: TextStyle(
                    color: estado.color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
                if (faltaCargaInicial) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Cargá el último service desde la ficha para ver KM al próximo',
                    style: TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ] else if (ultimoServiceKm != null ||
                    ultimoServiceFecha != null ||
                    kmRecorridos != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _formatearUltimoService(
                      km: ultimoServiceKm,
                      fecha: ultimoServiceFecha,
                      kmRecorridos: kmRecorridos,
                      fuenteManual: ultimoServiceFuenteManual,
                    ),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MantenimientoBadge(serviceDistanceKm: serviceDistanceKm),
              const SizedBox(height: 6),
              // Botón "Service hecho" — abre dialog que pre-carga el
              // odómetro actual y permite ajustar la fecha si el service
              // fue ayer/anteayer. Lo dejamos visible siempre (incluso
              // en estado OK) por si se hace un service preventivo o
              // intermedio antes del momento exacto.
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _confirmarServiceHecho(
                  context,
                  patente: patente,
                  marca: marca,
                  modelo: modelo,
                  kmActual: kmActual,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: Colors.greenAccent.withAlpha(60)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 12, color: Colors.greenAccent),
                      SizedBox(width: 4),
                      Text(
                        'Service hecho',
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Dialog que registra "service hecho hoy" para un tractor.
  ///
  /// Pre-carga el odómetro actual desde Volvo. El admin puede confirmar
  /// con la fecha de hoy o ajustar (si el service fue ayer/anteayer).
  /// Si el odómetro no está disponible (raro), avisa al admin que cargue
  /// el dato manualmente desde la ficha.
  static Future<void> _confirmarServiceHecho(
    BuildContext context, {
    required String patente,
    required String marca,
    required String modelo,
    required double? kmActual,
  }) async {
    final messenger = ScaffoldMessenger.of(context);

    if (kmActual == null) {
      AppFeedback.warningOn(messenger,
          'Sin KM_ACTUAL para $patente. Cargá el último service desde la ficha.');
      return;
    }

    DateTime fechaElegida = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (sbCtx, setStateDialog) => AlertDialog(
          title: Text('Marcar service hecho — $patente'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$marca $modelo'.trim().isEmpty
                    ? 'Tractor $patente'
                    : '$marca $modelo · $patente',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Text(
                'Odómetro actual: ${kmActual.round()} km',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Próximo service quedará a ${(kmActual + AppMantenimiento.intervaloServiceKm).round()} km.',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () async {
                  final picked = await pickFecha(
                    sbCtx,
                    initial: fechaElegida,
                    titulo: 'Fecha del service',
                  );
                  if (picked != null) {
                    setStateDialog(() => fechaElegida = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event,
                          color: Colors.greenAccent, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        'Fecha: ${AppFormatters.formatearFecha(fechaElegida.toString().split(" ").first)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      const Spacer(),
                      const Icon(Icons.edit_calendar,
                          color: Colors.white24, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(dCtx, true),
              icon: const Icon(Icons.check_circle),
              label: const Text('REGISTRAR'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('VEHICULOS')
          .doc(patente)
          .update({
        'ULTIMO_SERVICE_KM': kmActual,
        'ULTIMO_SERVICE_FECHA':
            fechaElegida.toString().split(' ').first,
        'fecha_ultima_actualizacion': FieldValue.serverTimestamp(),
      });
      AppFeedback.successOn(
        messenger,
        'Service registrado para $patente. Próximo a ${(kmActual + AppMantenimiento.intervaloServiceKm).round()} km.',
      );
    } catch (e) {
      AppFeedback.errorOn(messenger, 'No se pudo guardar: $e');
    }
  }

  /// Formatea "Último service: ~342.000 km · 38.000 km recorridos".
  ///
  /// El "~" antepuesto indica que el dato se infirió a partir de
  /// `KM_ACTUAL + serviceDistance − 50.000`. Si el admin lo cargó a
  /// mano desde la ficha (`fuenteManual: true`), el "~" se omite porque
  /// es dato verificado.
  static String _formatearUltimoService({
    double? km,
    DateTime? fecha,
    double? kmRecorridos,
    bool fuenteManual = false,
  }) {
    final partes = <String>[];
    if (km != null) {
      final prefijo = fuenteManual ? '' : '~';
      partes.add('$prefijo${km.round()} km');
    }
    if (kmRecorridos != null) {
      partes.add('${kmRecorridos.round()} km recorridos');
    }
    if (fecha != null) {
      partes.add(_tiempoRelativo(fecha));
    }
    return 'Último service: ${partes.join(' · ')}';
  }

  /// Devuelve "hoy", "hace X días", "hace X meses", "hace X años".
  static String _tiempoRelativo(DateTime fecha) {
    final dias = DateTime.now().difference(fecha).inDays;
    if (dias < 0) return 'fecha futura';
    if (dias == 0) return 'hoy';
    if (dias == 1) return 'hace 1 día';
    if (dias < 30) return 'hace $dias días';
    if (dias < 60) return 'hace 1 mes';
    if (dias < 365) {
      final meses = (dias / 30).round();
      return 'hace $meses meses';
    }
    final anios = (dias / 365).round();
    return anios == 1 ? 'hace 1 año' : 'hace $anios años';
  }

  IconData _iconoSegunEstado(MantenimientoEstado estado) {
    switch (estado) {
      case MantenimientoEstado.vencido:
        return Icons.warning_amber_rounded;
      case MantenimientoEstado.urgente:
        return Icons.priority_high;
      case MantenimientoEstado.programar:
        return Icons.event_note;
      case MantenimientoEstado.atencion:
        return Icons.schedule;
      case MantenimientoEstado.ok:
        return Icons.check_circle;
      case MantenimientoEstado.sinDato:
        return Icons.help_outline;
    }
  }
}

// =============================================================================
// RESUMEN AGREGADO (chips arriba de la lista)
// =============================================================================

class _Resumen {
  final int vencidos;
  final int urgentes;
  final int programar;
  final int atencion;
  final int ok;
  final int sinDato;

  const _Resumen({
    required this.vencidos,
    required this.urgentes,
    required this.programar,
    required this.atencion,
    required this.ok,
    required this.sinDato,
  });

  factory _Resumen.from(List<QueryDocumentSnapshot> docs) {
    int vencidos = 0, urgentes = 0, programar = 0, atencion = 0, ok = 0;
    int sinDato = 0;
    for (final d in docs) {
      final data = d.data() as Map<String, dynamic>;
      // Mismo resolver que la card: API > manual > ninguno. Mantiene
      // los chips consistentes con cada tarjeta.
      final servicio = _resolverServiceDistance(data);
      switch (AppMantenimiento.clasificar(servicio.km)) {
        case MantenimientoEstado.vencido:
          vencidos++;
          break;
        case MantenimientoEstado.urgente:
          urgentes++;
          break;
        case MantenimientoEstado.programar:
          programar++;
          break;
        case MantenimientoEstado.atencion:
          atencion++;
          break;
        case MantenimientoEstado.ok:
          ok++;
          break;
        case MantenimientoEstado.sinDato:
          sinDato++;
          break;
      }
    }
    return _Resumen(
      vencidos: vencidos,
      urgentes: urgentes,
      programar: programar,
      atencion: atencion,
      ok: ok,
      sinDato: sinDato,
    );
  }
}

class _BarraResumen extends StatelessWidget {
  final _Resumen resumen;
  const _BarraResumen({required this.resumen});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          _Chip(
            label: 'Vencidos',
            count: resumen.vencidos,
            color: Colors.redAccent,
          ),
          _Chip(
            label: 'Urgentes',
            count: resumen.urgentes,
            color: Colors.orangeAccent,
          ),
          _Chip(
            label: 'Programar',
            count: resumen.programar,
            color: Colors.amberAccent,
          ),
          _Chip(
            label: 'Falta poco',
            count: resumen.atencion,
            color: const Color(0xFFC6FF00),
          ),
          _Chip(
            label: 'OK',
            count: resumen.ok,
            color: Colors.greenAccent,
          ),
          if (resumen.sinDato > 0)
            _Chip(
              label: 'Sin datos',
              count: resumen.sinDato,
              color: Colors.white24,
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _Chip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

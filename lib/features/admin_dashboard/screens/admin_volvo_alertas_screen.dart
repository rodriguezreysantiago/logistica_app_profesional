import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/audit_log_service.dart';
import '../../../core/services/prefs_service.dart';
import '../../../shared/constants/app_colors.dart';
import '../../../shared/utils/app_feedback.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../eco_driving/utils/etiquetas_alerta_volvo.dart';

/// Pantalla "Alertas Volvo" del admin/supervisor.
///
/// Lista los eventos del Vehicle Alerts API que el `volvoAlertasPoller`
/// (scheduled cada 5 min) guarda en `VOLVO_ALERTAS`.
///
/// **Diseño revisado 2026-05-04**: por default muestra SOLO las alertas
/// del día actual. El operador puede elegir otra fecha con el calendario,
/// o togglear "Mostrar atendidas" para ver todo el día (sin importar
/// estado). El histórico de muchos días se ve cambiando de fecha — no
/// hay vista "todas las alertas de los últimos N días" para evitar
/// listas inmanejables (a 50 eventos/día, 200 = ~4 días).
///
/// Query: `where('creado_en', between [startOfDay, endOfDay))` +
/// `orderBy('creado_en', desc)`. Where + orderBy en el MISMO campo →
/// no requiere índice compuesto.
class AdminVolvoAlertasScreen extends StatefulWidget {
  const AdminVolvoAlertasScreen({super.key});

  @override
  State<AdminVolvoAlertasScreen> createState() =>
      _AdminVolvoAlertasScreenState();
}

class _AdminVolvoAlertasScreenState extends State<AdminVolvoAlertasScreen> {
  /// Día seleccionado — por default hoy.
  late DateTime _fecha;

  /// `true` (default) → solo alertas no atendidas. `false` → todas.
  bool _soloPendientes = true;

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    _fecha = DateTime(ahora.year, ahora.month, ahora.day);
  }

  Stream<QuerySnapshot> get _alertasStream {
    final inicio = DateTime(_fecha.year, _fecha.month, _fecha.day);
    final fin = inicio.add(const Duration(days: 1));
    // where + orderBy en `creado_en` (mismo campo) → no necesita índice
    // compuesto. Trae como mucho ~50 docs por día.
    return FirebaseFirestore.instance
        .collection(AppCollections.volvoAlertas)
        .where('creado_en',
            isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
        .where('creado_en', isLessThan: Timestamp.fromDate(fin))
        .orderBy('creado_en', descending: true)
        .snapshots();
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
      helpText: 'Elegir día de alertas',
      cancelText: 'CANCELAR',
      confirmText: 'VER',
      locale: const Locale('es', 'AR'),
    );
    if (picked != null && mounted) {
      setState(() => _fecha = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Alertas Volvo',
      body: AppListPage(
        stream: _alertasStream,
        searchHint: 'Buscar por patente, tipo o VIN...',
        emptyTitle: _soloPendientes
            ? 'Sin alertas pendientes ese día'
            : 'Sin alertas registradas ese día',
        emptySubtitle: _soloPendientes
            ? 'Cambiá a "Mostrar atendidas" para ver el histórico del día.'
            : 'Probá con otro día desde el botón de calendario.',
        emptyIcon: Icons.notifications_off_outlined,
        header: _Header(
          fechaEtiqueta: _etiquetaFecha,
          esHoy: _esHoy,
          soloPendientes: _soloPendientes,
          onElegirFecha: _elegirFecha,
          onIrAHoy: () {
            final hoy = DateTime.now();
            setState(() => _fecha = DateTime(hoy.year, hoy.month, hoy.day));
          },
          onTogglePendientes: (v) =>
              setState(() => _soloPendientes = v),
        ),
        filter: (doc, q) {
          final data = doc.data() as Map<String, dynamic>;
          // Filtro client-side de "atendidas" — la query server ya
          // limita por día.
          if (_soloPendientes && data['atendida'] == true) return false;
          if (q.isEmpty) return true;
          final hay = '${data['patente'] ?? ''} '
                  '${data['tipo'] ?? ''} '
                  '${data['vin'] ?? ''} '
                  '${data['severidad'] ?? ''}'
              .toUpperCase();
          return hay.contains(q);
        },
        itemBuilder: (ctx, doc) => _AlertaCard(doc: doc),
      ),
    );
  }
}

// =============================================================================
// HEADER — selector de fecha + filtros
// =============================================================================

class _Header extends StatelessWidget {
  final String fechaEtiqueta;
  final bool esHoy;
  final bool soloPendientes;
  final VoidCallback onElegirFecha;
  final VoidCallback onIrAHoy;
  final ValueChanged<bool> onTogglePendientes;

  const _Header({
    required this.fechaEtiqueta,
    required this.esHoy,
    required this.soloPendientes,
    required this.onElegirFecha,
    required this.onIrAHoy,
    required this.onTogglePendientes,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: onElegirFecha,
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            label: Text(fechaEtiqueta),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(
                color: esHoy ? AppColors.accentGreen : Colors.white38,
              ),
            ),
          ),
          if (!esHoy)
            TextButton.icon(
              onPressed: onIrAHoy,
              icon: const Icon(Icons.today_outlined, size: 18),
              label: const Text('Ir a hoy'),
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.accentGreen),
            ),
          FilterChip(
            label: Text(
              soloPendientes ? 'Solo pendientes' : 'Mostrar todas',
            ),
            selected: soloPendientes,
            onSelected: onTogglePendientes,
            avatar: Icon(
              soloPendientes
                  ? Icons.filter_alt
                  : Icons.filter_alt_off_outlined,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// CARD DE LA ALERTA
// =============================================================================

class _AlertaCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  const _AlertaCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final tipo = (data['tipo'] ?? 'DESCONOCIDO').toString();
    final severidad = (data['severidad'] ?? 'LOW').toString();
    final patente = (data['patente'] ?? '—').toString();
    final atendida = data['atendida'] == true;
    final creadoEn = data['creado_en'] as Timestamp?;
    final atendidaPor = (data['atendida_por'] ?? '').toString();
    final atendidaEn = data['atendida_en'] as Timestamp?;

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _SeveridadChip(severidad: severidad),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    etiquetaAlertaVolvo(tipo),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (atendida)
                  const Chip(
                    label: Text('Atendida'),
                    avatar: Icon(Icons.check_circle, size: 16),
                    backgroundColor: Color(0xFF1B5E20),
                    labelStyle: TextStyle(color: Colors.white, fontSize: 11),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.local_shipping_outlined,
                    size: 16, color: Colors.white70),
                const SizedBox(width: 4),
                Text(patente,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(width: 16),
                const Icon(Icons.access_time,
                    size: 14, color: Colors.white54),
                const SizedBox(width: 4),
                Text(
                  _formatTimestamp(creadoEn),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
            if (atendida) ...[
              const SizedBox(height: 6),
              Text(
                'Atendida por $atendidaPor — ${_formatTimestamp(atendidaEn)}',
                style: const TextStyle(
                    fontSize: 11, color: Colors.white54),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => _marcarAtendida(context),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Marcar atendida'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accentGreen,
                    side: const BorderSide(color: AppColors.accentGreen),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _marcarAtendida(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final dni = PrefsService.dni;
    if (dni.isEmpty) {
      AppFeedback.errorOn(messenger, 'Sin sesión activa.');
      return;
    }
    try {
      await doc.reference.update({
        'atendida': true,
        'atendida_por': dni,
        'atendida_en': FieldValue.serverTimestamp(),
      });
      // Auditoría server-side. Fire-and-forget — si falla, no bloquea
      // al admin (la marca ya quedó persistida).
      final data = doc.data() as Map<String, dynamic>;
      unawaited(AuditLog.registrar(
        accion: AuditAccion.marcarAlertaVolvoAtendida,
        entidad: 'VOLVO_ALERTAS',
        entidadId: doc.id,
        detalles: {
          'tipo': (data['tipo'] ?? '').toString(),
          'severidad': (data['severidad'] ?? '').toString(),
          'patente': (data['patente'] ?? '').toString(),
        },
      ));
      AppFeedback.successOn(messenger, 'Alerta marcada como atendida.');
    } catch (e) {
      AppFeedback.errorOn(messenger, 'Error al marcar atendida: $e');
    }
  }
}

// =============================================================================
// HELPERS
// =============================================================================

String _formatTimestamp(Timestamp? ts) {
  if (ts == null) return '—';
  final dt = ts.toDate().toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.day)}-${two(dt.month)}-${dt.year} '
      '${two(dt.hour)}:${two(dt.minute)}';
}

// =============================================================================
// SEVERIDAD CHIP
// =============================================================================

class _SeveridadChip extends StatelessWidget {
  final String severidad;
  const _SeveridadChip({required this.severidad});

  @override
  Widget build(BuildContext context) {
    final color = switch (severidad.toUpperCase()) {
      'HIGH' => const Color(0xFFD32F2F),    // rojo
      'MEDIUM' => const Color(0xFFEF6C00),  // naranja
      'LOW' => const Color(0xFFFBC02D),     // amarillo
      _ => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        severidad.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

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
/// Lista los eventos que el `volvoAlertasPoller` (scheduled cada 5 min)
/// trae de la Volvo Vehicle Alerts API y guarda en `VOLVO_ALERTAS`:
/// IDLING, OVERSPEED, DISTANCE_ALERT, PTO, TELL_TALE, ALARM, etc.
///
/// El admin puede:
///   - Ver pendientes (default) o todas (toggle).
///   - Filtrar por patente / tipo / VIN.
///   - Marcar como atendida (escribe `atendida=true`, `atendida_por`,
///     `atendida_en` + bitácora `MARCAR_ALERTA_VOLVO_ATENDIDA`).
///
/// La query usa solo `orderBy('creado_en', descending: true)` —
/// single-field index, no requiere índice compuesto.
class AdminVolvoAlertasScreen extends StatefulWidget {
  const AdminVolvoAlertasScreen({super.key});

  @override
  State<AdminVolvoAlertasScreen> createState() =>
      _AdminVolvoAlertasScreenState();
}

class _AdminVolvoAlertasScreenState extends State<AdminVolvoAlertasScreen> {
  late final Stream<QuerySnapshot> _alertasStream;
  bool _soloPendientes = true;

  @override
  void initState() {
    super.initState();
    // Limit defensivo a 200: con ~50 eventos/día, son los últimos ~4 días.
    // Si hay que ver más histórico, sumar paginación o filtros server-side.
    _alertasStream = FirebaseFirestore.instance
        .collection(AppCollections.volvoAlertas)
        .orderBy('creado_en', descending: true)
        .limit(200)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Alertas Volvo',
      body: AppListPage(
        stream: _alertasStream,
        searchHint: 'Buscar por patente, tipo o VIN...',
        emptyTitle: _soloPendientes
            ? 'No hay alertas pendientes'
            : 'Sin alertas registradas',
        emptySubtitle: _soloPendientes
            ? 'Todas las alertas fueron atendidas. Cambiá a "Todas" para ver el histórico.'
            : 'El poller corre cada 5 min. Las alertas nuevas van a aparecer acá.',
        emptyIcon: Icons.notifications_off_outlined,
        header: _buildHeader(),
        filter: (doc, q) {
          final data = doc.data() as Map<String, dynamic>;
          // Toggle "Pendientes" → excluye atendidas.
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

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          FilterChip(
            label: const Text('Solo pendientes'),
            selected: _soloPendientes,
            onSelected: (v) => setState(() => _soloPendientes = v),
            avatar: Icon(
              _soloPendientes
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

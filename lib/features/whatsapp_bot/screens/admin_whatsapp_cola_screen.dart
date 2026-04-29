import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/utils/app_feedback.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../services/whatsapp_cola_service.dart';

/// Pantalla "Cola de WhatsApp" — panel del admin para ver el estado
/// de los mensajes encolados al bot.
///
/// Cada doc se muestra con su estado (PENDIENTE / PROCESANDO / ENVIADO
/// / ERROR), número, mensaje (truncado) y timestamp de encolado. Las
/// filas con error tienen botón "REINTENTAR" que vuelve el estado a
/// PENDIENTE para que el bot lo levante de nuevo.
///
/// El stream es `orderBy(encolado_en, desc).limit(100)` — para una
/// flota chica esto cubre semanas de avisos. Si crece, se puede
/// agregar paginación.
class AdminWhatsAppColaScreen extends StatefulWidget {
  const AdminWhatsAppColaScreen({super.key});

  @override
  State<AdminWhatsAppColaScreen> createState() =>
      _AdminWhatsAppColaScreenState();
}

class _AdminWhatsAppColaScreenState extends State<AdminWhatsAppColaScreen> {
  final WhatsAppColaService _service = WhatsAppColaService();

  Future<void> _reintentar(String id) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.reintentar(id);
      AppFeedback.successOn(messenger, 'Marcado para reintento.');
    } catch (e) {
      AppFeedback.errorOn(messenger, 'No se pudo reintentar: $e');
    }
  }

  Future<void> _eliminar(String id) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await AppConfirmDialog.show(
      context,
      title: '¿Eliminar de la cola?',
      message:
          'El mensaje se borra del historial. Si todavía no se envió, no se va a enviar.',
      confirmLabel: 'ELIMINAR',
      destructive: true,
      icon: Icons.delete_outline,
    );
    if (ok != true) return;
    try {
      await _service.eliminar(id);
      AppFeedback.successOn(messenger, 'Mensaje eliminado.');
    } catch (e) {
      AppFeedback.errorOn(messenger, 'No se pudo eliminar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Cola de WhatsApp',
      body: StreamBuilder<QuerySnapshot>(
        stream: _service.streamCola(),
        builder: (ctx, snap) {
          if (snap.hasError) {
            return AppErrorState(subtitle: snap.error.toString());
          }
          if (!snap.hasData) return const AppLoadingState();
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const AppEmptyState(
              icon: Icons.smart_toy_outlined,
              title: 'No hay mensajes en cola',
              subtitle:
                  'Cuando encoles un aviso desde la auditoría de vencimientos, aparece acá.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
            children: [
              const _ResumenContador(),
              const SizedBox(height: 8),
              ...docs.map((doc) => _ItemCola(
                    doc: doc,
                    onReintentar: () => _reintentar(doc.id),
                    onEliminar: () => _eliminar(doc.id),
                  )),
            ],
          );
        },
      ),
    );
  }
}

// =============================================================================
// RESUMEN COMPACTO ARRIBA
// =============================================================================

/// Mini-row con conteos por estado (PENDIENTE / PROCESANDO / ENVIADO /
/// ERROR). Lee del mismo stream que la lista, así que se actualiza
/// solo cuando el bot mueve docs entre estados.
class _ResumenContador extends StatelessWidget {
  const _ResumenContador();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: WhatsAppColaService().streamCola(limit: 200),
      builder: (ctx, snap) {
        var pendientes = 0, procesando = 0, enviados = 0, errores = 0;
        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final estado = (data['estado'] ?? '').toString();
            if (estado == 'PENDIENTE') pendientes++;
            if (estado == 'PROCESANDO') procesando++;
            if (estado == 'ENVIADO') enviados++;
            if (estado == 'ERROR') errores++;
          }
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              _MiniContador(
                  label: 'Pendientes',
                  count: pendientes,
                  color: Colors.orangeAccent),
              const SizedBox(width: 8),
              _MiniContador(
                  label: 'En envío',
                  count: procesando,
                  color: Colors.blueAccent),
              const SizedBox(width: 8),
              _MiniContador(
                  label: 'Enviados',
                  count: enviados,
                  color: Colors.greenAccent),
              const SizedBox(width: 8),
              _MiniContador(
                  label: 'Con error',
                  count: errores,
                  color: Colors.redAccent),
            ],
          ),
        );
      },
    );
  }
}

class _MiniContador extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _MiniContador({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// ITEM DE LA LISTA
// =============================================================================

class _ItemCola extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final VoidCallback onReintentar;
  final VoidCallback onEliminar;

  const _ItemCola({
    required this.doc,
    required this.onReintentar,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final estado = (data['estado'] ?? 'PENDIENTE').toString();
    final telefono = (data['telefono'] ?? '').toString();
    final mensaje = (data['mensaje'] ?? '').toString();
    final encoladoTs = data['encolado_en'];
    final enviadoTs = data['enviado_en'];
    final error = (data['error'] ?? '').toString();
    final intentos = (data['intentos'] ?? 0) as int;

    final esError = estado == 'ERROR';

    return AppCard(
      borderColor: _colorEstado(estado).withAlpha(esError ? 150 : 40),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _BadgeEstado(estado: estado),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  telefono,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (intentos > 1)
                Text(
                  '×$intentos',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            mensaje,
            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.schedule, size: 11, color: Colors.white38),
              const SizedBox(width: 4),
              Text(
                _formatTs(encoladoTs, prefijo: 'Encolado'),
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
              if (enviadoTs != null) ...[
                const SizedBox(width: 12),
                const Icon(Icons.check, size: 11, color: Colors.greenAccent),
                const SizedBox(width: 4),
                Text(
                  _formatTs(enviadoTs, prefijo: 'Enviado'),
                  style: const TextStyle(
                      color: Colors.greenAccent, fontSize: 10),
                ),
              ],
            ],
          ),
          if (esError && error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withAlpha(15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                error,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (esError || estado == 'PENDIENTE')
                TextButton.icon(
                  onPressed: onEliminar,
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.white54, size: 16),
                  label: const Text(
                    'Eliminar',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
              if (esError) ...[
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: onReintentar,
                  icon: const Icon(Icons.refresh,
                      color: Colors.greenAccent, size: 16),
                  label: const Text(
                    'Reintentar',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static Color _colorEstado(String estado) {
    switch (estado) {
      case 'PENDIENTE':
        return Colors.orangeAccent;
      case 'PROCESANDO':
        return Colors.blueAccent;
      case 'ENVIADO':
        return Colors.greenAccent;
      case 'ERROR':
        return Colors.redAccent;
      default:
        return Colors.white38;
    }
  }

  static String _formatTs(dynamic ts, {String prefijo = ''}) {
    if (ts is! Timestamp) return prefijo;
    final dt = ts.toDate().toLocal();
    final txt = DateFormat('dd/MM HH:mm').format(dt);
    return prefijo.isEmpty ? txt : '$prefijo $txt';
  }
}

class _BadgeEstado extends StatelessWidget {
  final String estado;
  const _BadgeEstado({required this.estado});

  @override
  Widget build(BuildContext context) {
    final color = _ItemCola._colorEstado(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        estado,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

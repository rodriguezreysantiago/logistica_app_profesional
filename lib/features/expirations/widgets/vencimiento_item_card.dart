import 'package:flutter/material.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/app_widgets.dart';
import 'vencimiento_item.dart';

/// Card de auditoría de un vencimiento.
///
/// Reusable entre las 3 pantallas de listas (choferes, chasis, acoplados).
/// Muestra:
/// - Thumbnail del archivo (PDF/imagen) — usando [AppFileThumbnail]
/// - Título (nombre del chofer o "TIPO - patente")
/// - Subtítulo: tipo de documento + fecha
/// - Badge de días restantes — usando [VencimientoBadge]
class VencimientoItemCard extends StatelessWidget {
  final VencimientoItem item;
  final VoidCallback onTap;

  const VencimientoItemCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      // Si está vencido o vence en menos de 14 días, destacamos la card.
      highlighted: item.dias <= 14,
      borderColor: item.dias < 0
          ? Colors.redAccent.withAlpha(120)
          : item.dias <= 14
              ? Colors.orangeAccent.withAlpha(120)
              : null,
      child: Row(
        children: [
          AppFileThumbnail(
            url: item.urlArchivo,
            tituloVisor: '${item.tipoDoc} - ${item.docId}',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.tipoDoc} · ${AppFormatters.formatearFecha(item.fecha)}',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          VencimientoBadge(fecha: item.fecha),
        ],
      ),
    );
  }
}

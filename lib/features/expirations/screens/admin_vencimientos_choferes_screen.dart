import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../widgets/vencimiento_editor_sheet.dart';
import '../widgets/vencimiento_item.dart';
import '../widgets/vencimiento_item_card.dart';

/// Auditoría de vencimientos del personal (60 días).
///
/// Recorre EMPLEADOS y arma una lista de vencimientos críticos
/// (≤ 60 días o ya vencidos), ordenada por urgencia.
class AdminVencimientosChoferesScreen extends StatefulWidget {
  const AdminVencimientosChoferesScreen({super.key});

  @override
  State<AdminVencimientosChoferesScreen> createState() =>
      _AdminVencimientosChoferesScreenState();
}

class _AdminVencimientosChoferesScreenState
    extends State<AdminVencimientosChoferesScreen> {
  late final Stream<QuerySnapshot> _empleadosStream;

  /// Documentos a auditar (etiqueta visible → sufijo del campo Firestore).
  static const Map<String, String> _documentosAuditados = {
    'Licencia de Conducir': 'LICENCIA_DE_CONDUCIR',
    'Preocupacional': 'PREOCUPACIONAL',
    'Manejo Defensivo': 'CURSO_DE_MANEJO_DEFENSIVO',
    'ART': 'ART',
    'F. 931': '931',
    'Seguro de Vida': 'SEGURO_DE_VIDA',
    'Sindicato': 'LIBRE_DE_DEUDA_SINDICAL',
  };

  @override
  void initState() {
    super.initState();
    _empleadosStream =
        FirebaseFirestore.instance.collection('EMPLEADOS').snapshots();
  }

  /// Construye la lista de items de vencimiento desde el snapshot.
  List<VencimientoItem> _construirItems(QuerySnapshot snapshot) {
    final items = <VencimientoItem>[];
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final nombre = (data['NOMBRE'] ?? 'Sin nombre').toString();
      final dni = doc.id.trim();

      _documentosAuditados.forEach((etiqueta, campoBase) {
        final fecha = data['VENCIMIENTO_$campoBase']?.toString();
        if (fecha == null || fecha.isEmpty) return;
        final dias = AppFormatters.calcularDiasRestantes(fecha);
        items.add(VencimientoItem(
          docId: dni,
          coleccion: 'EMPLEADOS',
          titulo: nombre,
          tipoDoc: etiqueta,
          campoBase: campoBase,
          fecha: fecha,
          dias: dias,
          urlArchivo: data['ARCHIVO_$campoBase']?.toString(),
          storagePath: 'EMPLEADOS_DOCS',
        ));
      });
    }

    // Filtrar críticos (≤ 60 días) y ordenar por urgencia
    final criticos =
        items.where((it) => it.dias <= 60).toList()
          ..sort((a, b) => a.dias.compareTo(b.dias));
    return criticos;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Auditoría: Personal',
      body: StreamBuilder<QuerySnapshot>(
        stream: _empleadosStream,
        builder: (ctx, snap) {
          if (snap.hasError) {
            return AppErrorState(subtitle: snap.error.toString());
          }
          if (!snap.hasData) return const AppLoadingState();

          final items = _construirItems(snap.data!);

          if (items.isEmpty) {
            return const AppEmptyState(
              icon: Icons.check_circle_outline,
              title: 'Personal con documentación al día',
              subtitle: 'No hay vencimientos críticos en los próximos 60 días.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
            itemCount: items.length,
            itemBuilder: (ctx, idx) => VencimientoItemCard(
              item: items[idx],
              onTap: () =>
                  VencimientoEditorSheet.show(context, items[idx]),
            ),
          );
        },
      ),
    );
  }
}

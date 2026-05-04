import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/vencimientos_config.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../widgets/vencimiento_editor_sheet.dart';
import '../widgets/vencimiento_item.dart';
import '../widgets/vencimiento_item_card.dart';

/// Auditoría de vencimientos de tractores/chasis.
class AdminVencimientosChasisScreen extends StatefulWidget {
  const AdminVencimientosChasisScreen({super.key});

  @override
  State<AdminVencimientosChasisScreen> createState() =>
      _AdminVencimientosChasisScreenState();
}

class _AdminVencimientosChasisScreenState
    extends State<AdminVencimientosChasisScreen> {
  late final Stream<QuerySnapshot> _vehiculosStream;

  static const _tiposIncluidos = ['CHASIS', 'TRACTOR'];

  @override
  void initState() {
    super.initState();
    // where('TIPO', 'in', ...) filtra server-side: bajamos solo los
    // tractores/chasis en lugar de toda la flota. Con flota chica
    // ahorra ~50% de docs (mitad enganches mitad tractores); con flota
    // grande el ahorro escala lineal.
    _vehiculosStream = FirebaseFirestore.instance
        .collection(AppCollections.vehiculos)
        .where('TIPO', whereIn: _tiposIncluidos)
        .snapshots();
  }

  List<VencimientoItem> _construirItems(QuerySnapshot snapshot) {
    final items = <VencimientoItem>[];
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      // Soft-delete: vehiculos dados de baja no se auditan.
      if (!AppActivo.esActivo(data)) continue;
      final tipo = (data['TIPO'] ?? '').toString().toUpperCase();
      // Defensivo: el where ya filtra server-side, pero si algun doc
      // tiene TIPO null o casing distinto, igual lo skipeamos aca.
      if (!_tiposIncluidos.contains(tipo)) continue;

      final patente = doc.id.toUpperCase();
      // Iteramos los vencimientos definidos para tractor en
      // AppVencimientos. Cuando sumes uno nuevo a esa lista, esta
      // auditoría lo audita automáticamente.
      for (final spec in AppVencimientos.tractor) {
        final fecha = data[spec.campoFecha]?.toString();
        if (fecha == null || fecha.isEmpty) continue;
        // VencimientoItem espera el "campoBase" sin prefijo, p.ej. 'RTO'
        // o 'EXTINTOR_CABINA'. Lo derivamos del campoFecha.
        final campoBase = spec.campoFecha.replaceFirst('VENCIMIENTO_', '');
        final dias = AppFormatters.calcularDiasRestantes(fecha);
        items.add(VencimientoItem(
          docId: patente,
          coleccion: 'VEHICULOS',
          titulo: '$tipo - $patente',
          tipoDoc: spec.etiqueta,
          campoBase: campoBase,
          fecha: fecha,
          dias: dias,
          urlArchivo: data[spec.campoArchivo]?.toString(),
          storagePath: 'VEHICULOS_DOCS',
        ));
      }
    }

    // Inválidas (dias == null) primero: son datos corruptos a arreglar.
    final criticos = items
        .where((it) => it.dias == null || it.dias! <= 60)
        .toList()
      ..sort((a, b) {
        if (a.dias == null && b.dias == null) return 0;
        if (a.dias == null) return -1;
        if (b.dias == null) return 1;
        return a.dias!.compareTo(b.dias!);
      });
    return criticos;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Auditoría: Tractores',
      body: StreamBuilder<QuerySnapshot>(
        stream: _vehiculosStream,
        builder: (ctx, snap) {
          if (snap.hasError) {
            return AppErrorState(subtitle: snap.error.toString());
          }
          if (!snap.hasData) return const AppLoadingState();

          final items = _construirItems(snap.data!);

          if (items.isEmpty) {
            return const AppEmptyState(
              icon: Icons.check_circle_outline,
              title: 'Sin vencimientos próximos en tractores',
              subtitle:
                  'Los chasis y tractores tienen documentación al día.',
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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/vencimientos_config.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../providers/vehiculo_provider.dart';

import 'admin_vehiculo_alta_screen.dart';
import 'admin_vehiculo_form_screen.dart';

// 13 widgets visuales (cards, sheet de detalle, telemetría, badges,
// rows) extraídos para mantener navegable el screen principal.
// Comparten privacidad y los imports via `part of`.
part 'admin_vehiculos_lista_widgets.dart';

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

  /// Tabs que mostramos: tractor primero (la unidad que tracciona) y
  /// después los enganches. Filtramos `ACOPLADO` porque solo existe por
  /// retrocompatibilidad con docs viejos y no queremos un tab vacío.
  static List<String> get _tipos => [
        AppTiposVehiculo.tractor,
        ...AppTiposVehiculo.enganches.where((t) => t != 'ACOPLADO'),
      ];

  @override
  Widget build(BuildContext context) {
    final tipos = _tipos;
    return DefaultTabController(
      length: tipos.length,
      child: AppScaffold(
        title: 'Gestión de Flota',
        // isScrollable: con 5 tabs no entran cómodos en una sola fila;
        // esto los hace deslizables horizontalmente.
        bottom: TabBar(
          isScrollable: true,
          tabs: [
            for (final t in tipos)
              Tab(text: AppTiposVehiculo.pluralEtiquetas[t] ?? t),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminVehiculoAltaScreen(),
            ),
          ),
          tooltip: 'Agregar nueva unidad',
          icon: const Icon(Icons.add),
          label: const Text('NUEVO'),
        ),
        body: TabBarView(
          children: [
            for (final t in tipos) _ListaPorTipo(tipo: t),
          ],
        ),
      ),
    );
  }
}


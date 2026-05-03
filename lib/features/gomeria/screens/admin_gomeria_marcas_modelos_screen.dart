import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/constants/app_colors.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../constants/posiciones.dart';
import '../models/cubierta_marca.dart';
import '../models/cubierta_modelo.dart';

/// ABM de marcas y modelos de cubiertas. 2 tabs:
/// - **Marcas**: solo nombre + activo (soft-delete).
/// - **Modelos**: marca + modelo + medida + tipo_uso + km_vida_estimada
///   (nueva y recapada) + recapable + activo.
///
/// Acceso: ADMIN (las reglas Firestore CUBIERTAS_MARCAS / CUBIERTAS_MODELOS
/// requieren `isAdmin()` para escritura — el supervisor solo lee).
class AdminGomeriaMarcasModelosScreen extends StatelessWidget {
  const AdminGomeriaMarcasModelosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: AppScaffold(
        title: 'Marcas y Modelos',
        bottom: TabBar(
          tabs: [
            Tab(text: 'MARCAS'),
            Tab(text: 'MODELOS'),
          ],
          indicatorColor: AppColors.accentPurple,
        ),
        body: TabBarView(
          children: [
            _MarcasTab(),
            _ModelosTab(),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// MARCAS
// =============================================================================

class _MarcasTab extends StatelessWidget {
  const _MarcasTab();

  @override
  Widget build(BuildContext context) {
    final col =
        FirebaseFirestore.instance.collection(AppCollections.cubiertasMarcas);
    return Stack(
      children: [
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: col.orderBy('nombre').snapshots(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final marcas = (snap.data?.docs ?? const [])
                .map(CubiertaMarca.fromDoc)
                .toList();
            if (marcas.isEmpty) {
              return const _Vacio(
                texto: 'No hay marcas cargadas. Tocá + para agregar la primera.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
              itemCount: marcas.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final m = marcas[i];
                return AppCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.label_outline,
                        color: m.activo ? AppColors.accentPurple : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          m.nombre,
                          style: TextStyle(
                            color: m.activo ? Colors.white : Colors.grey,
                            fontSize: 15,
                            decoration: m.activo
                                ? TextDecoration.none
                                : TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                      Switch(
                        value: m.activo,
                        onChanged: (v) => col.doc(m.id).update({'activo': v}),
                        activeTrackColor: AppColors.accentPurple,
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'fab_marca',
            backgroundColor: AppColors.accentPurple,
            onPressed: () => _abrirAltaMarca(context),
            icon: const Icon(Icons.add),
            label: const Text('NUEVA MARCA'),
          ),
        ),
      ],
    );
  }

  Future<void> _abrirAltaMarca(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        title: const Text('Nueva marca'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nombre de la marca',
            hintText: 'Ej. Bridgestone',
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCELAR')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('GUARDAR'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || !context.mounted) return;
    await FirebaseFirestore.instance
        .collection(AppCollections.cubiertasMarcas)
        .add({'nombre': result, 'activo': true});
  }
}

// =============================================================================
// MODELOS
// =============================================================================

class _ModelosTab extends StatelessWidget {
  const _ModelosTab();

  @override
  Widget build(BuildContext context) {
    final colModelos =
        FirebaseFirestore.instance.collection(AppCollections.cubiertasModelos);
    return Stack(
      children: [
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: colModelos.orderBy('marca_nombre').snapshots(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final modelos = (snap.data?.docs ?? const [])
                .map(CubiertaModelo.fromDoc)
                .toList();
            if (modelos.isEmpty) {
              return const _Vacio(
                texto:
                    'No hay modelos cargados. Cargá las marcas y después agregá los modelos.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
              itemCount: modelos.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final m = modelos[i];
                return AppCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.tire_repair,
                            color: m.activo
                                ? AppColors.accentPurple
                                : Colors.grey,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              m.etiqueta,
                              style: TextStyle(
                                color: m.activo ? Colors.white : Colors.grey,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Switch(
                            value: m.activo,
                            onChanged: (v) =>
                                colModelos.doc(m.id).update({'activo': v}),
                            activeTrackColor: AppColors.accentPurple,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          _Chip(
                            'Vida nueva: ${_kmStr(m.kmVidaEstimadaNueva)}',
                          ),
                          _Chip(
                            'Recapada: ${_kmStr(m.kmVidaEstimadaRecapada)}',
                          ),
                          _Chip(
                            m.recapable ? 'Recapable' : 'No recapable',
                            color: m.recapable
                                ? AppColors.accentTeal
                                : Colors.grey,
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'fab_modelo',
            backgroundColor: AppColors.accentPurple,
            onPressed: () => _abrirAltaModelo(context),
            icon: const Icon(Icons.add),
            label: const Text('NUEVO MODELO'),
          ),
        ),
      ],
    );
  }

  String _kmStr(int? km) {
    if (km == null) return '—';
    return '${(km / 1000).toStringAsFixed(0)}k km';
  }

  Future<void> _abrirAltaModelo(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (ctx) => const _AltaModeloDialog(),
    );
  }
}

class _AltaModeloDialog extends StatefulWidget {
  const _AltaModeloDialog();

  @override
  State<_AltaModeloDialog> createState() => _AltaModeloDialogState();
}

class _AltaModeloDialogState extends State<_AltaModeloDialog> {
  final _modeloCtrl = TextEditingController();
  final _medidaCtrl = TextEditingController();
  final _kmNuevaCtrl = TextEditingController();
  final _kmRecapadaCtrl = TextEditingController();

  CubiertaMarca? _marcaSeleccionada;
  TipoUsoCubierta _tipoUso = TipoUsoCubierta.traccion;
  bool _recapable = true;
  bool _guardando = false;

  @override
  void dispose() {
    _modeloCtrl.dispose();
    _medidaCtrl.dispose();
    _kmNuevaCtrl.dispose();
    _kmRecapadaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: const Text('Nuevo modelo'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Marca (dropdown desde Firestore).
            // NOTA: filtramos `activo` + ordenamos client-side a
            // propósito. La combinación `where('activo') + orderBy('nombre')`
            // exigiría un índice compuesto en Firestore — sin él la query
            // falla silenciosa y el dropdown queda vacío. Como hay
            // típicamente < 50 marcas, el costo es nulo.
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection(AppCollections.cubiertasMarcas)
                  .snapshots(),
              builder: (ctx, snap) {
                final marcas = (snap.data?.docs ?? const [])
                    .map(CubiertaMarca.fromDoc)
                    .where((m) => m.activo)
                    .toList()
                  ..sort((a, b) => a.nombre.compareTo(b.nombre));
                if (marcas.isEmpty) {
                  return const Text(
                    'Cargá primero al menos una marca activa.',
                    style: TextStyle(color: Colors.amber),
                  );
                }
                return DropdownButtonFormField<CubiertaMarca>(
                  initialValue: _marcaSeleccionada,
                  decoration: const InputDecoration(labelText: 'Marca'),
                  items: marcas
                      .map((m) => DropdownMenuItem(
                            value: m,
                            child: Text(m.nombre),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _marcaSeleccionada = v),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modeloCtrl,
              decoration: const InputDecoration(
                labelText: 'Modelo',
                hintText: 'Ej. R268, M788',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _medidaCtrl,
              decoration: const InputDecoration(
                labelText: 'Medida',
                hintText: 'Ej. 295/80R22.5',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<TipoUsoCubierta>(
              initialValue: _tipoUso,
              decoration: const InputDecoration(labelText: 'Tipo de uso'),
              items: TipoUsoCubierta.values
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(t.etiqueta),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _tipoUso = v ?? _tipoUso),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _kmNuevaCtrl,
              decoration: const InputDecoration(
                labelText: 'Vida estimada (nueva), km',
                hintText: 'Ej. 120000',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _kmRecapadaCtrl,
              decoration: const InputDecoration(
                labelText: 'Vida estimada (recapada), km',
                hintText: 'Ej. 60000 (vacío si no recapa)',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _recapable,
              title: const Text('Recapable'),
              subtitle: const Text(
                'Si está apagado, no se va a poder mandar a recapar.',
                style: TextStyle(fontSize: 11, color: Colors.white60),
              ),
              onChanged: (v) => setState(() => _recapable = v),
              activeTrackColor: AppColors.accentPurple,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        ElevatedButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator())
              : const Text('GUARDAR'),
        ),
      ],
    );
  }

  Future<void> _guardar() async {
    final marca = _marcaSeleccionada;
    final modelo = _modeloCtrl.text.trim();
    final medida = _medidaCtrl.text.trim();
    if (marca == null || modelo.isEmpty || medida.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Marca, modelo y medida son obligatorios.'),
      ));
      return;
    }
    setState(() => _guardando = true);
    final nuevo = CubiertaModelo(
      id: '',
      marcaId: marca.id,
      marcaNombre: marca.nombre,
      modelo: modelo,
      medida: medida,
      tipoUso: _tipoUso,
      kmVidaEstimadaNueva: int.tryParse(_kmNuevaCtrl.text.trim()),
      kmVidaEstimadaRecapada: int.tryParse(_kmRecapadaCtrl.text.trim()),
      recapable: _recapable,
      activo: true,
    );
    try {
      await FirebaseFirestore.instance
          .collection(AppCollections.cubiertasModelos)
          .add(nuevo.toMap());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _guardando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error guardando: $e')));
      }
    }
  }
}

// =============================================================================
// HELPERS
// =============================================================================

class _Vacio extends StatelessWidget {
  final String texto;
  const _Vacio({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Text(
          texto,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, fontSize: 14),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String texto;
  final Color? color;
  const _Chip(this.texto, {this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.accentBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c, width: 1),
      ),
      child: Text(
        texto,
        style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

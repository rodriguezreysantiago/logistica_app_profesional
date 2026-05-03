import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/prefs_service.dart';
import '../../../shared/constants/app_colors.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../constants/posiciones.dart';
import '../models/cubierta.dart';
import '../models/cubierta_modelo.dart';
import '../services/gomeria_service.dart';

/// Stock de cubiertas — lista de las que están EN_DEPOSITO + alta de
/// nuevas. Filtros simples por tipo_uso (Dirección / Tracción) para el
/// caso típico "necesito una cubierta de dirección, ¿qué tengo?".
class GomeriaStockScreen extends StatefulWidget {
  const GomeriaStockScreen({super.key});

  @override
  State<GomeriaStockScreen> createState() => _GomeriaStockScreenState();
}

class _GomeriaStockScreenState extends State<GomeriaStockScreen> {
  final _service = GomeriaService();
  TipoUsoCubierta? _filtro;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Stock de cubiertas',
      body: Column(
        children: [
          _Filtros(
            seleccionado: _filtro,
            onChanged: (v) => setState(() => _filtro = v),
          ),
          Expanded(
            child: StreamBuilder<List<Cubierta>>(
              stream: _service.streamCubiertasEnDeposito(tipoUso: _filtro),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final cubiertas = snap.data ?? const <Cubierta>[];
                if (cubiertas.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Text(
                        'No hay cubiertas en depósito.\nTocá + para agregar la primera.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: Colors.white60, fontSize: 14),
                      ),
                    ),
                  );
                }
                // Ordenamos client-side por código (CUB-XXXX). Para listas
                // grandes habría que indexar y orderBy server-side, pero
                // < 200 cubiertas es trivial.
                cubiertas.sort((a, b) => a.codigo.compareTo(b.codigo));
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                  itemCount: cubiertas.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _CubiertaTile(c: cubiertas[i]),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accentBlue,
        onPressed: () => _abrirAlta(context),
        icon: const Icon(Icons.add),
        label: const Text('NUEVA CUBIERTA'),
      ),
    );
  }

  Future<void> _abrirAlta(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (ctx) => _AltaCubiertaDialog(service: _service),
    );
  }
}

// =============================================================================

class _Filtros extends StatelessWidget {
  final TipoUsoCubierta? seleccionado;
  final ValueChanged<TipoUsoCubierta?> onChanged;

  const _Filtros({required this.seleccionado, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Wrap(
        spacing: 8,
        children: [
          _ChipFiltro(
            label: 'TODAS',
            seleccionado: seleccionado == null,
            onTap: () => onChanged(null),
          ),
          for (final t in TipoUsoCubierta.values)
            _ChipFiltro(
              label: t.etiqueta.toUpperCase(),
              seleccionado: seleccionado == t,
              onTap: () => onChanged(t),
            ),
        ],
      ),
    );
  }
}

class _ChipFiltro extends StatelessWidget {
  final String label;
  final bool seleccionado;
  final VoidCallback onTap;

  const _ChipFiltro({
    required this.label,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: seleccionado,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.accentBlue,
      labelStyle: TextStyle(
        color: seleccionado ? Colors.black : Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 11,
      ),
      backgroundColor: AppColors.background,
    );
  }
}

class _CubiertaTile extends StatelessWidget {
  final Cubierta c;
  const _CubiertaTile({required this.c});

  @override
  Widget build(BuildContext context) {
    final color = c.tipoUso == TipoUsoCubierta.direccion
        ? AppColors.accentOrange
        : AppColors.accentBlue;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.tire_repair, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.codigo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  c.modeloEtiqueta,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    Text(
                      c.vidas == 1 ? 'Nueva' : '${c.vidas - 1}× recapada',
                      style: TextStyle(color: color, fontSize: 11),
                    ),
                    if (c.kmAcumulados > 0)
                      Text(
                        '${(c.kmAcumulados / 1000).toStringAsFixed(0)}k km totales',
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 11),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ALTA
// =============================================================================

class _AltaCubiertaDialog extends StatefulWidget {
  final GomeriaService service;
  const _AltaCubiertaDialog({required this.service});

  @override
  State<_AltaCubiertaDialog> createState() => _AltaCubiertaDialogState();
}

class _AltaCubiertaDialogState extends State<_AltaCubiertaDialog> {
  CubiertaModelo? _modeloSel;
  final _obsCtrl = TextEditingController();
  bool _guardando = false;

  @override
  void dispose() {
    _obsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: const Text('Nueva cubierta'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Filtramos `activo` + ordenamos client-side para evitar
              // exigir un índice compuesto en Firestore (where + orderBy
              // en campos distintos). Hay < 100 modelos típicamente.
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection(AppCollections.cubiertasModelos)
                    .snapshots(),
                builder: (ctx, snap) {
                  final modelos = (snap.data?.docs ?? const [])
                      .map(CubiertaModelo.fromDoc)
                      .where((m) => m.activo)
                      .toList()
                    ..sort((a, b) =>
                        a.marcaNombre.compareTo(b.marcaNombre));
                  if (modelos.isEmpty) {
                    return const Text(
                      'No hay modelos cargados.\n'
                      'Cargá los modelos antes (Marcas y Modelos → Modelos).',
                      style: TextStyle(color: Colors.amber),
                    );
                  }
                  return DropdownButtonFormField<CubiertaModelo>(
                    initialValue: _modeloSel,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Modelo'),
                    items: modelos
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(
                                m.etiqueta,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _modeloSel = v),
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _obsCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Observaciones (opcional)',
                  hintText: 'Ej. Comprada en oferta de mayo 2026',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'El código (CUB-XXXX) se asigna automáticamente.',
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
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
    final modelo = _modeloSel;
    if (modelo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná un modelo.')),
      );
      return;
    }
    setState(() => _guardando = true);
    try {
      await widget.service.crearCubierta(
        modeloId: modelo.id,
        supervisorDni: PrefsService.dni,
        supervisorNombre: PrefsService.nombre,
        observaciones: _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _guardando = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

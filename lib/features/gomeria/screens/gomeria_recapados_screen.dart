import 'package:flutter/material.dart';

import '../../../core/services/prefs_service.dart';
import '../../../shared/constants/app_colors.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../constants/posiciones.dart';
import '../models/cubierta.dart';
import '../models/cubierta_recapado.dart';
import '../services/gomeria_service.dart';

/// Pantalla de recapados — muestra los envíos en proceso (cubiertas
/// que están en el proveedor) y permite cerrarlos al recibir. Para
/// mandar una NUEVA cubierta a recapar, se usa el FAB que abre un
/// dialog que selecciona del stock.
class GomeriaRecapadosScreen extends StatefulWidget {
  const GomeriaRecapadosScreen({super.key});

  @override
  State<GomeriaRecapadosScreen> createState() =>
      _GomeriaRecapadosScreenState();
}

class _GomeriaRecapadosScreenState extends State<GomeriaRecapadosScreen> {
  final _service = GomeriaService();

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Recapados',
      body: StreamBuilder<List<CubiertaRecapado>>(
        stream: _service.streamRecapadosEnProceso(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final recapados = snap.data ?? const <CubiertaRecapado>[];
          if (recapados.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text(
                  'No hay recapados en proceso.\nTocá + para mandar una cubierta a recapar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60, fontSize: 14),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
            itemCount: recapados.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _RecapadoTile(
              r: recapados[i],
              onCerrar: () => _abrirCierre(context, recapados[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accentTeal,
        onPressed: () => _abrirEnvio(context),
        icon: const Icon(Icons.send_outlined),
        label: const Text('MANDAR A RECAPAR'),
      ),
    );
  }

  Future<void> _abrirEnvio(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (ctx) => _EnviarRecapadoDialog(service: _service),
    );
  }

  Future<void> _abrirCierre(
      BuildContext context, CubiertaRecapado r) async {
    await showDialog(
      context: context,
      builder: (ctx) => _CerrarRecapadoDialog(recapado: r, service: _service),
    );
  }
}

// =============================================================================
// TILE
// =============================================================================

class _RecapadoTile extends StatelessWidget {
  final CubiertaRecapado r;
  final VoidCallback onCerrar;
  const _RecapadoTile({required this.r, required this.onCerrar});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onCerrar,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz_outlined,
                  color: AppColors.accentTeal),
              const SizedBox(width: 8),
              Text(
                r.cubiertaCodigo,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentTeal.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.accentTeal),
                ),
                child: Text(
                  '${r.diasEnRecapado()}d',
                  style: const TextStyle(
                    color: AppColors.accentTeal,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Proveedor: ${r.proveedor}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            'Para vida ${r.vidaRecapado}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (r.notas != null && r.notas!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              r.notas!,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 6),
          const Text(
            'Tocá para cerrar el recapado al recibir.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// DIALOG ENVIO
// =============================================================================

class _EnviarRecapadoDialog extends StatefulWidget {
  final GomeriaService service;
  const _EnviarRecapadoDialog({required this.service});

  @override
  State<_EnviarRecapadoDialog> createState() => _EnviarRecapadoDialogState();
}

class _EnviarRecapadoDialogState extends State<_EnviarRecapadoDialog> {
  Cubierta? _cubiertaSel;
  final _proveedorCtrl = TextEditingController();
  final _notasCtrl = TextEditingController();
  bool _guardando = false;

  @override
  void dispose() {
    _proveedorCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: const Text('Mandar a recapar'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StreamBuilder<List<Cubierta>>(
                stream: widget.service.streamCubiertasEnDeposito(),
                builder: (ctx, snap) {
                  final todas = snap.data ?? const <Cubierta>[];
                  // Solo permitimos mandar cubiertas que `puedeRecaparse`
                  // (estado válido). El service además valida que el modelo
                  // sea recapable — ahí va a fallar si se elige una que no.
                  final candidatas =
                      todas.where((c) => c.puedeRecaparse).toList()
                        ..sort((a, b) => a.codigo.compareTo(b.codigo));
                  if (candidatas.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'No hay cubiertas en depósito para recapar.',
                        style: TextStyle(color: Colors.amber),
                      ),
                    );
                  }
                  return DropdownButtonFormField<Cubierta>(
                    initialValue: _cubiertaSel,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Cubierta'),
                    items: candidatas
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(
                                '${c.codigo} · ${c.modeloEtiqueta} '
                                '(vida ${c.vidas})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _cubiertaSel = v),
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _proveedorCtrl,
                decoration: const InputDecoration(
                  labelText: 'Proveedor',
                  hintText: 'Ej. Recauchutados Sur',
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notasCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notas (opcional)',
                ),
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
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentTeal),
          child: _guardando
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator())
              : const Text('ENVIAR'),
        ),
      ],
    );
  }

  Future<void> _guardar() async {
    final c = _cubiertaSel;
    final proveedor = _proveedorCtrl.text.trim();
    if (c == null || proveedor.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cubierta y proveedor son obligatorios.')),
      );
      return;
    }
    setState(() => _guardando = true);
    try {
      await widget.service.mandarARecapar(
        cubiertaId: c.id,
        proveedor: proveedor,
        supervisorDni: PrefsService.dni,
        supervisorNombre: PrefsService.nombre,
        notas: _notasCtrl.text.trim().isEmpty ? null : _notasCtrl.text,
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

// =============================================================================
// DIALOG CIERRE
// =============================================================================

class _CerrarRecapadoDialog extends StatefulWidget {
  final CubiertaRecapado recapado;
  final GomeriaService service;
  const _CerrarRecapadoDialog({
    required this.recapado,
    required this.service,
  });

  @override
  State<_CerrarRecapadoDialog> createState() => _CerrarRecapadoDialogState();
}

class _CerrarRecapadoDialogState extends State<_CerrarRecapadoDialog> {
  ResultadoRecapado _resultado = ResultadoRecapado.recibida;
  final _costoCtrl = TextEditingController();
  final _notasCtrl = TextEditingController();
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _notasCtrl.text = widget.recapado.notas ?? '';
  }

  @override
  void dispose() {
    _costoCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: Text('Cerrar recapado ${widget.recapado.cubiertaCodigo}'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Resultado:',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              // RadioGroup ancestor (Flutter 3.32+) — reemplazo del par
              // groupValue/onChanged que se deprecó. Centraliza el value
              // en el ancestor; los RadioListTile solo declaran su `value`.
              RadioGroup<ResultadoRecapado>(
                groupValue: _resultado,
                onChanged: (v) => setState(() => _resultado = v!),
                child: const Column(
                  children: [
                    RadioListTile<ResultadoRecapado>(
                      value: ResultadoRecapado.recibida,
                      title: Text('Recibida (vuelve al depósito)'),
                      activeColor: AppColors.accentGreen,
                    ),
                    RadioListTile<ResultadoRecapado>(
                      value: ResultadoRecapado.descartadaPorProveedor,
                      title:
                          Text('Descartada por el proveedor (estructura dañada)'),
                      activeColor: AppColors.accentRed,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _costoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Costo (\$, opcional)',
                  hintText: 'Ej. 45.000',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [AppFormatters.inputMiles],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notasCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notas (opcional)',
                ),
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
              : const Text('CERRAR'),
        ),
      ],
    );
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      await widget.service.recibirDeRecapado(
        recapadoId: widget.recapado.id,
        resultado: _resultado,
        supervisorDni: PrefsService.dni,
        supervisorNombre: PrefsService.nombre,
        // El usuario tipea con `.` de miles (formato AR). El parser
        // los descarta antes de convertir a int → double.
        costo: AppFormatters.parsearMiles(_costoCtrl.text)?.toDouble(),
        notas: _notasCtrl.text.trim().isEmpty ? null : _notasCtrl.text,
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

import 'package:flutter/material.dart';

import '../../../core/services/prefs_service.dart';
import '../../../shared/constants/app_colors.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../constants/posiciones.dart';
import '../models/cubierta.dart';
import '../models/cubierta_instalada.dart';
import '../services/gomeria_service.dart';

/// Pantalla detalle de una unidad — el corazón del flujo del operador
/// de gomería. Muestra el layout de posiciones de la unidad (10 para
/// tractor, 12 para enganche) agrupado por eje. Cada posición se
/// renderiza como un tile que indica si está ocupada (con qué cubierta)
/// o vacía. Tap en posición → dialog de acciones contextual.
///
/// El layout es texto/tile (no CustomPainter visual). Próximo iteración
/// puede reemplazar con un dibujo desde arriba del tractor (Santiago
/// adjuntó imagen como referencia) — por ahora prioriza función sobre
/// estética.
class GomeriaUnidadDetalleScreen extends StatefulWidget {
  final String unidadId;
  final TipoUnidadCubierta unidadTipo;
  final String tipoVehiculo;
  final String modelo;

  const GomeriaUnidadDetalleScreen({
    super.key,
    required this.unidadId,
    required this.unidadTipo,
    required this.tipoVehiculo,
    required this.modelo,
  });

  @override
  State<GomeriaUnidadDetalleScreen> createState() =>
      _GomeriaUnidadDetalleScreenState();
}

class _GomeriaUnidadDetalleScreenState
    extends State<GomeriaUnidadDetalleScreen> {
  final _service = GomeriaService();

  @override
  Widget build(BuildContext context) {
    final posiciones = posicionesParaUnidad(widget.unidadTipo);
    // Agrupamos por eje para renderizar fila por fila (más cercano al
    // layout físico desde arriba: eje 1 al frente, eje 3 al fondo).
    final porEje = <int, List<PosicionCubierta>>{};
    for (final p in posiciones) {
      porEje.putIfAbsent(p.eje, () => []).add(p);
    }
    final ejesOrdenados = porEje.keys.toList()..sort();

    return AppScaffold(
      title: widget.unidadId,
      body: StreamBuilder<List<CubiertaInstalada>>(
        stream:
            _service.streamInstalacionesActivasPorUnidad(widget.unidadId),
        builder: (ctx, snap) {
          final activas = snap.data ?? const <CubiertaInstalada>[];
          // Mapeo posicion_codigo → CubiertaInstalada activa.
          final mapa = <String, CubiertaInstalada>{};
          for (final i in activas) {
            mapa[i.posicion] = i;
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Cabecera(
                  unidadId: widget.unidadId,
                  unidadTipo: widget.unidadTipo,
                  tipoVehiculo: widget.tipoVehiculo,
                  modelo: widget.modelo,
                  cantInstaladas: activas.length,
                  cantPosiciones: posiciones.length,
                ),
                const SizedBox(height: 16),
                for (final eje in ejesOrdenados) ...[
                  _EjeHeader(
                      eje: eje, posiciones: porEje[eje]!),
                  const SizedBox(height: 8),
                  _GridEje(
                    posiciones: porEje[eje]!,
                    instaladas: mapa,
                    onTap: (p) =>
                        _onTapPosicion(context, p, mapa[p.codigo]),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _onTapPosicion(
    BuildContext context,
    PosicionCubierta posicion,
    CubiertaInstalada? actual,
  ) async {
    if (actual == null) {
      // Vacía → diálogo de instalación.
      await showDialog(
        context: context,
        builder: (ctx) => _InstalarCubiertaDialog(
          unidadId: widget.unidadId,
          unidadTipo: widget.unidadTipo,
          posicion: posicion,
          service: _service,
        ),
      );
    } else {
      // Ocupada → diálogo de acciones (retirar / descartar).
      await showDialog(
        context: context,
        builder: (ctx) => _PosicionOcupadaDialog(
          posicion: posicion,
          instalada: actual,
          service: _service,
        ),
      );
    }
  }
}

// =============================================================================
// CABECERA
// =============================================================================

class _Cabecera extends StatelessWidget {
  final String unidadId;
  final TipoUnidadCubierta unidadTipo;
  final String tipoVehiculo;
  final String modelo;
  final int cantInstaladas;
  final int cantPosiciones;

  const _Cabecera({
    required this.unidadId,
    required this.unidadTipo,
    required this.tipoVehiculo,
    required this.modelo,
    required this.cantInstaladas,
    required this.cantPosiciones,
  });

  @override
  Widget build(BuildContext context) {
    final completo = cantInstaladas == cantPosiciones;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(
            unidadTipo == TipoUnidadCubierta.tractor
                ? Icons.local_shipping_outlined
                : Icons.rv_hookup_outlined,
            color: AppColors.accentOrange,
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unidadId,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '$tipoVehiculo${modelo.isNotEmpty ? " · $modelo" : ""}',
                  style:
                      const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (completo
                      ? AppColors.accentGreen
                      : AppColors.accentOrange)
                  .withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: completo
                    ? AppColors.accentGreen
                    : AppColors.accentOrange,
              ),
            ),
            child: Text(
              '$cantInstaladas / $cantPosiciones',
              style: TextStyle(
                color:
                    completo ? AppColors.accentGreen : AppColors.accentOrange,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EjeHeader extends StatelessWidget {
  final int eje;
  final List<PosicionCubierta> posiciones;
  const _EjeHeader({required this.eje, required this.posiciones});

  @override
  Widget build(BuildContext context) {
    final tipo = posiciones.first.tipoUsoRequerido;
    final etiquetaTipo = tipo == TipoUsoCubierta.direccion
        ? 'DIRECCIÓN'
        : 'TRACCIÓN';
    final color = tipo == TipoUsoCubierta.direccion
        ? AppColors.accentOrange
        : AppColors.accentBlue;
    return Row(
      children: [
        Text(
          'EJE $eje',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color, width: 0.5),
          ),
          child: Text(
            etiquetaTipo,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// GRID DE POSICIONES POR EJE
// =============================================================================

class _GridEje extends StatelessWidget {
  final List<PosicionCubierta> posiciones;
  final Map<String, CubiertaInstalada> instaladas;
  final ValueChanged<PosicionCubierta> onTap;

  const _GridEje({
    required this.posiciones,
    required this.instaladas,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final p in posiciones)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _PosicionTile(
                posicion: p,
                instalada: instaladas[p.codigo],
                onTap: () => onTap(p),
              ),
            ),
          ),
      ],
    );
  }
}

class _PosicionTile extends StatelessWidget {
  final PosicionCubierta posicion;
  final CubiertaInstalada? instalada;
  final VoidCallback onTap;

  const _PosicionTile({
    required this.posicion,
    required this.instalada,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ocupada = instalada != null;
    final color = ocupada
        ? AppColors.accentGreen
        : AppColors.accentOrange.withValues(alpha: 0.5);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: ocupada
              ? AppColors.accentGreen.withValues(alpha: 0.08)
              : Colors.transparent,
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ocupada ? Icons.tire_repair : Icons.add_circle_outline,
              color: color,
              size: 22,
            ),
            const SizedBox(height: 6),
            Text(
              posicion.lado,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ocupada ? Colors.white : Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (ocupada) ...[
              const SizedBox(height: 2),
              Text(
                instalada!.cubiertaCodigo,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// DIALOG INSTALAR
// =============================================================================

class _InstalarCubiertaDialog extends StatefulWidget {
  final String unidadId;
  final TipoUnidadCubierta unidadTipo;
  final PosicionCubierta posicion;
  final GomeriaService service;

  const _InstalarCubiertaDialog({
    required this.unidadId,
    required this.unidadTipo,
    required this.posicion,
    required this.service,
  });

  @override
  State<_InstalarCubiertaDialog> createState() =>
      _InstalarCubiertaDialogState();
}

class _InstalarCubiertaDialogState extends State<_InstalarCubiertaDialog> {
  Cubierta? _cubiertaSel;
  final _motivoCtrl = TextEditingController();
  bool _guardando = false;

  @override
  void dispose() {
    _motivoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: Text('Instalar en ${widget.posicion.etiqueta}'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Solo mostramos cubiertas EN_DEPOSITO con tipo_uso compatible
              // (la validación STRICT igual la hace el service, pero filtrar
              // acá evita opciones inválidas en la UI).
              StreamBuilder<List<Cubierta>>(
                stream: widget.service.streamCubiertasEnDeposito(
                    tipoUso: widget.posicion.tipoUsoRequerido),
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 60,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final cubiertas = snap.data ?? const <Cubierta>[];
                  if (cubiertas.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'No hay cubiertas '
                        '${widget.posicion.tipoUsoRequerido.etiqueta.toUpperCase()} '
                        'en depósito.',
                        style: const TextStyle(color: Colors.amber),
                      ),
                    );
                  }
                  cubiertas.sort((a, b) => a.codigo.compareTo(b.codigo));
                  return DropdownButtonFormField<Cubierta>(
                    initialValue: _cubiertaSel,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Cubierta'),
                    items: cubiertas
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(
                                '${c.codigo} · ${c.modeloEtiqueta}'
                                '${c.vidas > 1 ? " (${c.vidas - 1}× recapada)" : ""}',
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
                controller: _motivoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Motivo (opcional)',
                  hintText: 'Ej. rotación, reemplazo por pinchazo',
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
              backgroundColor: AppColors.accentGreen),
          child: _guardando
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator())
              : const Text('INSTALAR'),
        ),
      ],
    );
  }

  Future<void> _guardar() async {
    final c = _cubiertaSel;
    if (c == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná una cubierta.')),
      );
      return;
    }
    setState(() => _guardando = true);
    try {
      await widget.service.instalar(
        cubiertaId: c.id,
        unidadId: widget.unidadId,
        unidadTipo: widget.unidadTipo,
        posicionCodigo: widget.posicion.codigo,
        supervisorDni: PrefsService.dni,
        supervisorNombre: PrefsService.nombre,
        motivo: _motivoCtrl.text.trim().isEmpty ? null : _motivoCtrl.text,
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
// DIALOG POSICIÓN OCUPADA
// =============================================================================

class _PosicionOcupadaDialog extends StatefulWidget {
  final PosicionCubierta posicion;
  final CubiertaInstalada instalada;
  final GomeriaService service;

  const _PosicionOcupadaDialog({
    required this.posicion,
    required this.instalada,
    required this.service,
  });

  @override
  State<_PosicionOcupadaDialog> createState() =>
      _PosicionOcupadaDialogState();
}

class _PosicionOcupadaDialogState extends State<_PosicionOcupadaDialog> {
  final _motivoCtrl = TextEditingController();
  bool _operando = false;

  @override
  void dispose() {
    _motivoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.instalada;
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: Text(widget.posicion.etiqueta),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tire_repair, color: AppColors.accentGreen),
                const SizedBox(width: 8),
                Text(
                  i.cubiertaCodigo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Vida al instalar: ${i.vidaAlInstalar}',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text('Días instalada: ${i.diasDuracion()}',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            if (i.kmUnidadAlInstalar != null)
              Text(
                'Km del tractor al instalar: ${AppFormatters.formatearMiles(i.kmUnidadAlInstalar)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _motivoCtrl,
              decoration: const InputDecoration(
                labelText: 'Motivo del retiro (opcional)',
                hintText: 'Ej. rotación, pinchazo, desgaste',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _operando ? null : () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        OutlinedButton(
          onPressed:
              _operando ? null : () => _retirar(EstadoCubierta.descartada),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.accentRed,
            side: const BorderSide(color: AppColors.accentRed),
          ),
          child: const Text('DESCARTAR'),
        ),
        ElevatedButton(
          onPressed:
              _operando ? null : () => _retirar(EstadoCubierta.enDeposito),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentBlue),
          child: _operando
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator())
              : const Text('AL DEPÓSITO'),
        ),
      ],
    );
  }

  Future<void> _retirar(EstadoCubierta destino) async {
    setState(() => _operando = true);
    try {
      await widget.service.retirar(
        instalacionId: widget.instalada.id,
        supervisorDni: PrefsService.dni,
        supervisorNombre: PrefsService.nombre,
        motivo: _motivoCtrl.text.trim().isEmpty ? null : _motivoCtrl.text,
        destinoFinal: destino,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _operando = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../shared/widgets/app_widgets.dart';
import '../../vehicles/services/volvo_api_service.dart';
import '../services/report_checklist.dart';
import '../services/report_flota.dart';

/// Centro de Reportes (admin).
///
/// Lista los informes que el admin puede generar y exportar a Excel/PDF.
/// El reporte de Flota dispara una sincronización con Volvo Connect antes
/// de generar el archivo.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  bool _generando = false;

  // ---------------------------------------------------------------------------
  // ACCIONES
  // ---------------------------------------------------------------------------

  Future<void> _ejecutarReporteChecklist() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ReportChecklistService.mostrarOpcionesYGenerar(context);
    } catch (e) {
      if (mounted) _mostrarSnack(messenger, 'Error: $e', esError: true);
    }
  }

  Future<void> _ejecutarReporteFlota() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _generando = true);

    try {
      // 1) Bajamos los datos de Volvo (puede tardar varios segundos)
      final volvoService = VolvoApiService();
      final cacheVolvo = await volvoService.traerDatosFlota();

      if (!mounted) return;
      setState(() => _generando = false);

      // 2) Abrimos el diálogo de opciones de exportación
      await ReportGenerator.mostrarOpcionesYGenerar(context, cacheVolvo);
    } catch (e) {
      if (mounted) {
        setState(() => _generando = false);
        _mostrarSnack(
          messenger,
          'Error al conectar con Volvo: $e',
          esError: true,
        );
      }
    }
  }

  void _mostrarSnack(
    ScaffoldMessengerState messenger,
    String mensaje, {
    bool esError = false,
  }) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          mensaje,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: esError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AppScaffold(
          title: 'Centro de Reportes',
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 5, bottom: 14),
                child: Text(
                  'INFORMES ESTRATÉGICOS',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 2,
                  ),
                ),
              ),
              _ReportCard(
                titulo: 'Checklists Mensuales',
                descripcion:
                    'Reporte de novedades y roturas cargadas por choferes.',
                icono: Icons.fact_check_rounded,
                color: Colors.greenAccent,
                onTap: _generando ? null : _ejecutarReporteChecklist,
              ),
              const SizedBox(height: 12),
              _ReportCard(
                titulo: 'Estado de Flota (Volvo)',
                descripcion:
                    'Sincroniza consumo, KMs y posición con Volvo Connect.',
                icono: Icons.cloud_sync_rounded,
                color: Colors.blueAccent,
                onTap: _generando ? null : _ejecutarReporteFlota,
              ),
              const SizedBox(height: 12),
              const _ReportCard(
                titulo: 'Consumo de Combustible',
                descripcion:
                    'Análisis histórico de litros por unidad. (Próximamente)',
                icono: Icons.local_gas_station_rounded,
                color: Colors.white,
                isLocked: true,
                onTap: null,
              ),
            ],
          ),
        ),

        // Overlay de carga durante la sincronización con Volvo
        if (_generando) const _CargandoOverlay(),
      ],
    );
  }
}

// =============================================================================
// CARD DE UN REPORTE
// =============================================================================

class _ReportCard extends StatelessWidget {
  final String titulo;
  final String descripcion;
  final IconData icono;
  final Color color;
  final VoidCallback? onTap;
  final bool isLocked;

  const _ReportCard({
    required this.titulo,
    required this.descripcion,
    required this.icono,
    required this.color,
    required this.onTap,
    this.isLocked = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      margin: EdgeInsets.zero,
      borderColor: color.withAlpha(isLocked ? 15 : 50),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withAlpha(isLocked ? 10 : 30),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icono,
              color: isLocked ? Colors.white24 : color,
              size: 28,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    color: isLocked ? Colors.white38 : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  descripcion,
                  style: TextStyle(
                    color: isLocked ? Colors.white24 : Colors.white54,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            isLocked ? Icons.lock_outline : Icons.chevron_right_rounded,
            color: isLocked ? Colors.white12 : Colors.white38,
            size: 24,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// OVERLAY DE CARGA (cristal esmerilado durante sync con Volvo)
// =============================================================================

class _CargandoOverlay extends StatelessWidget {
  const _CargandoOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          color: Colors.black.withAlpha(150),
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blueAccent.withAlpha(50)),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.blueAccent),
                  SizedBox(height: 25),
                  Text(
                    'CONECTANDO CON VOLVO',
                    style: TextStyle(
                      color: Colors.blueAccent,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Descargando telemetría de flota...',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

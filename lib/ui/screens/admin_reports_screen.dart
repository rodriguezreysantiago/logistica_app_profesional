import 'dart:ui'; // ✅ MENTOR: Necesario para el efecto BackdropFilter (Blur)
import 'package:flutter/material.dart';
import '../../core/utils/report_checklist.dart'; 
import '../../core/utils/report_flota.dart'; 
import '../../core/services/volvo_api_service.dart'; 

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  bool _generando = false;

  // --- LÓGICA DE EXPORTACIÓN BLINDADA ---

  Future<void> _ejecutarReporteChecklist() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ReportChecklistService.mostrarOpcionesYGenerar(context);
    } catch (e) {
      if (mounted) _mostrarSnack(messenger, "❌ Error: $e", esError: true);
    }
  }

  Future<void> _prepararYGenerarReporteFlota() async {
    // ✅ MENTOR: Capturamos el messenger ANTES de cualquier proceso asíncrono.
    final messenger = ScaffoldMessenger.of(context);
    
    setState(() => _generando = true);
    
    try {
      // 1. Bajamos la data de Volvo
      final volvoService = VolvoApiService();
      final cacheVolvo = await volvoService.traerDatosFlota();

      if (!mounted) return;
      setState(() => _generando = false);

      // 2. Abrimos el diálogo de opciones
      await ReportGenerator.mostrarOpcionesYGenerar(context, cacheVolvo);

    } catch (e) {
      if (mounted) {
        setState(() => _generando = false);
        _mostrarSnack(messenger, "❌ Error al conectar con Volvo: $e", esError: true);
      }
    }
  }

  void _mostrarSnack(ScaffoldMessengerState messenger, String mensaje, {bool esError = false}) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(mensaje, style: const TextStyle(fontWeight: FontWeight.bold)), 
        backgroundColor: esError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("CENTRO DE REPORTES", style: TextStyle(letterSpacing: 1.2)),
      ),
      body: Stack(
        children: [
          // Fondo base (heredado de main.dart)
          Positioned.fill(
            child: Image.asset(
              'assets/images/fondo_login.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => 
                  Container(color: Theme.of(context).scaffoldBackgroundColor),
            ),
          ),
          Positioned.fill(child: Container(color: Colors.black.withAlpha(200))),

          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20.0),
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 5, bottom: 20),
                  child: Text(
                    "INFORMES ESTRATÉGICOS",
                    style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 2),
                  ),
                ),
                
                // 📝 REPORTE 1: CHECKLISTS
                _buildReportCard(
                  titulo: "Checklists Mensuales",
                  descripcion: "Reporte de novedades y roturas cargadas por choferes.",
                  icono: Icons.fact_check_rounded,
                  color: Colors.greenAccent,
                  onTap: _generando ? null : _ejecutarReporteChecklist,
                ),

                const SizedBox(height: 15),

                // 🚛 REPORTE 2: ESTADO DE FLOTA (API Volvo)
                _buildReportCard(
                  titulo: "Estado de Flota (Volvo)",
                  descripcion: "Sincroniza consumo, KMs y posición con Volvo Connect.",
                  icono: Icons.cloud_sync_rounded,
                  color: Colors.blueAccent,
                  onTap: _generando ? null : _prepararYGenerarReporteFlota,
                ),

                const SizedBox(height: 15),

                // REPORTE 3: BLOQUEADO
                _buildReportCard(
                  titulo: "Consumo de Combustible",
                  descripcion: "Análisis histórico de litros por unidad. (Próximamente)",
                  icono: Icons.local_gas_station_rounded,
                  color: Colors.white,
                  isLocked: true,
                  onTap: null,
                ),
              ],
            ),
          ),
          
          // ✅ MENTOR: Pantalla de carga con Blur (Cristal esmerilado) para UX Premium
          if (_generando)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
                child: Container(
                  color: Colors.black.withAlpha(150),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.blueAccent.withAlpha(50))
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.blueAccent),
                          SizedBox(height: 25),
                          Text("CONECTANDO CON VOLVO", 
                            style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, letterSpacing: 1)),
                          SizedBox(height: 10),
                          Text("Descargando telemetría de flota...", 
                            style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ✅ MENTOR: Tarjeta rediseñada para responder correctamente al "Tap" (InkWell Ripple Fix)
  Widget _buildReportCard({
    required String titulo,
    required String descripcion,
    required IconData icono,
    required Color color,
    required VoidCallback? onTap,
    bool isLocked = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface, // Toma el color global
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(isLocked ? 15 : 50), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20), // Para que la onda de choque no se salga por las esquinas
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withAlpha(isLocked ? 10 : 30),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icono, color: isLocked ? Colors.white24 : color, size: 28),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo, 
                        style: TextStyle(
                          color: isLocked ? Colors.white38 : Colors.white, 
                          fontWeight: FontWeight.bold,
                          fontSize: 15
                        )
                      ),
                      const SizedBox(height: 6),
                      Text(descripcion, 
                        style: TextStyle(color: isLocked ? Colors.white24 : Colors.white54, fontSize: 12, height: 1.3)
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
          ),
        ),
      ),
    );
  }
}
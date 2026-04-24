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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1D2D),
      appBar: AppBar(
        title: const Text("CENTRO DE REPORTES", 
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "INFORMES ESTRATÉGICOS",
                  style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 2),
                ),
                const SizedBox(height: 25),
                
                // 📝 REPORTE 1: CHECKLISTS
                _buildReportCard(
                  titulo: "Checklists Mensuales",
                  descripcion: "Reporte de novedades y roturas cargadas por choferes.",
                  icono: Icons.fact_check_rounded,
                  color: Colors.greenAccent,
                  // ✅ Cambiado: Ya no ponemos _generando en true acá porque primero abre el diálogo
                  onTap: _generando ? null : _ejecutarReporteChecklist,
                ),

                const SizedBox(height: 20),

                // 🚛 REPORTE 2: ESTADO DE FLOTA (API Volvo)
                _buildReportCard(
                  titulo: "Estado de Flota (API Volvo)",
                  descripcion: "Sincroniza consumo, KMs y posición con Volvo Connect en tiempo real.",
                  icono: Icons.cloud_sync_rounded,
                  color: Colors.blueAccent,
                  onTap: _generando ? null : _prepararYGenerarReporteFlota,
                ),

                const SizedBox(height: 20),

                _buildReportCard(
                  titulo: "Consumo de Combustible",
                  descripcion: "Análisis histórico de litros por unidad.",
                  icono: Icons.local_gas_station_rounded,
                  color: Colors.white24,
                  isLocked: true,
                  onTap: null,
                ),
              ],
            ),
          ),
          
          // Pantalla de carga (Solo se activa durante procesos asíncronos pesados)
          if (_generando)
            Container(
              color: Colors.black87,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.blueAccent),
                    SizedBox(height: 25),
                    Text("SINCRONIZANDO DATOS...", 
                      style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    SizedBox(height: 10),
                    Text("Esto puede tardar unos segundos", 
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- LÓGICA DE EXPORTACIÓN ---

  Future<void> _ejecutarReporteChecklist() async {
    // ✅ CORREGIDO: Llamamos al nuevo servicio que abre el diálogo de opciones
    try {
      await ReportChecklistService.mostrarOpcionesYGenerar(context);
    } catch (e) {
      if (mounted) _mostrarSnack("❌ Error: $e", esError: true);
    }
  }

  Future<void> _prepararYGenerarReporteFlota() async {
    setState(() => _generando = true);
    
    try {
      // 1. Bajamos la data de Volvo
      final volvoService = VolvoApiService();
      final cacheVolvo = await volvoService.traerDatosFlota();

      if (!mounted) return;
      setState(() => _generando = false);

      // 2. Abrimos el diálogo de opciones (ReportGenerator es el nombre de tu clase en report_flota.dart)
      await ReportGenerator.mostrarOpcionesYGenerar(context, cacheVolvo);

    } catch (e) {
      if (mounted) {
        setState(() => _generando = false);
        _mostrarSnack("❌ Error al conectar con Volvo: $e", esError: true);
      }
    }
  }

  void _mostrarSnack(String mensaje, {bool esError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje), 
        backgroundColor: esError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildReportCard({
    required String titulo,
    required String descripcion,
    required IconData icono,
    required Color color,
    required VoidCallback? onTap,
    bool isLocked = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withAlpha(50), width: 1),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: color.withAlpha(30),
              child: Icon(icono, color: color, size: 28),
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
                  const SizedBox(height: 4),
                  Text(descripcion, 
                    style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.3)
                  ),
                ],
              ),
            ),
            Icon(
              isLocked ? Icons.lock_outline : Icons.chevron_right_rounded, 
              color: isLocked ? Colors.white24 : Colors.white38
            ),
          ],
        ),
      ),
    );
  }
}
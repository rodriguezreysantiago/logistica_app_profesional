import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/utils/formatters.dart';
import '../widgets/preview_screen.dart'; // ✅ Importamos el visor interno

class UserMiEquipoScreen extends StatelessWidget {
  final String dniUser;

  const UserMiEquipoScreen({super.key, required this.dniUser});

  // --- SOLICITAR CAMBIO ---
  Future<void> _solicitarCambioUnidad(BuildContext context, String tipo, String patenteActual) async {
    try {
      await FirebaseFirestore.instance.collection('SOLICITUDES').add({
        'dni_empleado': dniUser,
        'tipo_solicitud': 'CAMBIO_UNIDAD',
        'detalle': 'Solicita cambio de $tipo (Actual: $patenteActual)',
        'fecha': FieldValue.serverTimestamp(),
        'estado': 'PENDIENTE',
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Solicitud enviada a la oficina técnica."), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error al enviar solicitud"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- ABRIR DOCUMENTO (VISOR INTERNO) ---
  void _abrirDocumento(BuildContext context, String? url, String titulo) {
    if (url == null || url.isEmpty || url == "-") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Documento no disponible"), backgroundColor: Colors.orange),
      );
      return;
    }
    // ✅ Ahora usa el PreviewScreen para no salir de la app
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PreviewScreen(url: url, titulo: titulo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, 
      appBar: AppBar(
        title: const Text("Mi Equipo Asignado"),
        centerTitle: true,
        backgroundColor: Colors.transparent, 
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/fondo_login.jpg', 
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: const Color(0xFF0D1D2D)),
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withAlpha(200)),
          ),
          
          SafeArea(
            child: FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('EMPLEADOS').doc(dniUser).get(),
              builder: (context, empleadoSnapshot) {
                if (empleadoSnapshot.hasError) return const Center(child: Text("Error de conexión", style: TextStyle(color: Colors.white70)));
                if (empleadoSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.orangeAccent));
                }

                if (!empleadoSnapshot.hasData || !empleadoSnapshot.data!.exists) {
                  return const Center(child: Text("Datos no disponibles", style: TextStyle(color: Colors.white70)));
                }

                var empleadoData = empleadoSnapshot.data!.data() as Map<String, dynamic>;
                String patenteVehiculo = (empleadoData['VEHICULO'] ?? "").toString().trim();
                String patenteEnganche = (empleadoData['ENGANCHE'] ?? "").toString().trim();

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildSeccionUnidad(context, "TRACTOR / CHASIS", patenteVehiculo, Icons.local_shipping_outlined),
                    const SizedBox(height: 30),
                    _buildSeccionUnidad(context, "ENGANCHE (Batea/Tolva)", patenteEnganche, Icons.grid_view_rounded),
                    const SizedBox(height: 40),
                    const Center(
                      child: Text(
                        "Para cambios permanentes o errores,\nuse el botón de solicitar cambio.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white24, fontSize: 11),
                      ),
                    )
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionUnidad(BuildContext context, String titulo, String patente, IconData icono) {
    bool estaVacia = patente.isEmpty || patente == "-" || patente == "SIN ASIGNAR";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 10),
              child: Text(
                titulo, 
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orangeAccent, letterSpacing: 2)
              ),
            ),
            if (!estaVacia)
              TextButton.icon(
                onPressed: () => _solicitarCambioUnidad(context, titulo, patente),
                icon: const Icon(Icons.swap_horiz, size: 14, color: Colors.orangeAccent),
                label: const Text("SOLICITAR CAMBIO", style: TextStyle(color: Colors.orangeAccent, fontSize: 10)),
              ),
          ],
        ),
        if (estaVacia) 
          _cardGlass(
            child: const ListTile(
              leading: Icon(Icons.info_outline, color: Colors.white24),
              title: Text("Sin unidad asignada", style: TextStyle(color: Colors.white38, fontSize: 14)),
            )
          )
        else
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('VEHICULOS').doc(patente).snapshots(),
            builder: (context, vehiculoSnapshot) {
              if (!vehiculoSnapshot.hasData || !vehiculoSnapshot.data!.exists) {
                return _cardGlass(child: ListTile(title: Text("Buscando $patente...", style: const TextStyle(color: Colors.white54))));
              }

              var v = vehiculoSnapshot.data!.data() as Map<String, dynamic>;
              
              int diasRto = AppFormatters.calcularDiasRestantes(v['VENCIMIENTO_RTO'] ?? "");
              int diasSeg = AppFormatters.calcularDiasRestantes(v['VENCIMIENTO_SEGURO'] ?? "");

              return _cardGlass(
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      leading: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white.withAlpha(20), shape: BoxShape.circle),
                        child: Icon(icono, color: Colors.white, size: 28),
                      ),
                      title: Text(
                        patente.toUpperCase(), 
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24, letterSpacing: 2)
                      ),
                      // ✅ MARCA Y MODELO SEPARADOS COMO EN LOS OTROS MENÚS
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text("MARCA: ", style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                Text(v['MARCA'] ?? 'S/D', style: const TextStyle(color: Colors.white, fontSize: 12)),
                              ],
                            ),
                            Row(
                              children: [
                                const Text("MODELO: ", style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                Text(v['MODELO'] ?? 'S/D', style: const TextStyle(color: Colors.white, fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(color: Colors.white10, height: 1),
                    
                    // RTO
                    _buildFilaVencimientoConArchivo(
                      context,
                      "RTO / VTV", 
                      v['VENCIMIENTO_RTO'], 
                      _getSemaforoColor(diasRto), 
                      diasRto,
                      v['ARCHIVO_RTO'], // Pasamos la URL para el color del icono
                      () => _abrirDocumento(context, v['ARCHIVO_RTO'], "RTO $patente")
                    ),
                    
                    // SEGURO
                    _buildFilaVencimientoConArchivo(
                      context,
                      "Póliza Seguro", 
                      v['VENCIMIENTO_SEGURO'], 
                      _getSemaforoColor(diasSeg), 
                      diasSeg,
                      v['ARCHIVO_SEGURO'], // Pasamos la URL para el color del icono
                      () => _abrirDocumento(context, v['ARCHIVO_SEGURO'], "Seguro $patente")
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Color _getSemaforoColor(int dias) {
    if (dias < 0) return Colors.red;
    if (dias <= 14) return Colors.orange;
    if (dias <= 30) return Colors.greenAccent;
    return Colors.blueAccent;
  }

  Widget _buildFilaVencimientoConArchivo(BuildContext context, String etiqueta, String? fecha, Color color, int dias, String? urlArchivo, VoidCallback onVerPdf) {
    // ✅ SEMÁFORO DE COLOR: Azul si hay archivo, Gris si no
    bool tieneArchivo = urlArchivo != null && urlArchivo.isNotEmpty && urlArchivo != "-";

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(etiqueta, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                Text(
                  AppFormatters.formatearFecha(fecha ?? ""),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          // ✅ BOTÓN PDF CON COLOR INTELIGENTE
          IconButton(
            onPressed: onVerPdf,
            icon: Icon(
              Icons.picture_as_pdf_outlined, 
              color: tieneArchivo ? Colors.blueAccent : Colors.white24, // Azul si existe, Gris si no
              size: 22
            ),
            tooltip: tieneArchivo ? "Ver Documento" : "Sin archivo cargado",
          ),
          const SizedBox(width: 10),
          Container(
            width: 45,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: color.withAlpha(35),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withAlpha(100))
            ),
            child: Center(
              child: Text("${dias}d", style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardGlass({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(20), 
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withAlpha(30)),
      ),
      child: child,
    );
  }
}
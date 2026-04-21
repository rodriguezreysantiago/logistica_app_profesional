import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/utils/formatters.dart';

class UserMiEquipoScreen extends StatelessWidget {
  final String dniUser;

  const UserMiEquipoScreen({super.key, required this.dniUser});

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
          // 1. Fondo de pantalla
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
                if (empleadoSnapshot.hasError) return const Center(child: Text("Error de conexión con el servidor", style: TextStyle(color: Colors.white70)));
                if (empleadoSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.orangeAccent));
                }

                if (!empleadoSnapshot.hasData || !empleadoSnapshot.data!.exists) {
                  return const Center(child: Text("Datos de legajo no disponibles", style: TextStyle(color: Colors.white70)));
                }

                var empleadoData = empleadoSnapshot.data!.data() as Map<String, dynamic>;
                
                // Limpiamos las patentes para evitar errores de búsqueda en Firestore
                String patenteVehiculo = (empleadoData['VEHICULO'] ?? "").toString().trim();
                String patenteEnganche = (empleadoData['ENGANCHE'] ?? "").toString().trim();

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildSeccionUnidad("TRACTOR / CHASIS", patenteVehiculo, Icons.local_shipping_outlined),
                    const SizedBox(height: 30),
                    _buildSeccionUnidad("ENGANCHE (Batea/Tolva)", patenteEnganche, Icons.grid_view_rounded),
                    const SizedBox(height: 40),
                    const Center(
                      child: Text(
                        "Cualquier error en las patentes asignadas,\ncomunicarse con la oficina técnica.",
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

  Widget _buildSeccionUnidad(String titulo, String patente, IconData icono) {
    bool estaVacia = patente.isEmpty || patente == "-" || patente == "SIN ASIGNAR";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 10),
          child: Text(
            titulo, 
            style: const TextStyle(
              fontSize: 11, 
              fontWeight: FontWeight.bold, 
              color: Colors.orangeAccent,
              letterSpacing: 2
            )
          ),
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
              if (vehiculoSnapshot.hasError) return _cardGlass(child: const ListTile(title: Text("Error al cargar unidad", style: TextStyle(color: Colors.redAccent))));
              
              if (!vehiculoSnapshot.hasData || !vehiculoSnapshot.data!.exists) {
                return _cardGlass(child: ListTile(title: Text("Buscando $patente...", style: const TextStyle(color: Colors.white54))));
              }

              var v = vehiculoSnapshot.data!.data() as Map<String, dynamic>;
              
              // Lógica de Semáforo Unificada (S.M.A.R.T. Logic)
              int diasRto = AppFormatters.calcularDiasRestantes(v['VENCIMIENTO_RTO'] ?? "");
              Color colorRto = _getSemaforoColor(diasRto);

              int diasSeg = AppFormatters.calcularDiasRestantes(v['VENCIMIENTO_SEGURO'] ?? "");
              Color colorSeg = _getSemaforoColor(diasSeg);

              return _cardGlass(
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      leading: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(20),
                          shape: BoxShape.circle
                        ),
                        child: Icon(icono, color: Colors.white, size: 28),
                      ),
                      title: Text(
                        patente.toUpperCase(), 
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24, letterSpacing: 2)
                      ),
                      subtitle: Text(
                        "${v['MARCA'] ?? 'S/D'} ${v['MODELO'] ?? ''}",
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ),
                    const Divider(color: Colors.white10, height: 1),
                    _buildFilaVencimiento("Vto. RTO / VTV", v['VENCIMIENTO_RTO'], colorRto, diasRto),
                    _buildFilaVencimiento("Vto. SEGURO", v['VENCIMIENTO_SEGURO'], colorSeg, diasSeg),
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

  Widget _buildFilaVencimiento(String etiqueta, String? fecha, Color color, int dias) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(etiqueta, style: const TextStyle(color: Colors.white60, fontSize: 13)),
          ),
          Text(
            AppFormatters.formatearFecha(fecha ?? ""),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 15),
          Container(
            width: 45,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: color.withAlpha(35),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withAlpha(100))
            ),
            child: Center(
              child: Text(
                "${dias}d",
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
              ),
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
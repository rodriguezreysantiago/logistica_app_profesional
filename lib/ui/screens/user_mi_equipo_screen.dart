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
        title: const Text("Mi Equipo"),
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
              fit: BoxFit.cover
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withAlpha(180)),
          ),
          
          SafeArea(
            child: FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('EMPLEADOS').doc(dniUser).get(),
              builder: (context, empleadoSnapshot) {
                if (empleadoSnapshot.hasError) return const Center(child: Text("Error al cargar", style: TextStyle(color: Colors.white)));
                if (empleadoSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.white));
                }

                if (!empleadoSnapshot.hasData || !empleadoSnapshot.data!.exists) {
                  return const Center(child: Text("Perfil no encontrado", style: TextStyle(color: Colors.white)));
                }

                var empleadoData = empleadoSnapshot.data!.data() as Map<String, dynamic>;
                
                // ACTUALIZACIÓN: Ahora usamos los campos correctos de tu Firebase
                String patenteVehiculo = empleadoData['VEHICULO'] ?? "";
                String patenteEnganche = empleadoData['ENGANCHE'] ?? "";

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildSeccionUnidad("(VEHÍCULO)", patenteVehiculo),
                    const SizedBox(height: 30),
                    _buildSeccionUnidad("(ENGANCHE)", patenteEnganche),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionUnidad(String titulo, String patente) {
    bool estaVacia = patente.isEmpty || patente == "SIN ASIGNAR";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            titulo, 
            style: const TextStyle(
              fontSize: 14, 
              fontWeight: FontWeight.bold, 
              color: Colors.blueAccent,
              letterSpacing: 1.2
            )
          ),
        ),
        if (estaVacia) 
          _cardGlass(
            child: ListTile(
              leading: const Icon(Icons.not_interested, color: Colors.white30),
              title: const Text("Sin unidad asignada", style: TextStyle(color: Colors.white30)),
            )
          )
        else
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('VEHICULOS').doc(patente).snapshots(),
            builder: (context, vehiculoSnapshot) {
              if (!vehiculoSnapshot.hasData || !vehiculoSnapshot.data!.exists) {
                return _cardGlass(child: ListTile(title: Text("Buscando $patente...", style: const TextStyle(color: Colors.white))));
              }

              var v = vehiculoSnapshot.data!.data() as Map<String, dynamic>;
              
              // Usamos el formateador para calcular el estado de la RTO
              int diasRto = AppFormatters.calcularDiasRestantes(v['VENCIMIENTO_RTO']);
              Color colorAlerta = diasRto < 0 ? Colors.redAccent : (diasRto < 15 ? Colors.orangeAccent : Colors.greenAccent);

              return _cardGlass(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorAlerta.withAlpha(40),
                      shape: BoxShape.circle
                    ),
                    child: Icon(Icons.local_shipping, color: colorAlerta, size: 30),
                  ),
                  title: Text(
                    patente, 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      "${v['MARCA']} ${v['MODELO']}\nVto. RTO: ${AppFormatters.formatearFecha(v['VENCIMIENTO_RTO'])}",
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
                  isThreeLine: true,
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _cardGlass({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(20), 
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: child,
      ),
    );
  }
}
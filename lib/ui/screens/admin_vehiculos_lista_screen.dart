import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminVehiculosListaScreen extends StatefulWidget {
  const AdminVehiculosListaScreen({super.key});

  @override
  State<AdminVehiculosListaScreen> createState() => _AdminVehiculosListaScreenState();
}

class _AdminVehiculosListaScreenState extends State<AdminVehiculosListaScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = "";

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchText = _searchController.text.toUpperCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Gestión de Flota"),
          backgroundColor: Colors.orange.shade900,
          foregroundColor: Colors.white,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(110),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Buscar por patente (Dominio)...",
                      prefixIcon: const Icon(Icons.search),
                      fillColor: Colors.white,
                      filled: true,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const TabBar(
                  indicatorColor: Colors.white,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  tabs: [
                    Tab(icon: Icon(Icons.local_shipping), text: "CHASIS"),
                    Tab(icon: Icon(Icons.ad_units), text: "ACOPLADOS"),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _buildListaFiltrada("CHASIS"),
            _buildListaFiltrada("ACOPLADO"),
          ],
        ),
      ),
    );
  }

  Widget _buildListaFiltrada(String tipoVehiculo) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('VEHICULOS')
          .where('TIPO', isEqualTo: tipoVehiculo)
          .orderBy('DOMINIO')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text("Error al cargar datos"));
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final lista = snapshot.data!.docs.where((doc) {
          final patente = (doc['DOMINIO'] as String? ?? '').toUpperCase();
          return patente.contains(_searchText);
        }).toList();

        if (lista.isEmpty) {
          return const Center(child: Text("No se encontraron unidades"));
        }

        return ListView.builder(
          itemCount: lista.length,
          padding: const EdgeInsets.all(10),
          itemBuilder: (context, index) {
            var data = lista[index].data() as Map<String, dynamic>;

            // --- LÓGICA DE VENCIMIENTOS ---
            String venceRto = data['VENCE_RTO'] ?? 'Sin fecha';
            String venceSeguro = data['VENCE_SEGURO'] ?? 'Sin fecha';
            
            // Ejemplo de alerta: si la fecha contiene un año pasado, se pone rojo
            bool esCritico = venceRto.contains("2024") || venceRto.contains("2023");

            return Card(
              elevation: 3,
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ExpansionTile(
                leading: Icon(
                  tipoVehiculo == "CHASIS" ? Icons.local_shipping : Icons.local_shipping, // Cambié el segundo por trailer para diferenciar
                  color: esCritico ? Colors.red : Colors.orange.shade900,
                  size: 30,
                ),
                title: Text(
                  "Patente: ${data['DOMINIO'] ?? 'S/D'}",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                subtitle: Text("Marca: ${data['MARCA'] ?? 'No especificado'}"),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        _filaDato("Estado:", data['ESTADO'] ?? 'Activo', Icons.info_outline),
                        const Divider(),
                        _filaDato("Vence RTO:", venceRto, Icons.fact_check_outlined),
                        _filaDato("Vence Seguro:", venceSeguro, Icons.security_outlined),
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: () {
                            // Aquí iría tu lógica para editar
                          },
                          icon: const Icon(Icons.edit),
                          label: const Text("Editar Vehículo"),
                        )
                      ],
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Widget pequeño para organizar las filas de datos
  Widget _filaDato(String titulo, String valor, IconData icono) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icono, size: 18, color: Colors.grey),
          const SizedBox(width: 10),
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          Text(valor, style: const TextStyle(color: Colors.blueGrey)),
        ],
      ),
    );
  }
}
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

  // --- NUEVA FUNCIÓN PARA FORMATEAR FECHA ---
  String _formatearFecha(String? fecha) {
    if (fecha == null || fecha == 'Sin fecha' || fecha.isEmpty) return 'Sin fecha';
    try {
      // Divide AAAA-MM-DD
      List<String> partes = fecha.split('-');
      if (partes.length == 3) {
        // Retorna DD-MM-AAAA
        return "${partes[2]}-${partes[1]}-${partes[0]}";
      }
      return fecha;
    } catch (e) {
      return fecha;
    }
  }

  Color _getColorVencimiento(String? fecha) {
    if (fecha == null || fecha == 'Sin fecha' || fecha.isEmpty) return Colors.grey;
    try {
      DateTime vencimiento = DateTime.parse(fecha);
      DateTime hoy = DateTime.now();
      if (vencimiento.isBefore(hoy.add(const Duration(days: 30)))) {
        return Colors.red.shade700;
      }
      return Colors.green.shade700;
    } catch (e) {
      return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
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
                      hintText: "Buscar por patente (DOMINIO)...",
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
                  isScrollable: true,
                  tabs: [
                    Tab(icon: Icon(Icons.local_shipping), text: "TRACTORES"),
                    Tab(icon: Icon(Icons.inventory_2), text: "BATEAS"),
                    Tab(icon: Icon(Icons.agriculture), text: "TOLVAS"),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _buildListaFiltrada("TRACTOR"),
            _buildListaFiltrada("BATEA"),
            _buildListaFiltrada("TOLVA"),
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
        if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        final lista = docs.where((doc) {
          final patente = (doc['DOMINIO'] as String? ?? '').toUpperCase();
          return patente.contains(_searchText);
        }).toList();

        if (lista.isEmpty) {
          return Center(child: Text("No se encontraron: $tipoVehiculo"));
        }

        return ListView.builder(
          itemCount: lista.length,
          padding: const EdgeInsets.all(10),
          itemBuilder: (context, index) {
            var data = lista[index].data() as Map<String, dynamic>;
            
            Color colorAlerta = _getColorVencimiento(data['VENCIMIENTO_RTO']);

            IconData iconito;
            if (tipoVehiculo == "TRACTOR") {
              iconito = Icons.local_shipping;
            } else if (tipoVehiculo == "BATEA") {
              iconito = Icons.view_agenda_outlined;
            } else {
              iconito = Icons.agriculture;
            }

            return Card(
              elevation: 3,
              margin: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ExpansionTile(
                leading: Icon(iconito, color: colorAlerta, size: 35),
                title: Text(
                  "${data['DOMINIO'] ?? 'S/D'}",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                subtitle: Text("${data['MARCA'] ?? 'S/D'} - ${data['MODELO'] ?? 'S/D'}"),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("DETALLES TÉCNICOS", 
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                        const SizedBox(height: 8),
                        _filaDato("Estado:", data['ESTADO'] ?? 'S/D', Icons.info_outline),
                        _filaDato("Año:", data['AÑO'] ?? 'S/D', Icons.calendar_today),
                        _filaDato("Empresa:", data['EMPRESA'] ?? 'S/D', Icons.business),
                        _filaDato("Tipificada:", data['TIPIFICADA'] ?? 'S/D', Icons.scale),
                        
                        const Divider(height: 30),
                        
                        const Text("DOCUMENTACIÓN", 
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                        const SizedBox(height: 8),
                        _filaDato("RTO Nro:", data['RTO_NRO'] ?? 'S/D', Icons.fact_check_outlined),
                        
                        // Aplicación del nuevo formato de fecha
                        _filaDato("Vence RTO:", _formatearFecha(data['VENCIMIENTO_RTO']), 
                          Icons.event_available, 
                          colorValor: _getColorVencimiento(data['VENCIMIENTO_RTO'])),
                        
                        _filaDato("Póliza Nro:", data['POLIZA_NRO'] ?? 'S/D', Icons.security),
                        
                        // Aplicación del nuevo formato de fecha
                        _filaDato("Vence Seguro:", _formatearFecha(data['VENCIMIENTO_POLIZA']), 
                          Icons.event_busy, 
                          colorValor: _getColorVencimiento(data['VENCIMIENTO_POLIZA'])),

                        const SizedBox(height: 15),
                        Center(
                          child: ElevatedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.edit),
                            label: const Text("EDITAR VEHÍCULO"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade900,
                              foregroundColor: Colors.white,
                            ),
                          ),
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

  Widget _filaDato(String titulo, String valor, IconData icono, {Color? colorValor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icono, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(
            valor, 
            style: TextStyle(
              color: colorValor ?? Colors.black87,
              fontWeight: colorValor != null ? FontWeight.bold : FontWeight.normal
            )
          ),
        ],
      ),
    );
  }
}
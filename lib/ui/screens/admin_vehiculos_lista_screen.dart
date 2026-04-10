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

  String _formatearFecha(String? fecha) {
    if (fecha == null || fecha == 'Sin fecha' || fecha.isEmpty) return 'Sin fecha';
    try {
      List<String> partes = fecha.split('-');
      if (partes.length == 3) {
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
        return Colors.redAccent;
      }
      return Colors.greenAccent; 
    } catch (e) {
      return Colors.blueGrey;
    }
  }

  // --- FUNCIÓN PARA VER EL ARCHIVO ---
  void _verDocumento(String? url, String titulo) {
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No hay archivo adjunto para este documento.")),
      );
      return;
    }
    // Aquí luego integrarás 'url_launcher' o una vista de imagen
    debugPrint("Abriendo documento de $titulo: $url");
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        extendBodyBehindAppBar: true, 
        appBar: AppBar(
          title: const Text("Gestión de Flota"),
          centerTitle: true,
          backgroundColor: Colors.transparent, 
          elevation: 0,
          foregroundColor: Colors.white,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(110),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Buscar por patente (DOMINIO)...",
                      hintStyle: const TextStyle(color: Colors.white70),
                      prefixIcon: const Icon(Icons.search, color: Colors.white70),
                      fillColor: Colors.white.withValues(alpha: 0.15),
                      filled: true,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                    ),
                  ),
                ),
                const TabBar(
                  indicatorColor: Colors.orangeAccent,
                  labelColor: Colors.orangeAccent,
                  unselectedLabelColor: Colors.white,
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
        body: Stack(
          children: [
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/fondo_login.jpg'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Container(color: Colors.black.withValues(alpha: 0.45)),
            SafeArea(
              child: TabBarView(
                children: [
                  _buildListaFiltrada("TRACTOR"),
                  _buildListaFiltrada("BATEA"),
                  _buildListaFiltrada("TOLVA"),
                ],
              ),
            ),
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
        if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.white)));
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }

        final docs = snapshot.data?.docs ?? [];
        final lista = docs.where((doc) {
          final patente = (doc['DOMINIO'] as String? ?? '').toUpperCase();
          return patente.contains(_searchText);
        }).toList();

        if (lista.isEmpty) {
          return Center(child: Text("No se encontraron: $tipoVehiculo", style: const TextStyle(color: Colors.white70)));
        }

        return ListView.builder(
          itemCount: lista.length,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
          itemBuilder: (context, index) {
            var data = lista[index].data() as Map<String, dynamic>;
            Color colorAlertaRTO = _getColorVencimiento(data['VENCIMIENTO_RTO']);
            Color colorAlertaPoliza = _getColorVencimiento(data['VENCIMIENTO_POLIZA']);

            IconData iconito;
            if (tipoVehiculo == "TRACTOR") {
              iconito = Icons.local_shipping;
            } else if (tipoVehiculo == "BATEA") {
              iconito = Icons.view_agenda_outlined;
            } else {
              iconito = Icons.agriculture;
            }

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: ExpansionTile(
                iconColor: Colors.white,
                collapsedIconColor: Colors.white70,
                tilePadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                leading: Icon(iconito, color: Colors.white, size: 30),
                title: Text(
                  "${data['DOMINIO'] ?? 'S/D'}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold, 
                    fontSize: 20, 
                    letterSpacing: 1.2,
                    color: Colors.white
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("DETALLES TÉCNICOS", 
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70, letterSpacing: 1)),
                        const SizedBox(height: 12),
                        
                        _filaDatoTransparente("Marca:", data['MARCA'] ?? 'S/D', Icons.branding_watermark_outlined, Colors.blueAccent),
                        _filaDatoTransparente("Modelo:", data['MODELO'] ?? 'S/D', Icons.directions_car_filled_outlined, Colors.indigoAccent),
                        _filaDatoTransparente("Estado:", data['ESTADO'] ?? 'S/D', Icons.info_outline, Colors.orangeAccent),
                        _filaDatoTransparente("Año:", data['AÑO'] ?? 'S/D', Icons.calendar_today, Colors.yellowAccent),
                        _filaDatoTransparente("Empresa:", data['EMPRESA'] ?? 'S/D', Icons.business, Colors.brown.shade200),
                        _filaDatoTransparente("Tipificada:", data['TIPIFICADA'] ?? 'S/D', Icons.scale, Colors.tealAccent),
                        
                        Divider(height: 35, color: Colors.white.withValues(alpha: 0.2)),
                        
                        const Text("DOCUMENTACIÓN", 
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70, letterSpacing: 1)),
                        const SizedBox(height: 12),

                        // --- FILAS CON EL OJO PARA VER ARCHIVOS ---
                        _filaDatoTransparente(
                          "RTO Nro:", 
                          data['RTO_NRO'] ?? 'S/D', 
                          Icons.fact_check_outlined, 
                          Colors.grey.shade300,
                          onAction: () => _verDocumento(data['URL_RTO'], "RTO"),
                        ),
                        _filaDatoTransparente(
                          "Vence RTO:", 
                          _formatearFecha(data['VENCIMIENTO_RTO']), 
                          Icons.event_available, 
                          colorAlertaRTO,
                        ),
                        
                        const SizedBox(height: 10),

                        _filaDatoTransparente(
                          "Póliza Nro:", 
                          data['POLIZA_NRO'] ?? 'S/D', 
                          Icons.security, 
                          Colors.grey.shade300,
                          onAction: () => _verDocumento(data['URL_POLIZA'], "Póliza"),
                        ),
                        _filaDatoTransparente(
                          "Vence Seguro:", 
                          _formatearFecha(data['VENCIMIENTO_POLIZA']), 
                          Icons.event_busy, 
                          colorAlertaPoliza,
                        ),

                        const SizedBox(height: 25),
                        Center(
                          child: ElevatedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.edit, size: 18),
                            label: const Text("EDITAR VEHÍCULO", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orangeAccent.withValues(alpha: 0.8),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  // --- FILA DE DATOS CORREGIDA CON BOTÓN DE ACCIÓN (OJO) ---
  Widget _filaDatoTransparente(String titulo, String valor, IconData icono, Color colorIcono, {VoidCallback? onAction}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icono, size: 17, color: colorIcono),
          const SizedBox(width: 12),
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 13)),
          const Spacer(),
          Text(
            valor, 
            style: const TextStyle(color: Colors.white, fontSize: 13)
          ),
          // Si pasamos una acción, mostramos el OJO
          if (onAction != null) ...[
            const SizedBox(width: 5),
            IconButton(
              icon: const Icon(Icons.visibility_outlined, color: Colors.white70, size: 20),
              onPressed: onAction,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: "Ver archivo",
            ),
          ]
        ],
      ),
    );
  }
}
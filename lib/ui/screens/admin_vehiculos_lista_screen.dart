import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/preview_screen.dart';

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

  String _aplicarFormatoFecha(String? fecha) {
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

  void _abrirDocumento(String? url, String nombreDocumento) {
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("No hay archivo cargado para $nombreDocumento")),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PreviewScreen(
          url: url,
          titulo: nombreDocumento,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        // Mismo diseño de Scaffold que venimos usando
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
                      hintText: "Buscar por patente...",
                      hintStyle: const TextStyle(color: Colors.white70),
                      prefixIcon: const Icon(Icons.search, color: Colors.white70),
                      fillColor: Colors.white.withValues(alpha: 0.15),
                      filled: true,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
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
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/fondo_login.jpg'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Container(color: Colors.black.withValues(alpha: 0.5)),
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

        return ListView.builder(
          itemCount: lista.length,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
          itemBuilder: (context, index) {
            var data = lista[index].data() as Map<String, dynamic>;
            
            String fechaRto = _aplicarFormatoFecha(data['VENCIMIENTO_RTO']);
            String fechaSeguro = _aplicarFormatoFecha(data['VENCIMIENTO_SEGURO']);

            // Lógica de color para el icono del ojo
            String? urlRto = data['ARCHIVO_RTO'];
            String? urlSeguro = data['ARCHIVO_SEGURO'];

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: ExpansionTile(
                iconColor: Colors.white,
                collapsedIconColor: Colors.white70,
                leading: Icon(
                  tipoVehiculo == "TRACTOR" ? Icons.local_shipping : Icons.view_agenda_outlined, 
                  color: Colors.white, size: 28
                ),
                title: Text(
                  "${data['DOMINIO'] ?? 'S/D'}",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
                ),
                subtitle: Text(
                  "${data['MARCA'] ?? ''} ${data['MODELO'] ?? ''}",
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("DETALLES TÉCNICOS", 
                          style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        
                        _filaInfo("Marca:", data['MARCA'] ?? 'S/D', Icons.branding_watermark_outlined, Colors.blueAccent),
                        _filaInfo("Modelo:", data['MODELO'] ?? 'S/D', Icons.directions_car_filled_outlined, Colors.indigoAccent),
                        _filaInfo("Año:", data['AÑO'] ?? 'S/D', Icons.calendar_today, Colors.yellowAccent),
                        _filaInfo("Tipificada:", data['TIPIFICADA'] ?? 'S/D', Icons.scale, Colors.tealAccent),
                        _filaInfo("Estado:", data['ESTADO'] ?? 'S/D', Icons.info_outline, data['ESTADO'] == 'OCUPADO' ? Colors.greenAccent : Colors.orangeAccent),
                        _filaInfo("Empresa:", data['EMPRESA'] ?? 'S/D', Icons.business, Colors.brown.shade200),
                        
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Divider(color: Colors.white12),
                        ),
                        
                        const Text("DOCUMENTACIÓN", 
                          style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),

                        _filaInfo(
                          "Vencimiento RTO:", 
                          fechaRto, 
                          Icons.event_available, 
                          _getColorVencimiento(data['VENCIMIENTO_RTO']),
                          // Color azul si el URL no es nulo ni está vacío
                          colorIconoAccion: (urlRto != null && urlRto.isNotEmpty) ? Colors.blueAccent : Colors.white38,
                          onAction: () => _abrirDocumento(urlRto, "RTO - ${data['DOMINIO']}"),
                        ),
                        
                        _filaInfo(
                          "Vencimiento Seguro:", 
                          fechaSeguro, 
                          Icons.security, 
                          _getColorVencimiento(data['VENCIMIENTO_SEGURO']),
                          // Color azul si el URL no es nulo ni está vacío
                          colorIconoAccion: (urlSeguro != null && urlSeguro.isNotEmpty) ? Colors.blueAccent : Colors.white38,
                          onAction: () => _abrirDocumento(urlSeguro, "Seguro - ${data['DOMINIO']}"),
                        ),
                        
                        const SizedBox(height: 20),
                        Center(
                          child: OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text("EDITAR VEHÍCULO"),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.orangeAccent),
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

  Widget _filaInfo(String titulo, String valor, IconData icono, Color colorIcono, {VoidCallback? onAction, Color? colorIconoAccion}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 16, color: colorIcono),
          const SizedBox(width: 10),
          Text(titulo, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              valor, 
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
          if (onAction != null) ...[
            const SizedBox(width: 10),
            IconButton(
              // Usamos el color de acción dinámico pasado desde el constructor
              icon: Icon(Icons.visibility_outlined, color: colorIconoAccion ?? Colors.white, size: 20),
              onPressed: onAction,
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
          ]
        ],
      ),
    );
  }
}
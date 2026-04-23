import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/utils/formatters.dart';
import '../../core/services/volvo_api_service.dart'; 
import '../../core/utils/report_generator.dart';
import '../widgets/preview_screen.dart';
import 'admin_vehiculo_form_screen.dart'; 
import 'admin_vehiculo_alta_screen.dart'; 

class AdminVehiculosListaScreen extends StatefulWidget {
  const AdminVehiculosListaScreen({super.key});

  @override
  State<AdminVehiculosListaScreen> createState() => _AdminVehiculosListaScreenState();
}

class _AdminVehiculosListaScreenState extends State<AdminVehiculosListaScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = "";
  List<dynamic> _cacheVolvo = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchText = _searchController.text.toUpperCase();
        });
      }
    });
    _precargarDatosVolvo();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _precargarDatosVolvo() async {
    try {
      final api = VolvoApiService();
      final datos = await api.traerDatosFlota();
      if (mounted) {
        setState(() => _cacheVolvo = datos);
        debugPrint("📦 Memoria Volvo: ${_cacheVolvo.length} unidades listas.");
      }
    } catch (e) {
      debugPrint("📡 [INFO] Sin conexión a la red de Volvo.");
    }
  }

  void _sincronizarUnidadIndividual(String patente, String vin) {
    final String cleanVin = vin.trim().toUpperCase();

    Future(() async {
      double? metros;
      try {
        final infoEnCache = _cacheVolvo.firstWhere(
          (v) => v['vin'].toString().toUpperCase() == cleanVin,
          orElse: () => null,
        );

        if (infoEnCache != null) {
          metros = (infoEnCache['hrTotalVehicleDistance'] ?? 
                    infoEnCache['lastKnownOdometer'] ?? 0).toDouble();
        } 

        if (metros == null || metros <= 0) {
          final api = VolvoApiService();
          metros = await api.traerKilometrajeCualquierVia(cleanVin);
        }

        if (metros != null && metros > 0 && mounted) {
          final double kmReal = metros / 1000;

          FirebaseFirestore.instance
              .collection('VEHICULOS')
              .doc(patente)
              .update({
            'KM_ACTUAL': kmReal,
            'ULTIMA_SINCRO': FieldValue.serverTimestamp(),
            'SINCRO_TIPO': 'AUTOMATIC_LIVE',
          }).then((_) {
            debugPrint("✅ $patente: Sincronizado.");
          }).catchError((_) {}); 
        } else {
          debugPrint("💤 $patente: En reposo.");
        }
      } catch (e) {
        debugPrint("ℹ️ $patente: No disponible.");
      }
    });
  }

  IconData _getIconoPorTipo(String tipo) {
    switch (tipo.toUpperCase()) {
      case 'TRACTOR': return Icons.local_shipping;
      case 'BATEA': return Icons.view_agenda_outlined;
      case 'TOLVA': return Icons.difference_outlined;
      default: return Icons.grid_view;
    }
  }

  Color _getColorVencimiento(String? fecha) {
    if (fecha == null || fecha.isEmpty) return Colors.grey;
    int dias = AppFormatters.calcularDiasRestantes(fecha);
    if (dias < 0) return Colors.red;
    if (dias <= 14) return Colors.orange;
    if (dias <= 30) return Colors.greenAccent;
    return Colors.blueAccent;
  }

  void _abrirDocumento(String? url, String nombreDocumento) {
    if (url == null || url.isEmpty || url == "-") {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("No hay archivo digital para $nombreDocumento"), backgroundColor: Colors.orange),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => PreviewScreen(url: url, titulo: nombreDocumento)),
    );
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
          backgroundColor: const Color(0xFF1A3A5A).withAlpha(220),
          elevation: 0,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.file_download, color: Colors.greenAccent),
              onPressed: () async {
                await ReportGenerator.mostrarOpcionesYGenerar(context, _cacheVolvo);
              },
              tooltip: "Configurar y Descargar Reporte",
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.orangeAccent),
              onPressed: _precargarDatosVolvo,
              tooltip: "Refrescar datos de Volvo",
            )
          ],
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
                      hintText: "Buscar patente...",
                      hintStyle: const TextStyle(color: Colors.white70),
                      prefixIcon: const Icon(Icons.search, color: Colors.white70),
                      fillColor: Colors.white.withAlpha(40),
                      filled: true,
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const TabBar(
                  indicatorColor: Colors.orangeAccent,
                  labelColor: Colors.orangeAccent,
                  unselectedLabelColor: Colors.white,
                  tabs: [
                    Tab(icon: Icon(Icons.local_shipping), text: "TRACTORES"),
                    Tab(icon: Icon(Icons.view_agenda_outlined), text: "BATEAS"),
                    Tab(icon: Icon(Icons.difference_outlined), text: "TOLVAS"),
                  ],
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminVehiculoAltaScreen()));
          },
          backgroundColor: Colors.orangeAccent,
          icon: const Icon(Icons.add_box_outlined, color: Colors.black),
          label: const Text("NUEVA UNIDAD", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
        body: Stack(
          children: [
            Positioned.fill(child: Image.asset('assets/images/fondo_login.jpg', fit: BoxFit.cover)),
            Positioned.fill(child: Container(color: Colors.black.withAlpha(200))),
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
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.orangeAccent));

        final docs = snapshot.data!.docs;
        final lista = docs.where((doc) {
          final patenteDoc = doc.id.toUpperCase();
          final patenteCampo = (doc['DOMINIO'] as String? ?? '').toUpperCase();
          return patenteDoc.contains(_searchText) || patenteCampo.contains(_searchText);
        }).toList();

        if (lista.isEmpty) return const Center(child: Text("Sin unidades registradas", style: TextStyle(color: Colors.white54)));

        return ListView.builder(
          itemCount: lista.length,
          padding: const EdgeInsets.only(top: 10, left: 10, right: 10, bottom: 90),
          itemBuilder: (context, index) {
            final doc = lista[index];
            final Map<String, dynamic> vData = doc.data() as Map<String, dynamic>;
            final String patenteId = doc.id;
            
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(20),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white.withAlpha(30)),
              ),
              child: ExpansionTile(
                key: PageStorageKey(patenteId),
                iconColor: Colors.orangeAccent,
                collapsedIconColor: Colors.white70,
                onExpansionChanged: (isExpanded) {
                  if (isExpanded && vData['MARCA'] == 'VOLVO' && vData['VIN'] != null) {
                    _sincronizarUnidadIndividual(patenteId, vData['VIN']);
                  }
                },
                leading: CircleAvatar(
                  backgroundColor: vData['ESTADO'] == 'LIBRE' ? Colors.green.withAlpha(40) : Colors.white.withAlpha(10),
                  child: Icon(_getIconoPorTipo(tipoVehiculo), color: vData['ESTADO'] == 'LIBRE' ? Colors.greenAccent : Colors.white70, size: 20),
                ),
                title: Text(patenteId, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.2)),
                subtitle: Text("${vData['MARCA'] ?? 'S/M'} - ${vData['ESTADO'] ?? 'S/E'}", style: TextStyle(color: vData['ESTADO'] == 'LIBRE' ? Colors.greenAccent : Colors.white38, fontSize: 11)),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      children: [
                        _filaInfo("Kilometraje Actual:", "${AppFormatters.formatearKilometraje(vData['KM_ACTUAL'])} KM", Icons.speed, Colors.orangeAccent),
                        if (vData['VIN'] != null && vData['VIN'] != "") _filaInfo("Nro. Chasis (VIN):", vData['VIN'], Icons.fingerprint, Colors.white60),
                        const Divider(color: Colors.white10),
                        
                        _filaInfo("Marca:", vData['MARCA'] ?? 'S/D', Icons.branding_watermark_outlined, Colors.blueAccent),
                        _filaInfo("Modelo:", vData['MODELO'] ?? 'S/D', Icons.directions_car_outlined, Colors.blueAccent),
                        
                        _filaInfo("Año Unidad:", "${vData['AÑO'] ?? vData['ANIO'] ?? 'S/D'}", Icons.calendar_today, Colors.white60),
                        _filaInfo("Titular / Empresa:", vData['EMPRESA'] ?? 'S/D', Icons.business, Colors.white60),
                        const Divider(color: Colors.white10, height: 20),
                        
                        _filaInfo(
                          "Vencimiento RTO:", 
                          AppFormatters.formatearFecha(vData['VENCIMIENTO_RTO']), 
                          Icons.fact_check, 
                          _getColorVencimiento(vData['VENCIMIENTO_RTO']), 
                          onAction: () => _abrirDocumento(vData['ARCHIVO_RTO'], "RTO - $patenteId"),
                          urlArchivo: vData['ARCHIVO_RTO'], // ✅ Semáforo de color
                        ),
                        _filaInfo(
                          "Póliza Seguro:", 
                          AppFormatters.formatearFecha(vData['VENCIMIENTO_SEGURO']), 
                          Icons.security, 
                          _getColorVencimiento(vData['VENCIMIENTO_SEGURO']), 
                          onAction: () => _abrirDocumento(vData['ARCHIVO_SEGURO'], "Seguro - $patenteId"),
                          urlArchivo: vData['ARCHIVO_SEGURO'], // ✅ Semáforo de color
                        ),
                        const SizedBox(height: 15),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(context, MaterialPageRoute(builder: (context) => AdminVehiculoFormScreen(vehiculoId: patenteId, datosIniciales: vData)));
                            },
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text("EDITAR FICHA TÉCNICA"),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
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

  Widget _filaInfo(String titulo, String valor, IconData icono, Color color, {VoidCallback? onAction, String? urlArchivo}) {
    bool tieneArchivo = urlArchivo != null && urlArchivo.isNotEmpty && urlArchivo != "-";

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icono, size: 14, color: color),
          const SizedBox(width: 10),
          Text(titulo, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const Spacer(),
          Text(valor.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          if (onAction != null) ...[
            const SizedBox(width: 10),
            IconButton(
              icon: Icon(
                Icons.visibility, 
                color: tieneArchivo ? Colors.blueAccent : Colors.white24, // ✅ Gris si no hay nada, Azul si hay algo
                size: 18
              ), 
              onPressed: onAction, 
              constraints: const BoxConstraints(), 
              padding: EdgeInsets.zero,
              tooltip: tieneArchivo ? "Ver documento" : "Sin documento cargado",
            ),
          ]
        ],
      ),
    );
  }
}
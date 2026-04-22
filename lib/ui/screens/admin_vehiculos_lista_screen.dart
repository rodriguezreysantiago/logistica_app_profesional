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
        debugPrint("📦 Memoria Volvo actualizada: ${_cacheVolvo.length} unidades.");
      }
    } catch (e) {
      debugPrint("❌ Error cargando memoria Volvo: $e");
    }
  }

  // ✅ SOLUCIÓN DEFINITIVA PARA WINDOWS: Separación de hilos
  void _sincronizarUnidadIndividual(String patente, String vin) {
    final String cleanVin = vin.trim().toUpperCase();

    // 1. Iniciamos el proceso asíncrono sin bloquear el hilo principal de Windows
    Future(() async {
      double? metros;
      try {
        // Buscamos en caché primero
        final infoEnCache = _cacheVolvo.firstWhere(
          (v) => v['vin'].toString().toUpperCase() == cleanVin,
          orElse: () => null,
        );

        if (infoEnCache != null) {
          metros = (infoEnCache['hrTotalVehicleDistance'] ?? 
                    infoEnCache['lastKnownOdometer'] ?? 0).toDouble();
        } 

        // Si no hay, rescate profundo vía API
        if (metros == null || metros <= 0) {
          debugPrint("🔍 [Windows] Rescate profundo para $patente");
          final api = VolvoApiService();
          metros = await api.traerKilometrajeCualquierVia(cleanVin);
        }

        // 2. ACTUALIZACIÓN SEGURA: "Disparar y olvidar"
        if (metros != null && metros > 0 && mounted) {
          final double kmReal = metros / 1000;

          // 🔥 LA CLAVE: No usamos 'await' aquí. 
          // Dejamos que Firestore maneje su propio hilo de C++ independientemente.
          FirebaseFirestore.instance
              .collection('VEHICULOS')
              .doc(patente)
              .update({
            'KM_ACTUAL': kmReal,
            'ULTIMA_SINCRO': FieldValue.serverTimestamp(),
            'SINCRO_TIPO': 'WINDOWS_STABLE_V1',
          }).then((_) {
            debugPrint("💾 [OK] $patente actualizado a $kmReal KM");
          }).catchError((err) {
            debugPrint("❌ Error Firestore Windows en $patente: $err");
          });
        }
      } catch (e) {
        debugPrint("🚨 Error en proceso de sincronización: $e");
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Generando reporte de flota...")),
                );
                await ReportGenerator.generarYCompartirReporte(_cacheVolvo);
              },
              tooltip: "Descargar Reporte CSV",
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
                        _filaInfo("Kilometraje:", "${AppFormatters.formatearKilometraje(vData['KM_ACTUAL'])} KM", Icons.speed, Colors.orangeAccent),
                        if (vData['VIN'] != null && vData['VIN'] != "") _filaInfo("VIN:", vData['VIN'], Icons.fingerprint, Colors.white60),
                        const Divider(color: Colors.white10),
                        _filaInfo("Marca/Modelo:", "${vData['MARCA'] ?? ''} ${vData['MODELO'] ?? ''}", Icons.info_outline, Colors.blueAccent),
                        _filaInfo("Año:", "${vData['AÑO'] ?? vData['ANIO'] ?? 'S/D'}", Icons.calendar_today, Colors.white60),
                        _filaInfo("Empresa:", vData['EMPRESA'] ?? 'S/D', Icons.business, Colors.white60),
                        const Divider(color: Colors.white10, height: 20),
                        _filaInfo("Vencimiento RTO:", AppFormatters.formatearFecha(vData['VENCIMIENTO_RTO']), Icons.fact_check, _getColorVencimiento(vData['VENCIMIENTO_RTO']), onAction: () => _abrirDocumento(vData['ARCHIVO_RTO'], "RTO - $patenteId")),
                        _filaInfo("Póliza Seguro:", AppFormatters.formatearFecha(vData['VENCIMIENTO_SEGURO']), Icons.security, _getColorVencimiento(vData['VENCIMIENTO_SEGURO']), onAction: () => _abrirDocumento(vData['ARCHIVO_SEGURO'], "Seguro - $patenteId")),
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

  Widget _filaInfo(String titulo, String valor, IconData icono, Color color, {VoidCallback? onAction}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icono, size: 14, color: color),
          const SizedBox(width: 10),
          Text(titulo, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const Spacer(),
          Text(valor, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          if (onAction != null) ...[
            const SizedBox(width: 10),
            IconButton(icon: const Icon(Icons.visibility, color: Colors.blueAccent, size: 18), onPressed: onAction, constraints: const BoxConstraints(), padding: EdgeInsets.zero),
          ]
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/preview_screen.dart';

// ✅ MENTOR: StatefulWidget para proteger los Streams y evitar sobrecostos
class UserMiEquipoScreen extends StatefulWidget {
  final String dniUser;

  const UserMiEquipoScreen({super.key, required this.dniUser});

  @override
  State<UserMiEquipoScreen> createState() => _UserMiEquipoScreenState();
}

class _UserMiEquipoScreenState extends State<UserMiEquipoScreen> {
  late final Stream<DocumentSnapshot> _empleadoStream;
  late final Stream<QuerySnapshot> _solicitudesStream;

  @override
  void initState() {
    super.initState();
    // ✅ MENTOR: Ahora el empleado es un Stream. Si el Admin aprueba el cambio, 
    // la pantalla del chofer se actualiza en TIEMPO REAL sin que tenga que salir.
    _empleadoStream = FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dniUser).snapshots();
    
    _solicitudesStream = FirebaseFirestore.instance.collection('REVISIONES')
        .where('dni', isEqualTo: widget.dniUser)
        .where('tipo_solicitud', isEqualTo: 'CAMBIO_EQUIPO')
        .snapshots();
  }

  // --- SELECTOR DE UNIDAD (SOLO MUESTRA LAS "LIBRE") ---
  Future<void> _mostrarSelectorCambio(BuildContext context, String tipo, String patenteActual, String nombreChofer) async {
    String tipoBusqueda = tipo.contains("TRACTOR") ? "TRACTOR" : "";
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent, // ✅ MENTOR: Usamos transparente para inyectar nuestro Surface
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (bContext) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
            border: const Border(top: BorderSide(color: Colors.orangeAccent, width: 2))
          ),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Text("SELECCIONAR NUEVO $tipo", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text("Solo se muestran unidades disponibles (LIBRE)", style: TextStyle(color: Colors.greenAccent, fontSize: 11)),
              ),
              const Divider(color: Colors.white10),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: tipoBusqueda.isNotEmpty 
                    ? FirebaseFirestore.instance.collection('VEHICULOS')
                        .where('TIPO', isEqualTo: tipoBusqueda)
                        .where('ESTADO', isEqualTo: 'LIBRE')
                        .snapshots()
                    : FirebaseFirestore.instance.collection('VEHICULOS')
                        .where('TIPO', whereIn: ['BATEA', 'TOLVA', 'ACOPLADO'])
                        .where('ESTADO', isEqualTo: 'LIBRE')
                        .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.orangeAccent));
                    var unidades = snapshot.data!.docs;

                    if (unidades.isEmpty) {
                      return const Center(child: Text("No hay unidades libres de este tipo.", style: TextStyle(color: Colors.white54)));
                    }

                    return ListView.builder(
                      itemCount: unidades.length,
                      itemBuilder: (context, index) {
                        String patente = unidades[index].id;
                        if (patente == patenteActual) return const SizedBox.shrink();

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              Navigator.pop(context);
                              _enviarSolicitudCambio(context, tipo, patenteActual, patente, nombreChofer);
                            },
                            child: ListTile(
                              leading: const Icon(Icons.check_circle_outline, color: Colors.white38, size: 24),
                              title: Text(patente, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              subtitle: Text("${unidades[index]['MARCA']} ${unidades[index]['MODELO']}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              trailing: const Icon(Icons.add_circle, color: Colors.orangeAccent),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- ENVÍO DE SOLICITUD ---
  Future<void> _enviarSolicitudCambio(BuildContext context, String tipo, String actual, String nueva, String nombre) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      await FirebaseFirestore.instance.collection('REVISIONES').add({
        'dni': widget.dniUser,
        'nombre_usuario': nombre,
        'etiqueta': 'CAMBIO DE ${tipo.contains("TRACTOR") ? "UNIDAD" : "EQUIPO"}',
        'campo': tipo.contains("TRACTOR") ? 'SOLICITUD_VEHICULO' : 'SOLICITUD_ENGANCHE',
        'patente': nueva, 
        'unidad_actual': actual, 
        'fecha_vencimiento': '2026-12-31', 
        'tipo_solicitud': 'CAMBIO_EQUIPO', 
        'coleccion_destino': 'EMPLEADOS',
        'url_archivo': '', 
        'fecha_solicitud': FieldValue.serverTimestamp(),
      });

      messenger.showSnackBar(
        const SnackBar(content: Text("Solicitud enviada. Aguarde aprobación de oficina.", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.orange),
      );
    } catch (e) {
      debugPrint("Error Solicitud: $e");
      messenger.showSnackBar(
        SnackBar(content: Text("Error al enviar solicitud: $e"), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _abrirDocumento(BuildContext context, String? url, String titulo) {
    if (url == null || url.isEmpty || url == "-") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Documento no disponible"), backgroundColor: Colors.orangeAccent),
      );
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (context) => PreviewScreen(url: url, titulo: titulo)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text("Mi Equipo Asignado"), centerTitle: true, backgroundColor: Colors.transparent, elevation: 0),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/fondo_login.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: Theme.of(context).scaffoldBackgroundColor),
            )
          ),
          Positioned.fill(child: Container(color: Colors.black.withAlpha(200))),
          
          SafeArea(
            child: StreamBuilder<DocumentSnapshot>(
              stream: _empleadoStream, // ✅ MENTOR: Stream reactivo
              builder: (context, empleadoSnapshot) {
                if (empleadoSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.orangeAccent));
                if (!empleadoSnapshot.hasData || !empleadoSnapshot.data!.exists) return const Center(child: Text("Error al cargar perfil", style: TextStyle(color: Colors.white)));
                
                var empleadoData = empleadoSnapshot.data!.data() as Map<String, dynamic>;
                String nombreChofer = empleadoData['NOMBRE'] ?? "Chofer";
                String patenteVehiculo = (empleadoData['VEHICULO'] ?? "").toString().trim();
                String patenteEnganche = (empleadoData['ENGANCHE'] ?? "").toString().trim();

                return StreamBuilder<QuerySnapshot>(
                  stream: _solicitudesStream, // ✅ MENTOR: Stream cacheado
                  builder: (context, solicitudesSnapshot) {
                    var solicitudes = solicitudesSnapshot.data?.docs ?? [];
                    
                    return ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        _buildSeccionUnidad(context, "TRACTOR / CHASIS", patenteVehiculo, Icons.local_shipping_outlined, solicitudes, "SOLICITUD_VEHICULO", nombreChofer),
                        const SizedBox(height: 30),
                        _buildSeccionUnidad(context, "ENGANCHE (Batea/Tolva)", patenteEnganche, Icons.grid_view_rounded, solicitudes, "SOLICITUD_ENGANCHE", nombreChofer),
                      ],
                    );
                  }
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionUnidad(BuildContext context, String titulo, String patente, IconData icono, List<QueryDocumentSnapshot> solicitudes, String claveSoli, String nombreChofer) {
    var solicitudPendiente = solicitudes.where((s) {
      var d = s.data() as Map<String, dynamic>;
      return d['campo'] == claveSoli;
    }).toList();

    bool estaVacia = patente.isEmpty || patente == "-" || patente == "SIN ASIGNAR";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(titulo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.greenAccent, letterSpacing: 2)),
            if (!estaVacia && solicitudPendiente.isEmpty)
              TextButton.icon(
                onPressed: () => _mostrarSelectorCambio(context, titulo, patente, nombreChofer),
                icon: const Icon(Icons.swap_horiz, size: 16, color: Colors.orangeAccent),
                label: const Text("SOLICITAR CAMBIO", style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (solicitudPendiente.isNotEmpty)
          _cardBase(
            context: context,
            color: Colors.orangeAccent,
            enRevision: true,
            child: ListTile(
              leading: const Icon(Icons.history_toggle_off, color: Colors.orangeAccent, size: 30),
              title: Text("CAMBIO A ${solicitudPendiente.first['patente']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text("VALIDACIÓN PENDIENTE...", style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
            )
          )
        else if (estaVacia)
          _cardBase(
            context: context,
            color: Colors.white10, 
            child: const ListTile(
              leading: Icon(Icons.info_outline, color: Colors.white24), 
              title: Text("Sin unidad asignada", style: TextStyle(color: Colors.white38, fontSize: 14))
            )
          )
        else
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('VEHICULOS').doc(patente).snapshots(),
            builder: (context, vehiculoSnapshot) {
              if (!vehiculoSnapshot.hasData || !vehiculoSnapshot.data!.exists) return const SizedBox.shrink();
              var v = vehiculoSnapshot.data!.data() as Map<String, dynamic>;
              
              int diasRto = AppFormatters.calcularDiasRestantes(v['VENCIMIENTO_RTO'] ?? "");
              int diasSeg = AppFormatters.calcularDiasRestantes(v['VENCIMIENTO_SEGURO'] ?? "");

              return _cardBase(
                context: context,
                color: Colors.white24,
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      leading: Icon(icono, color: Colors.white70, size: 32),
                      title: Text(patente.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 26, letterSpacing: 2)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text("MARCA: ", style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                Text(v['MARCA'] ?? 'S/D', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Text("MODELO: ", style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                Text(v['MODELO'] ?? 'S/D', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(color: Colors.white10, height: 1),
                    _buildFilaVencimiento(context, "RTO / VTV", v['VENCIMIENTO_RTO'], diasRto, v['ARCHIVO_RTO'], "RTO $patente"),
                    _buildFilaVencimiento(context, "Póliza Seguro", v['VENCIMIENTO_SEGURO'], diasSeg, v['ARCHIVO_SEGURO'], "Seguro $patente"),
                    const SizedBox(height: 12),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildFilaVencimiento(BuildContext context, String etiqueta, String? fecha, int dias, String? url, String tituloDoc) {
    bool tiene = url != null && url.isNotEmpty && url != "-";
    
    Color colorEstado = Colors.blueAccent;
    if (dias < 0) {
      colorEstado = Colors.redAccent;
    } else if (dias <= 14) {
      colorEstado = Colors.orangeAccent;
    } else if (dias <= 30) {
      colorEstado = Colors.greenAccent;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                Text(etiqueta, style: const TextStyle(color: Colors.white54, fontSize: 11)), 
                Text(AppFormatters.formatearFecha(fecha ?? ""), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))
              ]
            )
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(50),
              onTap: () => _abrirDocumento(context, url, tituloDoc),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(Icons.picture_as_pdf_outlined, color: tiene ? Colors.greenAccent : Colors.white12, size: 24),
              ),
            ),
          ),
          const SizedBox(width: 15),
          Container(
            width: 50, 
            padding: const EdgeInsets.symmetric(vertical: 6), 
            decoration: BoxDecoration(
              color: colorEstado.withAlpha(20), 
              borderRadius: BorderRadius.circular(8), 
              border: Border.all(color: colorEstado.withAlpha(80))
            ), 
            child: Center(
              child: Text("${dias}d", style: TextStyle(color: colorEstado, fontWeight: FontWeight.bold, fontSize: 11))
            )
          ),
        ],
      ),
    );
  }

  Widget _cardBase({required BuildContext context, required Widget child, required Color color, bool enRevision = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface, 
        borderRadius: BorderRadius.circular(20), 
        border: Border.all(color: enRevision ? Colors.orangeAccent.withAlpha(150) : Colors.white.withAlpha(20), width: enRevision ? 1.5 : 1)
      ), 
      child: child
    );
  }
}
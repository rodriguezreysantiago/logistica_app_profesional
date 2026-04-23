import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/utils/formatters.dart';
import '../widgets/preview_screen.dart';

class UserMiEquipoScreen extends StatelessWidget {
  final String dniUser;

  const UserMiEquipoScreen({super.key, required this.dniUser});

  // --- SELECTOR DE UNIDAD (SOLO MUESTRA LAS "LIBRE") ---
  Future<void> _mostrarSelectorCambio(BuildContext context, String tipo, String patenteActual, String nombreChofer) async {
    String tipoBusqueda = tipo.contains("TRACTOR") ? "TRACTOR" : "";
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A3A5A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        return Column(
          children: [
            const SizedBox(height: 20),
            Text("SELECCIONAR NUEVO $tipo", style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text("Solo se muestran unidades disponibles (LIBRE)", style: TextStyle(color: Colors.white38, fontSize: 10)),
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
                      .where('TIPO', whereIn: ['BATEA', 'TOLVA'])
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

                      return ListTile(
                        leading: const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 20),
                        title: Text(patente, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text("${unidades[index]['MARCA']} ${unidades[index]['MODELO']}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        trailing: const Icon(Icons.add_circle_outline, color: Colors.orangeAccent),
                        onTap: () {
                          Navigator.pop(context);
                          _enviarSolicitudCambio(context, tipo, patenteActual, patente, nombreChofer);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // --- ENVÍO DE SOLICITUD A "REVISIONES" (UNIFICADO) ---
  Future<void> _enviarSolicitudCambio(BuildContext context, String tipo, String actual, String nueva, String nombre) async {
    try {
      // ✅ Guardamos en REVISIONES para que Ariel lo vea junto con los carnets
      await FirebaseFirestore.instance.collection('REVISIONES').add({
        'dni': dniUser,
        'nombre_usuario': nombre,
        'etiqueta': 'CAMBIO DE ${tipo.contains("TRACTOR") ? "UNIDAD" : "EQUIPO"}',
        'campo': tipo.contains("TRACTOR") ? 'SOLICITUD_VEHICULO' : 'SOLICITUD_ENGANCHE',
        'patente': nueva, // Patente solicitada
        'unidad_actual': actual, // Patente que suelta
        'fecha_vencimiento': '2026-12-31', // Dummy para el orderby
        'tipo_solicitud': 'CAMBIO_EQUIPO', // Flag para el diálogo del admin
        'coleccion_destino': 'EMPLEADOS',
        'url_archivo': '', 
        'fecha_solicitud': FieldValue.serverTimestamp(),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Solicitud enviada. Aguarde aprobación de oficina."), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      debugPrint("Error Solicitud: $e");
    }
  }

  void _abrirDocumento(BuildContext context, String? url, String titulo) {
    if (url == null || url.isEmpty || url == "-") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Documento no disponible"), backgroundColor: Colors.orange),
      );
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (context) => PreviewScreen(url: url, titulo: titulo)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text("Mi Equipo Asignado"), centerTitle: true, backgroundColor: Colors.transparent, elevation: 0, foregroundColor: Colors.white),
      body: Stack(
        children: [
          Positioned.fill(child: Image.asset('assets/images/fondo_login.jpg', fit: BoxFit.cover)),
          Positioned.fill(child: Container(color: Colors.black.withAlpha(220))),
          SafeArea(
            child: FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('EMPLEADOS').doc(dniUser).get(),
              builder: (context, empleadoSnapshot) {
                if (!empleadoSnapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.orangeAccent));
                
                var empleadoData = empleadoSnapshot.data!.data() as Map<String, dynamic>;
                String nombreChofer = empleadoData['NOMBRE'] ?? "Chofer";
                String patenteVehiculo = (empleadoData['VEHICULO'] ?? "").toString().trim();
                String patenteEnganche = (empleadoData['ENGANCHE'] ?? "").toString().trim();

                // ✅ CONSULTAMOS LA COLECCIÓN "REVISIONES" PARA EL RELOJITO
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('REVISIONES')
                      .where('dni', isEqualTo: dniUser)
                      .where('tipo_solicitud', isEqualTo: 'CAMBIO_EQUIPO')
                      .snapshots(),
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
    // Buscamos si existe la revisión pendiente por el campo específico
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
            Text(titulo, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orangeAccent, letterSpacing: 2)),
            if (!estaVacia && solicitudPendiente.isEmpty)
              TextButton.icon(
                onPressed: () => _mostrarSelectorCambio(context, titulo, patente, nombreChofer),
                icon: const Icon(Icons.swap_horiz, size: 14, color: Colors.orangeAccent),
                label: const Text("SOLICITAR CAMBIO", style: TextStyle(color: Colors.orangeAccent, fontSize: 10)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (solicitudPendiente.isNotEmpty)
          _cardBase(
            color: Colors.blueAccent,
            enRevision: true,
            child: ListTile(
              leading: const Icon(Icons.history_toggle_off, color: Colors.blueAccent, size: 30),
              title: Text("CAMBIO A ${solicitudPendiente.first['patente']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text("VALIDACIÓN PENDIENTE...", style: TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold)),
            )
          )
        else if (estaVacia)
          _cardBase(color: Colors.white10, child: const ListTile(leading: Icon(Icons.info_outline, color: Colors.white24), title: Text("Sin unidad asignada", style: TextStyle(color: Colors.white38, fontSize: 14))))
        else
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('VEHICULOS').doc(patente).snapshots(),
            builder: (context, vehiculoSnapshot) {
              if (!vehiculoSnapshot.hasData || !vehiculoSnapshot.data!.exists) return const SizedBox.shrink();
              var v = vehiculoSnapshot.data!.data() as Map<String, dynamic>;
              
              int diasRto = AppFormatters.calcularDiasRestantes(v['VENCIMIENTO_RTO'] ?? "");
              int diasSeg = AppFormatters.calcularDiasRestantes(v['VENCIMIENTO_SEGURO'] ?? "");

              return _cardBase(
                color: Colors.white24,
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      leading: Icon(icono, color: Colors.white, size: 28),
                      title: Text(patente.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24, letterSpacing: 2)),
                      subtitle: Column(
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
    
    Color colorEstado;
    if (dias < 0) { colorEstado = Colors.red; } 
    else if (dias <= 14) { colorEstado = Colors.orange; } 
    else if (dias <= 30) { colorEstado = Colors.greenAccent; } 
    else { colorEstado = Colors.blueAccent; }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(etiqueta, style: const TextStyle(color: Colors.white60, fontSize: 10)), Text(AppFormatters.formatearFecha(fecha ?? ""), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))])),
          IconButton(onPressed: () => _abrirDocumento(context, url, tituloDoc), icon: Icon(Icons.picture_as_pdf_outlined, color: tiene ? Colors.blueAccent : Colors.white12, size: 22)),
          const SizedBox(width: 10),
          Container(width: 45, padding: const EdgeInsets.symmetric(vertical: 4), decoration: BoxDecoration(color: colorEstado.withAlpha(30), borderRadius: BorderRadius.circular(6), border: Border.all(color: colorEstado.withAlpha(80))), child: Center(child: Text("${dias}d", style: TextStyle(color: colorEstado, fontWeight: FontWeight.bold, fontSize: 10)))),
        ],
      ),
    );
  }

  Widget _cardBase({required Widget child, required Color color, bool enRevision = false}) {
    return Container(
      decoration: BoxDecoration(
        color: enRevision ? Colors.blue.withAlpha(30) : Colors.white.withAlpha(15), 
        borderRadius: BorderRadius.circular(20), 
        border: Border.all(color: color.withAlpha(100), width: enRevision ? 1.5 : 0.8)
      ), 
      child: child
    );
  }
}
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/utils/formatters.dart';

class AdminPersonalListaScreen extends StatefulWidget {
  const AdminPersonalListaScreen({super.key});

  @override
  State<AdminPersonalListaScreen> createState() => _AdminPersonalListaScreenState();
}

class _AdminPersonalListaScreenState extends State<AdminPersonalListaScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = "";

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchText = _searchController.text.toUpperCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gestión de Personal"),
        backgroundColor: const Color(0xFF1A3A5A),
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Buscar por nombre...",
                prefixIcon: const Icon(Icons.search),
                fillColor: Colors.white,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('EMPLEADOS')
            .orderBy('CHOFER')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text("Error al cargar datos"));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final empleados = snapshot.data!.docs.where((doc) {
            final nombre = (doc['CHOFER'] as String? ?? '').toUpperCase();
            return nombre.contains(_searchText);
          }).toList();

          return ListView.builder(
            itemCount: empleados.length,
            padding: const EdgeInsets.all(10),
            itemBuilder: (context, index) {
              var data = empleados[index].data() as Map<String, dynamic>;
              String dni = empleados[index].id;

              return Card(
                elevation: 2,
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF1A3A5A),
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  title: Text(
                    data['CHOFER'] ?? 'Sin nombre',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    "Tractor: ${data['TRACTOR'] ?? 'S/T'} | Batea: ${data['BATEA_TOLVA'] ?? 'S/B'}",
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => _mostrarDetalleChofer(context, dni, data),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _mostrarDetalleChofer(BuildContext context, String dni, Map<String, dynamic> chofer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // ENCABEZADO CON NOMBRE Y DNI
                  Text(
                    chofer['CHOFER'] ?? "Sin Nombre",
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "DNI: $dni | CUIL: ${chofer['CUIL'] ?? 'N/A'}",
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const Divider(height: 30),

                  // SECCIÓN: DATOS DE CONTACTO Y EMPRESA
                  _buildSeccionTitulo(Icons.business_center, "Información Laboral"),
                  _buildDatoSimple("Empresa", chofer['EMPRESA']),
                  _buildDatoSimple("Teléfono", chofer['TELEFONO']),
                  _buildDatoSimple("Rol", chofer['ROL']),

                  const SizedBox(height: 20),

                  // SECCIÓN: VENCIMIENTOS PERSONALES
                  _buildSeccionTitulo(Icons.badge, "Documentación Chofer"),
                  _buildDatoVencimiento("Licencia Conducir", chofer['LIC_COND']),
                  _buildDatoVencimiento("Curso Manejo", chofer['CURSO_MANEJO']),
                  _buildDatoVencimiento("EPAP", chofer['EPAP']),

                  const Divider(height: 40),

                  // SECCIÓN: TRACTOR ASIGNADO
                  _buildSeccionTitulo(Icons.local_shipping, "Tractor: ${chofer['TRACTOR'] ?? 'No asignado'}"),
                  if (chofer['TRACTOR'] != null && chofer['TRACTOR'].toString().isNotEmpty)
                    _buildStreamVehiculo(chofer['TRACTOR'])
                  else
                    const Text("Sin tractor asignado.", 
                        style: TextStyle(color: Colors.orange, fontStyle: FontStyle.italic)),

                  const SizedBox(height: 20),

                  // SECCIÓN: BATEA / TOLVA ASIGNADA
                  _buildSeccionTitulo(Icons.ad_units, "Batea/Tolva: ${chofer['BATEA_TOLVA'] ?? 'No asignada'}"),
                  if (chofer['BATEA_TOLVA'] != null && chofer['BATEA_TOLVA'].toString().isNotEmpty)
                    _buildStreamVehiculo(chofer['BATEA_TOLVA'])
                  else
                    const Text("Sin acoplado asignado.", 
                        style: TextStyle(color: Colors.orange, fontStyle: FontStyle.italic)),

                  const SizedBox(height: 30),
                  
                  // BOTÓN DE ACCIÓN PRINCIPAL
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.edit),
                      label: const Text("MODIFICAR FICHA COMPLETA"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A3A5A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStreamVehiculo(String patente) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('VEHICULOS').doc(patente).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Text("⚠️ No se encontró la unidad $patente en VEHICULOS.", 
                      style: const TextStyle(color: Colors.red, fontSize: 12));
        }
        var vData = snapshot.data!.data() as Map<String, dynamic>;
        return Column(
          children: [
            _buildDatoVencimiento("Vencimiento RTO", vData['VENCIMIENTO_RTO']),
            _buildDatoVencimiento("Vencimiento Póliza", vData['VENCIMIENTO_POLIZA']),
          ],
        );
      },
    );
  }

  Widget _buildSeccionTitulo(IconData icono, String titulo) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icono, color: const Color(0xFF1A3A5A), size: 20),
          const SizedBox(width: 10),
          Text(
            titulo,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A3A5A)),
          ),
        ],
      ),
    );
  }

  Widget _buildDatoVencimiento(String etiqueta, String? fecha) {
    if (fecha == null || fecha.isEmpty) return _buildDatoSimple(etiqueta, "No cargado");
    int dias = AppFormatters.calcularDiasRestantes(fecha);
    Color colorSemaforo = dias < 0 ? Colors.red : (dias <= 30 ? Colors.orange : Colors.green);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta, style: const TextStyle(color: Colors.black87, fontSize: 13)),
          Row(
            children: [
              Text(AppFormatters.formatearFecha(fecha), 
                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: colorSemaforo, borderRadius: BorderRadius.circular(4)),
                child: Text(
                  "${dias}d",
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDatoSimple(String etiqueta, String? valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta, style: const TextStyle(color: Colors.black87, fontSize: 13)),
          Text(
            valor ?? "N/A",
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Colors.blueGrey),
          ),
        ],
      ),
    );
  }
}
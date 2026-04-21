import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../core/utils/formatters.dart';

class AdminVencimientosChasisScreen extends StatelessWidget {
  const AdminVencimientosChasisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Gestión Chasis / Tractores"),
        centerTitle: true,
        backgroundColor: const Color(0xFF1A3A5A).withAlpha(220),
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/fondo_login.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: const Color(0xFF0D1D2D)),
            ),
          ),
          Container(color: const Color(0xFF1A3A5A).withAlpha(130)),
          SafeArea(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('VEHICULOS').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.orangeAccent));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                      child: Text("No hay datos de vehículos registrados.", style: TextStyle(color: Colors.white70)));
                }

                List<Map<String, dynamic>> alertasChasis = [];

                for (var doc in snapshot.data!.docs) {
                  var data = doc.data() as Map<String, dynamic>;
                  String patente = doc.id.toUpperCase(); 
                  String tipoVehiculo = (data['TIPO'] ?? "").toString().toUpperCase();

                  // FILTRO: Solo Tractores o Chasis
                  if (tipoVehiculo == "CHASIS" || tipoVehiculo == "TRACTOR") {
                    
                    // Verificamos RTO
                    _verificarVencimiento(alertasChasis, patente, tipoVehiculo, "RTO", 
                        "RTO", data['VENCIMIENTO_RTO'], data['ARCHIVO_RTO']);

                    // Verificamos Seguro
                    _verificarVencimiento(alertasChasis, patente, tipoVehiculo, "Seguro", 
                        "SEGURO", data['VENCIMIENTO_SEGURO'], data['ARCHIVO_SEGURO']);
                  }
                }

                // MOSTRAR: Lo vencido y lo que vence en los próximos 60 días
                alertasChasis = alertasChasis.where((item) => item['dias'] <= 60).toList();
                alertasChasis.sort((a, b) => a['dias'].compareTo(b['dias']));

                if (alertasChasis.isEmpty) {
                  return const Center(
                      child: Text("Sin vencimientos próximos en tractores", style: TextStyle(color: Colors.white70)));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  itemCount: alertasChasis.length,
                  itemBuilder: (context, index) {
                    final item = alertasChasis[index];
                    int d = item['dias'];

                    // SEMÁFORO UNIFICADO S.M.A.R.T.
                    Color colorSemaforo;
                    if (d < 0) {
                      colorSemaforo = Colors.red;
                    } else if (d <= 14) {
                      colorSemaforo = Colors.orange;
                    } else if (d <= 30) {
                      colorSemaforo = Colors.greenAccent;
                    } else {
                      colorSemaforo = Colors.blueAccent;
                    }

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(25),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: colorSemaforo.withAlpha(100),
                          width: d <= 14 ? 2 : 1,
                        ),
                      ),
                      child: ListTile(
                        onTap: () => _abrirEditorVehiculo(context, item),
                        leading: CircleAvatar(
                          backgroundColor: colorSemaforo.withAlpha(50),
                          child: Text("${item['dias']}d", 
                            style: TextStyle(
                              color: d <= 14 && d >= 0 ? Colors.orange : colorSemaforo, 
                              fontWeight: FontWeight.bold, 
                              fontSize: 10
                            )
                          ),
                        ),
                        title: Text("${item['tipo_v']} - ${item['patente']}", 
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)),
                        subtitle: Text(
                          "${item['doc_nombre']}: ${AppFormatters.formatearFecha(item['fecha'])}",
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        trailing: const Icon(Icons.edit_calendar, color: Colors.orangeAccent, size: 20),
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
  }

  void _verificarVencimiento(List<Map<String, dynamic>> lista, String patente, String tipoV, String nombreDoc, String campoBase, String? fecha, String? foto) {
    if (fecha == null || fecha.isEmpty) return;
    int diasRestantes = AppFormatters.calcularDiasRestantes(fecha);
    lista.add({
      'patente': patente,
      'tipo_v': tipoV,
      'doc_nombre': nombreDoc,
      'campo_base': campoBase, 
      'fecha': fecha,
      'dias': diasRestantes,
      'foto': foto,
    });
  }

  Future<String?> _subirArchivoVehiculo(String patente, String campo, File archivo) async {
    try {
      String extension = archivo.path.split('.').last;
      String nombreArchivo = "${patente}_ADMIN_UPDATE_${campo}_${DateTime.now().millisecondsSinceEpoch}.$extension";
      // Usamos la carpeta VEHICULOS_DOCS para auditoría de flota
      Reference ref = FirebaseStorage.instance.ref().child('VEHICULOS_DOCS/$nombreArchivo');
      await ref.putFile(archivo);
      return await ref.getDownloadURL();
    } catch (e) {
      return null;
    }
  }

  void _abrirEditorVehiculo(BuildContext context, Map<String, dynamic> item) {
    DateTime fechaSeleccionada = DateTime.tryParse(item['fecha']) ?? DateTime.now();
    File? archivoSeleccionado;
    bool subiendo = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D1D2D),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (bContext) => StatefulBuilder(
        builder: (stContext, setState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(stContext).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Actualizar ${item['doc_nombre']}", 
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              Text("${item['tipo_v']} - ${item['patente']}", style: const TextStyle(color: Colors.white54)),
              const Divider(color: Colors.white12, height: 25),
              
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Nueva Fecha de Vencimiento", style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: Text(AppFormatters.formatearFecha(fechaSeleccionada.toString().split(' ')[0]),
                  style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                trailing: const Icon(Icons.edit_calendar_outlined, color: Colors.blueAccent),
                onTap: () async {
                  DateTime? picker = await showDatePicker(
                    context: stContext,
                    initialDate: fechaSeleccionada,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2040),
                  );
                  if (picker != null) setState(() => fechaSeleccionada = picker);
                },
              ),
              const SizedBox(height: 10),
              
              InkWell(
                onTap: () async {
                  FilePickerResult? result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['jpg', 'pdf', 'png', 'jpeg'],
                  );
                  if (result != null) setState(() => archivoSeleccionado = File(result.files.single.path!));
                },
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(10), 
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: archivoSeleccionado == null ? Colors.white12 : Colors.greenAccent)
                  ),
                  child: Row(
                    children: [
                      Icon(archivoSeleccionado == null ? Icons.file_upload_outlined : Icons.check_circle_outline, 
                           color: archivoSeleccionado == null ? Colors.white38 : Colors.greenAccent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          archivoSeleccionado == null ? "Cargar comprobante nuevo" : "Archivo adjuntado correctamente",
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        )
                      ),
                      if (archivoSeleccionado == null) const Icon(Icons.add_a_photo_outlined, color: Colors.blueAccent, size: 20)
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 30),
              if (subiendo) 
                const CircularProgressIndicator(color: Colors.orangeAccent)
              else
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(stContext), 
                        child: const Text("CANCELAR", style: TextStyle(color: Colors.white54))
                      )
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                        onPressed: () async {
                          setState(() => subiendo = true);
                          
                          String? urlFinal = item['foto'];
                          if (archivoSeleccionado != null) {
                            urlFinal = await _subirArchivoVehiculo(item['patente'], item['campo_base'], archivoSeleccionado!);
                          }
                          
                          String fechaString = fechaSeleccionada.toString().split(' ')[0];
                          
                          // ACTUALIZACIÓN SIGUIENDO LA LÓGICA DE PARES VENCIMIENTO/ARCHIVO
                          await FirebaseFirestore.instance.collection('VEHICULOS').doc(item['patente']).update({
                            "VENCIMIENTO_${item['campo_base']}": fechaString,
                            "ARCHIVO_${item['campo_base']}": urlFinal,
                            "ultima_modificacion_admin": FieldValue.serverTimestamp(),
                          });
                          
                          if (stContext.mounted) Navigator.pop(stContext);
                        },
                        child: const Text("GUARDAR"),
                      ),
                    ),
                  ],
                )
            ],
          ),
        ),
      ),
    );
  }
}
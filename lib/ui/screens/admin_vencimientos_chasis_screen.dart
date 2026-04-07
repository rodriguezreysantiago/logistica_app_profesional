import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart'; // <--- YA NO SERÁ UNUSED
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import '../../core/utils/formatters.dart';

class AdminVencimientosChasisScreen extends StatelessWidget {
  const AdminVencimientosChasisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gestión Chasis (60 días)"),
        backgroundColor: const Color(0xFF1A3A5A),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('VEHICULOS').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No hay datos de vehículos."));
          }

          List<Map<String, dynamic>> alertasChasis = [];

          for (var doc in snapshot.data!.docs) {
            var data = doc.data() as Map<String, dynamic>;
            String patente = doc.id;
            String tipoVehiculo = (data['TIPO'] ?? "").toString().toUpperCase();

            if (tipoVehiculo == "CHASIS" || tipoVehiculo == "TRACTOR") {
              _verificarVencimiento(alertasChasis, patente, tipoVehiculo, "RTO", 
                  "VENCIMIENTO_RTO", data['VENCIMIENTO_RTO'], data['FOTO_VENCIMIENTO_RTO']);

              _verificarVencimiento(alertasChasis, patente, tipoVehiculo, "Póliza", 
                  "VENCIMIENTO_POLIZA", data['VENCIMIENTO_POLIZA'], data['FOTO_VENCIMIENTO_POLIZA']);
            }
          }

          alertasChasis = alertasChasis.where((item) => item['dias'] <= 60).toList();
          alertasChasis.sort((a, b) => a['dias'].compareTo(b['dias']));

          if (alertasChasis.isEmpty) {
            return const Center(child: Text("Sin vencimientos próximos (60 días)"));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: alertasChasis.length,
            itemBuilder: (context, index) {
              final item = alertasChasis[index];
              
              // SEMÁFORO DE COLORES
              Color colorSemaforo;
              if (item['dias'] < 0) {
                colorSemaforo = Colors.red;
              } else if (item['dias'] <= 30) {
                colorSemaforo = Colors.orange;
              } else {
                colorSemaforo = Colors.green;
              }

              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: colorSemaforo.withValues(alpha: 0.5), width: 1.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  onTap: () => _abrirEditorVehiculo(context, item),
                  leading: CircleAvatar(
                    backgroundColor: colorSemaforo.withValues(alpha: 0.1),
                    child: Text("${item['dias']}d", 
                      style: TextStyle(color: colorSemaforo, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                  title: Text("${item['tipo_v']} - ${item['patente']}", 
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text("${item['doc_nombre']}: ${AppFormatters.formatearFecha(item['fecha'])}"),
                  trailing: const Icon(Icons.edit_square, color: Colors.blue, size: 20),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _verificarVencimiento(List<Map<String, dynamic>> lista, String patente, String tipoV, String nombreDoc, String campoTecnico, String? fecha, String? foto) {
    if (fecha == null || fecha.isEmpty) return;
    int diasRestantes = AppFormatters.calcularDiasRestantes(fecha);
    lista.add({
      'patente': patente,
      'tipo_v': tipoV,
      'doc_nombre': nombreDoc,
      'campo': campoTecnico,
      'fecha': fecha,
      'dias': diasRestantes,
      'foto': foto,
    });
  }

  Future<String?> _subirArchivoVehiculo(String patente, String campo, File archivo) async {
    try {
      String extension = archivo.path.split('.').last;
      Reference ref = FirebaseStorage.instance.ref().child('documentacion_vehiculos/$patente/$campo.$extension');
      UploadTask uploadTask = ref.putFile(archivo);
      TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      return null;
    }
  }

  void _abrirEditorVehiculo(BuildContext context, Map<String, dynamic> item) {
    DateTime fechaSeleccionada = DateTime.parse(item['fecha']);
    File? archivoSeleccionado;
    bool subiendo = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Actualizar ${item['doc_nombre']}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text("${item['tipo_v']} - ${item['patente']}", style: const TextStyle(color: Colors.grey)),
              const Divider(),
              ListTile(
                title: const Text("Fecha Vencimiento"),
                subtitle: Text(AppFormatters.formatearFecha(fechaSeleccionada.toString().split(' ')[0])),
                trailing: const Icon(Icons.calendar_month, color: Colors.blue),
                onTap: () async {
                  DateTime? picker = await showDatePicker(
                    context: context,
                    initialDate: fechaSeleccionada,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picker != null) setState(() => fechaSeleccionada = picker);
                },
              ),
              const SizedBox(height: 10),
              
              // SECCIÓN DE ARCHIVO (Usa FilePicker aquí)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    Icon(archivoSeleccionado == null ? Icons.upload_file : Icons.check_circle, 
                         color: archivoSeleccionado == null ? Colors.blueGrey : Colors.green),
                    const SizedBox(width: 12),
                    Expanded(child: Text(archivoSeleccionado == null ? "Adjuntar PDF o Foto" : "Archivo listo")),
                    IconButton(
                      icon: const Icon(Icons.add_a_photo_outlined, color: Colors.blue),
                      onPressed: () async {
                        FilePickerResult? result = await FilePicker.platform.pickFiles();
                        if (result != null) setState(() => archivoSeleccionado = File(result.files.single.path!));
                      },
                    )
                  ],
                ),
              ),

              const SizedBox(height: 25),
              if (subiendo) 
                const CircularProgressIndicator()
              else
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR"))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                        onPressed: () async {
                          setState(() => subiendo = true);
                          String? urlFinal = item['foto'];
                          if (archivoSeleccionado != null) {
                            urlFinal = await _subirArchivoVehiculo(item['patente'], item['campo'], archivoSeleccionado!);
                          }
                          String fechaString = fechaSeleccionada.toString().split(' ')[0];
                          await FirebaseFirestore.instance.collection('VEHICULOS').doc(item['patente']).update({
                            item['campo']: fechaString,
                            "FOTO_${item['campo']}": urlFinal,
                          });
                          if (context.mounted) Navigator.pop(context);
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
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart'; 
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import '../../core/utils/formatters.dart';

class AdminVencimientosChoferesScreen extends StatelessWidget {
  const AdminVencimientosChoferesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gestión: Vencimientos (60 días)"),
        backgroundColor: const Color(0xFF1A3A5A),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('EMPLEADOS').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          List<Map<String, dynamic>> criticos = [];

          for (var doc in snapshot.data!.docs) {
            var data = doc.data() as Map<String, dynamic>;
            String nombre = data['CHOFER'] ?? "Sin Nombre";
            String dni = doc.id;
            
            _revisarFecha(criticos, dni, nombre, "Licencia", "LIC_COND", data['LIC_COND'], data['FOTO_LIC_COND']);
            _revisarFecha(criticos, dni, nombre, "EPAP", "EPAP", data['EPAP'], data['FOTO_EPAP']);
            _revisarFecha(criticos, dni, nombre, "Manejo", "CURSO_MANEJO", data['CURSO_MANEJO'], data['FOTO_CURSO_MANEJO']);
          }

          // Filtro a 60 días
          criticos = criticos.where((item) => item['dias'] <= 60).toList();
          criticos.sort((a, b) => a['dias'].compareTo(b['dias']));

          if (criticos.isEmpty) {
            return const Center(child: Text("No hay vencimientos en los próximos 60 días"));
          }

          return ListView.builder(
            itemCount: criticos.length,
            itemBuilder: (context, index) {
              final item = criticos[index];
              
              // LÓGICA DE COLORES SEMÁFORO
              Color colorSemaforo;
              if (item['dias'] < 0) {
                colorSemaforo = Colors.red;      // Vencido
              } else if (item['dias'] <= 30) {
                colorSemaforo = Colors.orange;   // 0 a 30 días
              } else {
                colorSemaforo = Colors.green;    // 31 a 60 días
              }

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: colorSemaforo.withValues(alpha: 0.5), width: 1.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListTile(
                  onTap: () => _abrirEditorDirecto(context, item),
                  leading: CircleAvatar(
                    backgroundColor: colorSemaforo.withValues(alpha: 0.1),
                    child: Text("${item['dias']}d", 
                      style: TextStyle(color: colorSemaforo, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(item['usuario'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text("${item['tipo']}: ${AppFormatters.formatearFecha(item['fecha'])}"),
                  trailing: const Icon(Icons.edit_note, size: 22, color: Colors.blue),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _revisarFecha(List<Map<String, dynamic>> lista, String dni, String usuario, String tipo, String campoTecnico, String? fecha, String? foto) {
    if (fecha == null || fecha.isEmpty) return;
    int dias = AppFormatters.calcularDiasRestantes(fecha);
    lista.add({
      'dni': dni,
      'usuario': usuario,
      'tipo': tipo,
      'campo': campoTecnico,
      'fecha': fecha,
      'dias': dias,
      'foto': foto
    });
  }

  Future<String?> _subirArchivo(String dni, String campo, File archivo) async {
    try {
      String extension = archivo.path.split('.').last;
      Reference ref = FirebaseStorage.instance.ref().child('documentacion/$dni/$campo.$extension');
      UploadTask uploadTask = ref.putFile(archivo);
      TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      return null;
    }
  }

  void _abrirEditorDirecto(BuildContext context, Map<String, dynamic> item) {
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
              Text("Editar ${item['tipo']}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(item['usuario'], style: const TextStyle(color: Colors.grey)),
              const Divider(),
              
              ListTile(
                title: const Text("Fecha de Vencimiento"),
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
              
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    Icon(archivoSeleccionado == null ? Icons.attach_file : Icons.check_circle, 
                         color: archivoSeleccionado == null ? Colors.blueGrey : Colors.green),
                    const SizedBox(width: 10),
                    Expanded(child: Text(archivoSeleccionado == null ? "Sin archivo seleccionado" : "Archivo adjunto")),
                    IconButton(
                      icon: const Icon(Icons.add_photo_alternate_outlined, color: Colors.blue),
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
                            urlFinal = await _subirArchivo(item['dni'], item['campo'], archivoSeleccionado!);
                          }
                          String fechaString = fechaSeleccionada.toString().split(' ')[0];
                          await FirebaseFirestore.instance.collection('EMPLEADOS').doc(item['dni']).update({
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
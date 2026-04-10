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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Gestión: Vencimientos (60 días)"),
        centerTitle: true,
        backgroundColor: Colors.transparent,
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
                  Container(color: Colors.blueGrey.shade900),
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.65),
            ),
          ),
          SafeArea(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('EMPLEADOS').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.orangeAccent));
                }
                
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text("No hay datos de empleados", style: TextStyle(color: Colors.white70))
                  );
                }

                List<Map<String, dynamic>> criticos = [];

                for (var doc in snapshot.data!.docs) {
                  var data = doc.data() as Map<String, dynamic>;
                  String nombre = data['CHOFER'] ?? "Sin Nombre";
                  String dni = doc.id;
                  
                  // AJUSTE DE CAMPOS SEGÚN TU FIREBASE
                  _revisarFecha(criticos, dni, nombre, "Licencia", "LICENCIA_DE_CONDUCIR", data['VENCIMIENTO_LICENCIA_DE_CONDUCIR'], data['ARCHIVO_LICENCIA_DE_CONDUCIR']);
                  _revisarFecha(criticos, dni, nombre, "Psicofísico", "PSICOFISICO", data['VENCIMIENTO_PSICOFISICO'], data['ARCHIVO_PSICOFISICO']);
                  _revisarFecha(criticos, dni, nombre, "Manejo Defensivo", "CURSO_DE_MANEJO_DEFENSIVO", data['VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO'], data['ARCHIVO_CURSO_DE_MANEJO_DEFENSIVO']);
                }

                criticos = criticos.where((item) => item['dias'] <= 60).toList();
                criticos.sort((a, b) => a['dias'].compareTo(b['dias']));

                if (criticos.isEmpty) {
                  return const Center(
                    child: Text("Sin vencimientos próximos", style: TextStyle(color: Colors.white70))
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  itemCount: criticos.length,
                  itemBuilder: (context, index) {
                    final item = criticos[index];
                    
                    Color colorSemaforo = item['dias'] < 0 
                        ? Colors.redAccent 
                        : (item['dias'] <= 30 ? Colors.orangeAccent : Colors.greenAccent);

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: colorSemaforo.withValues(alpha: 0.3), width: 1),
                      ),
                      child: ListTile(
                        onTap: () => _abrirEditorDirecto(context, item),
                        leading: CircleAvatar(
                          backgroundColor: colorSemaforo.withValues(alpha: 0.15),
                          child: Text("${item['dias']}d", 
                            style: TextStyle(color: colorSemaforo, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(item['usuario'], 
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text(
                          "${item['tipo']}: ${AppFormatters.formatearFecha(item['fecha'])}",
                          style: const TextStyle(color: Colors.white70),
                        ),
                        trailing: const Icon(Icons.edit_note, color: Colors.blueAccent, size: 24),
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

  void _revisarFecha(List<Map<String, dynamic>> lista, String dni, String usuario, String tipo, String campoBase, String? fecha, String? foto) {
    if (fecha == null || fecha.isEmpty) return;
    int dias = AppFormatters.calcularDiasRestantes(fecha);
    lista.add({
      'dni': dni,
      'usuario': usuario,
      'tipo': tipo,
      'campo_base': campoBase, // Ejemplo: LICENCIA_DE_CONDUCIR
      'fecha': fecha,
      'dias': dias,
      'foto': foto
    });
  }

  // Subida a Storage respetando la estructura de carpetas
  Future<String?> _subirArchivo(String dni, String campo, File archivo) async {
    try {
      String extension = archivo.path.split('.').last;
      String nombreArchivo = "${dni}_VENCIMIENTO_${campo}_${DateTime.now().millisecondsSinceEpoch}.$extension";
      
      // Subimos a la carpeta REVISIONES como se ve en tu token de Firebase
      Reference ref = FirebaseStorage.instance.ref().child('REVISIONES/$nombreArchivo');
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
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Editar ${item['tipo']}", 
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              Text(item['usuario'], style: const TextStyle(color: Colors.white54)),
              const Divider(color: Colors.white12, height: 25),
              
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Fecha de Vencimiento", style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  AppFormatters.formatearFecha(fechaSeleccionada.toString().split(' ')[0]),
                  style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold),
                ),
                trailing: const Icon(Icons.calendar_month, color: Colors.blueAccent),
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
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05), 
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.white10)
                ),
                child: Row(
                  children: [
                    Icon(archivoSeleccionado == null ? Icons.attach_file : Icons.check_circle, 
                         color: archivoSeleccionado == null ? Colors.white38 : Colors.greenAccent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        archivoSeleccionado == null ? "Sin archivo seleccionado" : "Archivo adjunto listo",
                        style: const TextStyle(color: Colors.white70),
                      )
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_photo_alternate_outlined, color: Colors.blueAccent),
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
                const CircularProgressIndicator(color: Colors.orangeAccent)
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70, 
                          side: const BorderSide(color: Colors.white24)
                        ),
                        onPressed: () => Navigator.pop(context), 
                        child: const Text("CANCELAR")
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
                            urlFinal = await _subirArchivo(item['dni'], item['campo_base'], archivoSeleccionado!);
                          }
                          
                          String fechaString = fechaSeleccionada.toString().split(' ')[0];
                          
                          // ACTUALIZACIÓN CON LOS NOMBRES DE TU FIREBASE
                          await FirebaseFirestore.instance.collection('EMPLEADOS').doc(item['dni']).update({
                            "VENCIMIENTO_${item['campo_base']}": fechaString,
                            "ARCHIVO_${item['campo_base']}": urlFinal,
                            "ultima_revision": FieldValue.serverTimestamp(), // Para actualizar la fecha de revisión
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
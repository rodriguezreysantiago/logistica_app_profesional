import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../core/utils/formatters.dart';

class AdminVencimientosChoferesScreen extends StatelessWidget {
  const AdminVencimientosChoferesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Auditoría: Personal (60 días)"),
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
              stream: FirebaseFirestore.instance.collection('EMPLEADOS').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.orangeAccent));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                      child: Text("No hay datos de empleados registrados.",
                          style: TextStyle(color: Colors.white70)));
                }

                List<Map<String, dynamic>> criticos = [];

                for (var doc in snapshot.data!.docs) {
                  var data = doc.data() as Map<String, dynamic>;
                  String nombre = data['NOMBRE'] ?? "Sin Nombre";
                  String dni = doc.id.trim();

                  // --- DOCUMENTACIÓN PERSONAL (Pares VENCIMIENTO / ARCHIVO) ---
                  _revisarFecha(criticos, dni, nombre, "Licencia", "LICENCIA_DE_CONDUCIR",
                      data['VENCIMIENTO_LICENCIA_DE_CONDUCIR'], data['ARCHIVO_LICENCIA_DE_CONDUCIR']);
                  
                  _revisarFecha(criticos, dni, nombre, "Psicofísico", "PSICOFISICO",
                      data['VENCIMIENTO_PSICOFISICO'], data['ARCHIVO_PSICOFISICO']);
                  
                  _revisarFecha(criticos, dni, nombre, "Manejo Defensivo", "CURSO_DE_MANEJO_DEFENSIVO",
                      data['VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO'], data['ARCHIVO_CURSO_DE_MANEJO_DEFENSIVO']);

                  // --- DOCUMENTACIÓN LABORAL ---
                  _revisarFecha(criticos, dni, nombre, "ART", "ART",
                      data['VENCIMIENTO_ART'], data['ARCHIVO_ART']);
                  
                  _revisarFecha(criticos, dni, nombre, "F. 931", "931",
                      data['VENCIMIENTO_931'], data['ARCHIVO_931']);
                  
                  _revisarFecha(criticos, dni, nombre, "Seguro de Vida", "SEGURO_DE_VIDA",
                      data['VENCIMIENTO_SEGURO_DE_VIDA'], data['ARCHIVO_SEGURO_DE_VIDA']);
                  
                  _revisarFecha(criticos, dni, nombre, "Sindicato", "LIBRE_DE_DEUDA_SINDICAL",
                      data['VENCIMIENTO_LIBRE_DE_DEUDA_SINDICAL'], data['ARCHIVO_LIBRE_DE_DEUDA_SINDICAL']);
                }

                // Filtrar por 60 días y ordenar por urgencia
                criticos = criticos.where((item) => item['dias'] <= 60).toList();
                criticos.sort((a, b) => a['dias'].compareTo(b['dias']));

                if (criticos.isEmpty) {
                  return const Center(
                      child: Text("Personal con documentación al día",
                          style: TextStyle(color: Colors.white70)));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  itemCount: criticos.length,
                  itemBuilder: (context, index) {
                    final item = criticos[index];
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
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(25),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: colorSemaforo.withAlpha(80), width: d <= 14 ? 1.5 : 0.5),
                      ),
                      child: ListTile(
                        onTap: () => _abrirEditorDirecto(context, item),
                        leading: CircleAvatar(
                          backgroundColor: colorSemaforo.withAlpha(40),
                          child: Text("${item['dias']}d",
                              style: TextStyle(
                                  color: d <= 14 && d >= 0 ? Colors.orange : colorSemaforo,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ),
                        title: Text(item['usuario'],
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text(
                          "${item['tipo']}: ${AppFormatters.formatearFecha(item['fecha'])}",
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

  void _revisarFecha(List<Map<String, dynamic>> lista, String dni, String usuario, String tipo,
      String campoBase, String? fecha, String? foto) {
    if (fecha == null || fecha.isEmpty) return;
    int dias = AppFormatters.calcularDiasRestantes(fecha);
    lista.add({
      'dni': dni,
      'usuario': usuario,
      'tipo': tipo,
      'campo_base': campoBase,
      'fecha': fecha,
      'dias': dias,
      'foto': foto
    });
  }

  Future<String?> _subirArchivo(String dni, String campo, File archivo) async {
    try {
      String extension = archivo.path.split('.').last;
      String nombreArchivo = "${dni}_ADMIN_AUDIT_${campo}_${DateTime.now().millisecondsSinceEpoch}.$extension";
      Reference ref = FirebaseStorage.instance.ref().child('EMPLEADOS_DOCS/$nombreArchivo');
      await ref.putFile(archivo);
      return await ref.getDownloadURL();
    } catch (e) {
      return null;
    }
  }

  void _abrirEditorDirecto(BuildContext context, Map<String, dynamic> item) {
    DateTime fechaSeleccionada = DateTime.tryParse(item['fecha']) ?? DateTime.now();
    File? archivoSeleccionado;
    bool subiendo = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D1D2D),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (bContext) => StatefulBuilder(
        builder: (stContext, setState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(stContext).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Actualizar ${item['tipo']}",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              Text(item['usuario'], style: const TextStyle(color: Colors.white54)),
              const Divider(color: Colors.white12, height: 25),
              
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Fecha de Vencimiento", style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: Text(
                  AppFormatters.formatearFecha(fechaSeleccionada.toString().split(' ')[0]),
                  style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                trailing: const Icon(Icons.calendar_month, color: Colors.blueAccent),
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
                  if (result != null) {
                    setState(() => archivoSeleccionado = File(result.files.single.path!));
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                      color: Colors.white.withAlpha(10),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: archivoSeleccionado == null ? Colors.white12 : Colors.greenAccent)),
                  child: Row(
                    children: [
                      Icon(archivoSeleccionado == null ? Icons.upload_file : Icons.check_circle,
                          color: archivoSeleccionado == null ? Colors.white38 : Colors.greenAccent),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(
                        archivoSeleccionado == null ? "Cargar comprobante nuevo" : "Archivo adjuntado correctamente",
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      )),
                      const Icon(Icons.add_a_photo_outlined, color: Colors.blueAccent, size: 20)
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
                          child: const Text("CANCELAR", style: TextStyle(color: Colors.white54))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green, foregroundColor: Colors.white),
                        onPressed: () async {
                          setState(() => subiendo = true);
                          
                          String? urlFinal = item['foto'];
                          if (archivoSeleccionado != null) {
                            urlFinal = await _subirArchivo(item['dni'], item['campo_base'], archivoSeleccionado!);
                          }

                          String fechaString = fechaSeleccionada.toString().split(' ')[0];

                          // ACTUALIZACIÓN SIGUIENDO LA LÓGICA DE PARES VENCIMIENTO/ARCHIVO
                          await FirebaseFirestore.instance
                              .collection('EMPLEADOS')
                              .doc(item['dni'])
                              .update({
                            "VENCIMIENTO_${item['campo_base']}": fechaString,
                            "ARCHIVO_${item['campo_base']}": urlFinal,
                            "ultima_auditoria_admin": FieldValue.serverTimestamp(),
                          });

                          if (stContext.mounted) Navigator.pop(stContext);
                        },
                        child: const Text("GUARDAR CAMBIOS"),
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
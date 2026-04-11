import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import '../../core/utils/formatters.dart';

class AdminVencimientosAcopladosScreen extends StatelessWidget {
  const AdminVencimientosAcopladosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Gestión Acoplados / Tolvas"),
        centerTitle: true,
        backgroundColor: const Color(0xFF1A3A5A).withValues(alpha: 0.85),
        elevation: 0,
        foregroundColor: Colors.white,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
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
          Container(color: const Color(0xFF1A3A5A).withValues(alpha: 0.5)),
          SafeArea(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('VEHICULOS').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.orangeAccent));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                      child: Text("No hay datos de unidades.", style: TextStyle(color: Colors.white70)));
                }

                List<Map<String, dynamic>> alertasAcoplados = [];

                for (var doc in snapshot.data!.docs) {
                  var data = doc.data() as Map<String, dynamic>;
                  String patente = doc.id; 
                  String tipoVehiculo = (data['TIPO'] ?? "").toString().toUpperCase();

                  // Filtrado específico para unidades de enganche
                  if (tipoVehiculo == "BATEA" || tipoVehiculo == "TOLVA" || tipoVehiculo == "ACOPLADO") {
                    
                    _verificarVencimiento(alertasAcoplados, patente, tipoVehiculo, "RTO", 
                        "RTO", data['VENCIMIENTO_RTO'], data['ARCHIVO_RTO']);

                    _verificarVencimiento(alertasAcoplados, patente, tipoVehiculo, "Seguro", 
                        "SEGURO", data['VENCIMIENTO_SEGURO'], data['ARCHIVO_SEGURO']);
                  }
                }

                alertasAcoplados = alertasAcoplados.where((item) => item['dias'] <= 60).toList();
                alertasAcoplados.sort((a, b) => a['dias'].compareTo(b['dias']));

                if (alertasAcoplados.isEmpty) {
                  return const Center(
                      child: Text("Sin vencimientos próximos (60 días)", style: TextStyle(color: Colors.white70)));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  itemCount: alertasAcoplados.length,
                  itemBuilder: (context, index) {
                    final item = alertasAcoplados[index];
                    Color colorSemaforo = item['dias'] < 0 
                        ? Colors.redAccent 
                        : (item['dias'] <= 30 ? Colors.orangeAccent : Colors.greenAccent);

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: colorSemaforo.withValues(alpha: 0.3)),
                      ),
                      child: ListTile(
                        onTap: () => _abrirEditorAcoplado(context, item),
                        leading: CircleAvatar(
                          backgroundColor: colorSemaforo.withValues(alpha: 0.2),
                          child: Text("${item['dias']}d", 
                            style: TextStyle(color: colorSemaforo, fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                        title: Text("${item['tipo_v']} - ${item['patente']}", 
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)),
                        subtitle: Text(
                          "${item['doc_nombre']}: ${AppFormatters.formatearFecha(item['fecha'])}",
                          style: const TextStyle(color: Colors.white70),
                        ),
                        trailing: const Icon(Icons.edit_square, color: Colors.blueAccent),
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

  Future<String?> _subirArchivoAcoplado(String patente, String campo, File archivo) async {
    try {
      String extension = archivo.path.split('.').last;
      String nombreArchivo = "${patente}_VENCIMIENTO_${campo}_${DateTime.now().millisecondsSinceEpoch}.$extension";
      
      Reference ref = FirebaseStorage.instance.ref().child('VEHICULOS/$nombreArchivo');
      UploadTask uploadTask = ref.putFile(archivo);
      TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      return null;
    }
  }

  void _abrirEditorAcoplado(BuildContext context, Map<String, dynamic> item) {
    DateTime fechaSeleccionada = DateTime.tryParse(item['fecha']) ?? DateTime.now();
    File? archivoSeleccionado;
    bool subiendo = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D1D2D),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Actualizar ${item['doc_nombre']}", 
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              Text("${item['tipo_v']} - ${item['patente']}", style: const TextStyle(color: Colors.white54)),
              const Divider(color: Colors.white12, height: 25),
              
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Vencimiento Documento", style: TextStyle(color: Colors.white)),
                subtitle: Text(AppFormatters.formatearFecha(fechaSeleccionada.toString().split(' ')[0]),
                  style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
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
                  border: Border.all(color: Colors.white12)
                ),
                child: Row(
                  children: [
                    Icon(archivoSeleccionado == null ? Icons.upload_file : Icons.check_circle, 
                         color: archivoSeleccionado == null ? Colors.white38 : Colors.greenAccent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        archivoSeleccionado == null ? "Adjuntar PDF o Foto" : "Archivo seleccionado",
                        style: const TextStyle(color: Colors.white70),
                      )
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_a_photo_outlined, color: Colors.blueAccent),
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
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
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
                            urlFinal = await _subirArchivoAcoplado(item['patente'], item['campo_base'], archivoSeleccionado!);
                          }
                          
                          String fechaString = fechaSeleccionada.toString().split(' ')[0];
                          
                          await FirebaseFirestore.instance.collection('VEHICULOS').doc(item['patente']).update({
                            "VENCIMIENTO_${item['campo_base']}": fechaString,
                            "ARCHIVO_${item['campo_base']}": urlFinal,
                            "fecha_ultima_actualizacion": FieldValue.serverTimestamp(),
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
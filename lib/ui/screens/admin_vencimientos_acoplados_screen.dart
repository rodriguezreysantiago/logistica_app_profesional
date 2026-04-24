import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
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
                      child: Text("No hay datos de unidades.", style: TextStyle(color: Colors.white70)));
                }

                List<Map<String, dynamic>> alertasAcoplados = [];

                for (var doc in snapshot.data!.docs) {
                  var data = doc.data() as Map<String, dynamic>;
                  String patente = doc.id.toUpperCase(); 
                  String tipoVehiculo = (data['TIPO'] ?? "").toString().toUpperCase();

                  // FILTRO: Solo lo que se engancha (No Tractores)
                  if (tipoVehiculo == "BATEA" || tipoVehiculo == "TOLVA" || tipoVehiculo == "ACOPLADO") {
                    
                    // Verificamos RTO
                    _verificarVencimiento(alertasAcoplados, patente, tipoVehiculo, "RTO", 
                        "RTO", data['VENCIMIENTO_RTO'], data['ARCHIVO_RTO']);

                    // Verificamos Seguro
                    _verificarVencimiento(alertasAcoplados, patente, tipoVehiculo, "Seguro", 
                        "SEGURO", data['VENCIMIENTO_SEGURO'], data['ARCHIVO_SEGURO']);
                  }
                }

                // MOSTRAR: Lo vencido y lo que vence en los próximos 60 días
                alertasAcoplados = alertasAcoplados.where((item) => item['dias'] <= 60).toList();
                alertasAcoplados.sort((a, b) => a['dias'].compareTo(b['dias']));

                if (alertasAcoplados.isEmpty) {
                  return const Center(
                      child: Text("Sin vencimientos próximos en la flota", style: TextStyle(color: Colors.white70)));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  itemCount: alertasAcoplados.length,
                  itemBuilder: (context, index) {
                    final item = alertasAcoplados[index];
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
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: colorSemaforo.withAlpha(100),
                          width: d <= 14 ? 2 : 1,
                        ),
                      ),
                      child: ListTile(
                        onTap: () => _abrirEditorAcoplado(context, item),
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

  // ✅ Mentora: Le quitamos el try/catch. Queremos que el error "suba" y aborte el guardado si falla.
  Future<String?> _subirArchivoAcoplado(String patente, String campo, File archivo) async {
    String extension = archivo.path.split('.').last;
    String nombreArchivo = "${patente}_ADMIN_UPDATE_${campo}_${DateTime.now().millisecondsSinceEpoch}.$extension";
    Reference ref = FirebaseStorage.instance.ref().child('VEHICULOS_DOCS/$nombreArchivo');
    await ref.putFile(archivo);
    return await ref.getDownloadURL();
  }

  void _abrirEditorAcoplado(BuildContext context, Map<String, dynamic> item) {
    DateTime fechaSeleccionada = DateTime.tryParse(item['fecha']) ?? DateTime.now();
    File? archivoSeleccionado;
    bool subiendo = false;

    // ✅ Mentora: Capturamos el context seguro desde la pantalla base, no desde el modal
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

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
                title: const Text("Fecha de Vencimiento", style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: Text(AppFormatters.formatearFecha(fechaSeleccionada.toString().split(' ')[0]),
                  style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                trailing: const Icon(Icons.calendar_month, color: Colors.blueAccent),
                onTap: () async {
                  DateTime? picker = await showDatePicker(
                    context: stContext,
                    initialDate: fechaSeleccionada,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2040),
                  );
                  // ✅ Mentora: Evitamos crasheos si el usuario cierra el modal rápido
                  if (picker != null && stContext.mounted) {
                    setState(() => fechaSeleccionada = picker);
                  }
                },
              ),
              const SizedBox(height: 10),
              
              InkWell(
                onTap: () async {
                  FilePickerResult? result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['jpg', 'pdf', 'png', 'jpeg'],
                  );
                  if (result != null && stContext.mounted) {
                    setState(() => archivoSeleccionado = File(result.files.single.path!));
                  }
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
                      Icon(archivoSeleccionado == null ? Icons.upload_file : Icons.check_circle, 
                           color: archivoSeleccionado == null ? Colors.white38 : Colors.greenAccent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          archivoSeleccionado == null ? "Cargar comprobante nuevo" : "Archivo listo para subir",
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        )
                      ),
                      if (archivoSeleccionado == null) const Icon(Icons.add_a_photo, color: Colors.blueAccent, size: 20)
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
                          
                          try {
                            String? urlFinal = item['foto'];
                            
                            // Si hay archivo nuevo, lo subimos. Si esto falla, saltamos al catch 
                            // y NO actualizamos Firebase, evitando borrar la foto anterior.
                            if (archivoSeleccionado != null) {
                              urlFinal = await _subirArchivoAcoplado(item['patente'], item['campo_base'], archivoSeleccionado!);
                            }
                            
                            String fechaString = fechaSeleccionada.toString().split(' ')[0];
                            
                            await FirebaseFirestore.instance.collection('VEHICULOS').doc(item['patente']).update({
                              "VENCIMIENTO_${item['campo_base']}": fechaString,
                              "ARCHIVO_${item['campo_base']}": urlFinal,
                              "admin_audit_date": FieldValue.serverTimestamp(),
                            });
                            
                            messenger.showSnackBar(
                              SnackBar(content: Text("${item['doc_nombre']} actualizado con éxito"), backgroundColor: Colors.green)
                            );
                            navigator.pop(); // Usamos la referencia capturada al inicio

                          } catch (e) {
                            messenger.showSnackBar(
                              SnackBar(content: Text("Error al guardar: $e"), backgroundColor: Colors.red)
                            );
                            if (stContext.mounted) {
                              setState(() => subiendo = false);
                            }
                          }
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
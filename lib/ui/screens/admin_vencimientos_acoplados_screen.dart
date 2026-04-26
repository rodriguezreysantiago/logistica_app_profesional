import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../core/utils/formatters.dart';

// ✅ MENTOR: Cambiado a StatefulWidget para proteger el Stream
class AdminVencimientosAcopladosScreen extends StatefulWidget {
  const AdminVencimientosAcopladosScreen({super.key});

  @override
  State<AdminVencimientosAcopladosScreen> createState() => _AdminVencimientosAcopladosScreenState();
}

class _AdminVencimientosAcopladosScreenState extends State<AdminVencimientosAcopladosScreen> {
  late final Stream<QuerySnapshot> _vehiculosStream;

  @override
  void initState() {
    super.initState();
    // ✅ MENTOR: El Stream se abre una sola vez
    _vehiculosStream = FirebaseFirestore.instance.collection('VEHICULOS').snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Gestión Acoplados / Tolvas"),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/fondo_login.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: Theme.of(context).scaffoldBackgroundColor),
            ),
          ),
          Container(color: Colors.black.withAlpha(200)),
          
          SafeArea(
            child: StreamBuilder<QuerySnapshot>(
              stream: _vehiculosStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                      child: Text("No hay datos de unidades.", style: TextStyle(color: Colors.white54)));
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 60),
                        SizedBox(height: 15),
                        Text("Sin vencimientos próximos en los enganches", style: TextStyle(color: Colors.white70, fontSize: 15)),
                      ],
                    )
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  itemCount: alertasAcoplados.length,
                  itemBuilder: (context, index) {
                    final item = alertasAcoplados[index];
                    int d = item['dias'];

                    // SEMÁFORO UNIFICADO S.M.A.R.T.
                    Color colorSemaforo = Colors.blueAccent;
                    if (d < 0) {
  colorSemaforo = Colors.redAccent;
} else if (d <= 14) {
  colorSemaforo = Colors.orangeAccent;
} else if (d <= 30) {
  colorSemaforo = Colors.greenAccent;
}

                    // ✅ MENTOR: Implementación del Ripple Effect con el Theme global
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colorSemaforo.withAlpha(d <= 14 ? 150 : 30),
                          width: d <= 14 ? 1.5 : 0.5,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _abrirEditorAcoplado(context, item),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: colorSemaforo.withAlpha(20),
                                child: Text("${item['dias']}d", 
                                  style: TextStyle(
                                    color: colorSemaforo, 
                                    fontWeight: FontWeight.bold, 
                                    fontSize: 12
                                  )
                                ),
                              ),
                              title: Text("${item['tipo_v']} - ${item['patente']}", 
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)),
                              subtitle: Text(
                                "${item['doc_nombre']}: ${AppFormatters.formatearFecha(item['fecha'])}",
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                              trailing: const Icon(Icons.edit_calendar, color: Colors.greenAccent, size: 20),
                            ),
                          ),
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
    String extension = archivo.path.split('.').last.toLowerCase();
    String nombreArchivo = "${patente}_ADMIN_UPDATE_${campo}_${DateTime.now().millisecondsSinceEpoch}.$extension";
    Reference ref = FirebaseStorage.instance.ref().child('VEHICULOS_DOCS/$nombreArchivo');
    
    // ✅ MENTOR: Protección de formato para el navegador
    SettableMetadata? metadata;
    if (extension == 'pdf') {
      metadata = SettableMetadata(contentType: 'application/pdf');
    } else if (['jpg', 'jpeg', 'png'].contains(extension)) {
      metadata = SettableMetadata(contentType: 'image/jpeg');
    }

    await ref.putFile(archivo, metadata);
    return await ref.getDownloadURL();
  }

  void _abrirEditorAcoplado(BuildContext context, Map<String, dynamic> item) {
    DateTime fechaSeleccionada = DateTime.tryParse(item['fecha']) ?? DateTime.now();
    File? archivoSeleccionado;
    bool subiendo = false;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bContext) => StatefulBuilder(
        builder: (stContext, setState) => Container(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(stContext).viewInsets.bottom + 20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
            border: const Border(top: BorderSide(color: Colors.greenAccent, width: 2))
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Actualizar ${item['doc_nombre']}", 
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 5),
              Text("${item['tipo_v']} - ${item['patente']}", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w500)),
              const Divider(color: Colors.white10, height: 25),
              
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Fecha de Vencimiento", style: TextStyle(color: Colors.white70, fontSize: 13)),
                subtitle: Text(AppFormatters.formatearFecha(fechaSeleccionada.toString().split(' ')[0]),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                trailing: const Icon(Icons.calendar_month, color: Colors.greenAccent, size: 28),
                onTap: () async {
                  DateTime? picker = await showDatePicker(
                    context: stContext,
                    initialDate: fechaSeleccionada,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2040),
                  );
                  if (picker != null && stContext.mounted) {
                    setState(() => fechaSeleccionada = picker);
                  }
                },
              ),
              const SizedBox(height: 15),
              
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
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black12, 
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: archivoSeleccionado == null ? Colors.white10 : Colors.greenAccent)
                  ),
                  child: Row(
                    children: [
                      Icon(archivoSeleccionado == null ? Icons.upload_file : Icons.check_circle, 
                           color: archivoSeleccionado == null ? Colors.white38 : Colors.greenAccent, size: 28),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Text(
                          archivoSeleccionado == null ? "Cargar comprobante nuevo" : "Archivo listo para subir",
                          style: TextStyle(color: archivoSeleccionado == null ? Colors.white54 : Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.w500),
                        )
                      ),
                      if (archivoSeleccionado == null) const Icon(Icons.add_a_photo_outlined, color: Colors.greenAccent, size: 20)
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 35),
              if (subiendo) 
                const CircularProgressIndicator(color: Colors.greenAccent)
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                        ),
                        onPressed: () => Navigator.pop(stContext), 
                        child: const Text("CANCELAR", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold))
                      )
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                        ),
                        onPressed: () async {
                          setState(() => subiendo = true);
                          
                          try {
                            String? urlFinal = item['foto'];
                            
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
                            navigator.pop();

                          } catch (e) {
                            messenger.showSnackBar(
                              SnackBar(content: Text("Error al guardar: $e"), backgroundColor: Colors.redAccent)
                            );
                            if (stContext.mounted) {
                              setState(() => subiendo = false);
                            }
                          }
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
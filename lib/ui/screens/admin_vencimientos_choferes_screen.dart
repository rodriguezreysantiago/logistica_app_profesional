import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../core/utils/formatters.dart';

// ✅ MENTOR: Transformado a StatefulWidget para aislar el Stream y no re-calcular todo en cada render.
class AdminVencimientosChoferesScreen extends StatefulWidget {
  const AdminVencimientosChoferesScreen({super.key});

  @override
  State<AdminVencimientosChoferesScreen> createState() => _AdminVencimientosChoferesScreenState();
}

class _AdminVencimientosChoferesScreenState extends State<AdminVencimientosChoferesScreen> {
  late final Stream<QuerySnapshot> _empleadosStream;

  @override
  void initState() {
    super.initState();
    // Inicializamos la conexión a la base de datos UNA sola vez
    _empleadosStream = FirebaseFirestore.instance.collection('EMPLEADOS').snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Auditoría: Personal (60 días)"),
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
              stream: _empleadosStream, // Usamos el stream en caché
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text("Error al cargar datos", style: TextStyle(color: Colors.redAccent)));
                }
                
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                      child: Text("No hay datos de empleados registrados.",
                          style: TextStyle(color: Colors.white54)));
                }

                List<Map<String, dynamic>> criticos = [];

                // Lógica de extracción de fechas
                for (var doc in snapshot.data!.docs) {
                  var data = doc.data() as Map<String, dynamic>;
                  String nombre = data['NOMBRE'] ?? "Sin Nombre";
                  String dni = doc.id.trim();

                  // --- DOCUMENTACIÓN PERSONAL ---
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 60),
                        SizedBox(height: 15),
                        Text("Personal con documentación al día", style: TextStyle(color: Colors.white70, fontSize: 16)),
                      ],
                    )
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  itemCount: criticos.length,
                  itemBuilder: (context, index) {
                    final item = criticos[index];
                    int d = item['dias'];
                    
                    // SEMÁFORO UNIFICADO
                    Color colorSemaforo = Colors.blueAccent;
                    if (d < 0) {
                    colorSemaforo = Colors.redAccent;
                    } else if (d <= 14) {
                   colorSemaforo = Colors.orangeAccent;
                    } else if (d <= 30) {
                      colorSemaforo = Colors.greenAccent;
                    }

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface, // Diseño unificado
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: colorSemaforo.withAlpha(d <= 14 ? 150 : 30), width: d <= 14 ? 1.5 : 0.5),
                      ),
                      child: ListTile(
                        onTap: () => _abrirEditorDirecto(context, item),
                        leading: CircleAvatar(
                          backgroundColor: colorSemaforo.withAlpha(20),
                          child: Text("${item['dias']}d",
                              style: TextStyle(
                                  color: colorSemaforo,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ),
                        title: Text(item['usuario'],
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text(
                          "${item['tipo']}: ${AppFormatters.formatearFecha(item['fecha'])}",
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        trailing: const Icon(Icons.edit_calendar, color: Colors.greenAccent, size: 20),
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
    String extension = archivo.path.split('.').last.toLowerCase();
    String nombreArchivo = "${dni}_ADMIN_AUDIT_${campo}_${DateTime.now().millisecondsSinceEpoch}.$extension";
    Reference ref = FirebaseStorage.instance.ref().child('EMPLEADOS_DOCS/$nombreArchivo');
    
    // ✅ MENTOR: Identificamos el tipo de archivo para que el navegador sepa cómo leerlo
    SettableMetadata? metadata;
    if (extension == 'pdf') {
      metadata = SettableMetadata(contentType: 'application/pdf');
    } else if (['jpg', 'jpeg', 'png'].contains(extension)) {
      metadata = SettableMetadata(contentType: 'image/jpeg');
    }

    await ref.putFile(archivo, metadata);
    return await ref.getDownloadURL();
  }

  void _abrirEditorDirecto(BuildContext context, Map<String, dynamic> item) {
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
              Text("Actualizar ${item['tipo']}",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 5),
              Text(item['usuario'], style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w500)),
              const Divider(color: Colors.white10, height: 25),
              
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Fecha de Vencimiento", style: TextStyle(color: Colors.white70, fontSize: 13)),
                subtitle: Text(
                  AppFormatters.formatearFecha(fechaSeleccionada.toString().split(' ')[0]),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
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
                      border: Border.all(color: archivoSeleccionado == null ? Colors.white10 : Colors.greenAccent)),
                  child: Row(
                    children: [
                      Icon(archivoSeleccionado == null ? Icons.upload_file : Icons.check_circle,
                          color: archivoSeleccionado == null ? Colors.white38 : Colors.greenAccent, size: 28),
                      const SizedBox(width: 15),
                      Expanded(
                          child: Text(
                        archivoSeleccionado == null ? "Cargar comprobante nuevo" : "Archivo adjuntado correctamente",
                        style: TextStyle(color: archivoSeleccionado == null ? Colors.white54 : Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.w500),
                      )),
                      if (archivoSeleccionado == null)
                        const Icon(Icons.add_a_photo_outlined, color: Colors.greenAccent, size: 20)
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
                          child: const Text("CANCELAR", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold))),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () async {
                          setState(() => subiendo = true);
                          
                          try {
                            String? urlFinal = item['foto'];
                            
                            if (archivoSeleccionado != null) {
                              urlFinal = await _subirArchivo(item['dni'], item['campo_base'], archivoSeleccionado!);
                            }

                            String fechaString = fechaSeleccionada.toString().split(' ')[0];

                            await FirebaseFirestore.instance
                                .collection('EMPLEADOS')
                                .doc(item['dni'])
                                .update({
                              "VENCIMIENTO_${item['campo_base']}": fechaString,
                              "ARCHIVO_${item['campo_base']}": urlFinal,
                              "ultima_auditoria_admin": FieldValue.serverTimestamp(),
                            });

                            messenger.showSnackBar(
                              SnackBar(content: Text("${item['tipo']} actualizado con éxito"), backgroundColor: Colors.green)
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
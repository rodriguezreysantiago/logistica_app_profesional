import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/services/firebase_service.dart';
import '../../core/utils/formatters.dart';

class UserMiPerfilScreen extends StatefulWidget {
  final String dni;
  const UserMiPerfilScreen({super.key, required this.dni});

  @override
  State<UserMiPerfilScreen> createState() => _UserMiPerfilScreenState();
}

class _UserMiPerfilScreenState extends State<UserMiPerfilScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  // SOLUCIÓN: Quitamos 'BuildContext context' de los parámetros.
  // Usaremos el context propio del State que es seguro tras chequear 'mounted'.
  Future<void> _iniciarTramite({
    required String documentoEtiqueta,
    required String campoFirestore,
  }) async {
    // 1. Seleccionar Fecha
    final DateTime? fechaElegida = await showDatePicker(
      context: context, // Usamos el context del State
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: "SELECCIONAR VENCIMIENTO",
      locale: const Locale('es', 'AR'),
    );

    if (fechaElegida == null || !mounted) return;
    
    String fechaS = "${fechaElegida.year}-${fechaElegida.month.toString().padLeft(2, '0')}-${fechaElegida.day.toString().padLeft(2, '0')}";

    // 2. Seleccionar Archivo
    // Guardamos el Navigator y el resultado en una variable local
    File? archivoElegido;
    
    await showModalBottomSheet(
      context: context,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Tomar Foto'),
                onTap: () async {
                  final ImagePicker picker = ImagePicker();
                  final XFile? img = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
                  if (img != null) archivoElegido = File(img.path);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file),
                title: const Text('Subir Archivo o Galería'),
                onTap: () async {
                  final FilePickerResult? res = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['jpg', 'pdf', 'png', 'jpeg'],
                  );
                  if (res != null && res.files.single.path != null) {
                    archivoElegido = File(res.files.single.path!);
                  }
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
              ),
            ],
          ),
        );
      },
    );

    // 3. Subida Final
    // Crucial: Verificamos mounted antes de llamar a la siguiente función que usa context
    if (archivoElegido != null && mounted) {
      _subirAlService(documentoEtiqueta, campoFirestore, archivoElegido!, fechaS);
    }
  }

  void _subirAlService(String etiqueta, String campo, File archivo, String fecha) async {
    // Referencias locales para evitar fugas de memoria
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (c) => const Center(child: CircularProgressIndicator())
    );

    try {
      await _firebaseService.registrarSolicitudRevision(
        dni: widget.dni,
        etiqueta: etiqueta,
        campo: campo,
        archivo: archivo,
        fechaS: fecha,
        coleccionDestino: 'EMPLEADOS',
      );

      if (!mounted) return;

      navigator.pop(); 
      messenger.showSnackBar(
        SnackBar(content: Text("Solicitud de $etiqueta enviada con éxito"), backgroundColor: Colors.green)
      );
    } catch (e) {
      if (!mounted) return;
      
      navigator.pop(); 
      messenger.showSnackBar(
        SnackBar(content: Text("Error al subir: $e"), backgroundColor: Colors.red)
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mi Perfil / Documentación"),
        backgroundColor: const Color(0xFF1A3A5A),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dni).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text("Error al cargar datos"));
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: CircularProgressIndicator());

          var data = snapshot.data!.data() as Map<String, dynamic>;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSeccionTitulo("DATOS PERSONALES"),
              _buildInfoTile("DNI", AppFormatters.formatearDNI(widget.dni)),
              _buildInfoTile("NOMBRE", data['CHOFER'] ?? "No disponible"),
              const Divider(height: 40),
              
              _buildSeccionTitulo("DOCUMENTACIÓN"),
              _buildDocItem(
                "LICENCIA DE CONDUCIR",
                data['VTO_LICENCIA'],
                () => _iniciarTramite(documentoEtiqueta: "LICENCIA", campoFirestore: "VTO_LICENCIA"),
              ),
              _buildDocItem(
                "CURSO LINTI",
                data['VTO_LINTI'],
                () => _iniciarTramite(documentoEtiqueta: "LINTI", campoFirestore: "VTO_LINTI"),
              ),
              _buildDocItem(
                "LIBRETA SANITARIA",
                data['VTO_LIBRETA'],
                () => _iniciarTramite(documentoEtiqueta: "LIBRETA", campoFirestore: "VTO_LIBRETA"),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSeccionTitulo(String titulo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 5),
      child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
    );
  }

  Widget _buildInfoTile(String label, String valor) {
    return ListTile(
      title: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      subtitle: Text(valor, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildDocItem(String titulo, String? fecha, VoidCallback onEdit) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.description, color: Color(0xFF1A3A5A)),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("Vencimiento: ${AppFormatters.formatearFecha(fecha)}"),
        trailing: IconButton(
          icon: const Icon(Icons.file_upload_outlined, color: Colors.blue),
          onPressed: onEdit,
        ),
      ),
    );
  }
}
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/services/firebase_service.dart';
import '../../core/utils/formatters.dart';

class UserMisVencimientosScreen extends StatefulWidget {
  final String dniUser;

  const UserMisVencimientosScreen({super.key, required this.dniUser});

  @override
  State<UserMisVencimientosScreen> createState() => _UserMisVencimientosScreenState();
}

class _UserMisVencimientosScreenState extends State<UserMisVencimientosScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  // --- MOTOR ASÍNCRONO ---
  Future<void> _ejecutarTareaAsincrona({
    required Future<void> Function() tarea,
    required String mensajeExito,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await tarea();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensajeExito), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  // --- LÓGICA DE TRÁMITE ---
  void _iniciarTramiteManual({
    required String etiqueta, 
    required String campo, 
    required String idDocumento, 
    required String coleccion,   
    String? infoExtra,           
  }) {
    final TextEditingController fechaCtrl = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Actualizar: $etiqueta", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (infoExtra != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(infoExtra, style: const TextStyle(fontSize: 14, color: Colors.blue, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Nueva fecha de vencimiento:", style: TextStyle(fontSize: 13)),
              const SizedBox(height: 15),
              TextFormField(
                controller: fechaCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, letterSpacing: 2, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  hintText: "DD/MM/AAAA",
                  border: OutlineInputBorder(),
                  counterText: "",
                ),
                maxLength: 10,
                inputFormatters: [_FechaInputFormatter()],
                validator: (value) {
                  if (value == null || value.length < 10) return "Fecha incompleta";
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text("CANCELAR")),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                final partes = fechaCtrl.text.split('/');
                final fechaS = "${partes[2]}-${partes[1]}-${partes[0]}";
                Navigator.pop(dCtx);
                
                String etiquetaFinal = infoExtra != null ? "$etiqueta ($infoExtra)" : etiqueta;
                _mostrarSelectorArchivo(etiquetaFinal, campo, fechaS, idDocumento, coleccion);
              }
            },
            child: const Text("SIGUIENTE"),
          ),
        ],
      ),
    );
  }

  void _mostrarSelectorArchivo(String etiqueta, String campo, String fechaS, String id, String coleccion) {
    showModalBottomSheet(
      context: context,
      builder: (sCtx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text("Tomar Foto"),
              onTap: () async {
                final img = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70);
                if (img != null) _enviarRevision(etiqueta, campo, File(img.path), fechaS, id, coleccion);
                if (sCtx.mounted) Navigator.pop(sCtx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text("Subir Archivo / PDF"),
              onTap: () async {
                final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'png']);
                if (res != null) _enviarRevision(etiqueta, campo, File(res.files.single.path!), fechaS, id, coleccion);
                if (sCtx.mounted) Navigator.pop(sCtx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _enviarRevision(String etiqueta, String campo, File archivo, String fecha, String id, String coleccion) {
    _ejecutarTareaAsincrona(
      tarea: () async => await _firebaseService.registrarSolicitudRevision(
        dni: id, 
        etiqueta: etiqueta, 
        campo: campo, 
        archivo: archivo, 
        fechaS: fecha, 
        coleccionDestino: coleccion,
      ),
      mensajeExito: "Solicitud enviada correctamente",
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mis Vencimientos"),
        backgroundColor: const Color(0xFF1A3A5A),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dniUser).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: CircularProgressIndicator());

          var data = snapshot.data!.data() as Map<String, dynamic>;
          String pTractor = data['TRACTOR'] ?? "";
          String pAcoplado = data['BATEA_TOLVA'] ?? "";

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildTituloPrincipal("DOCUMENTACIÓN PERSONAL"),
              _buildCardVencimiento("Licencia de Conducir", data['LIC_COND'], 
                () => _iniciarTramiteManual(etiqueta: "LICENCIA", campo: "LIC_COND", idDocumento: widget.dniUser, coleccion: 'EMPLEADOS')),
              _buildCardVencimiento("Curso Manejo Defensivo", data['CURSO_MANEJO'], 
                () => _iniciarTramiteManual(etiqueta: "MANEJO DEFENSIVO", campo: "CURSO_MANEJO", idDocumento: widget.dniUser, coleccion: 'EMPLEADOS')),
              _buildCardVencimiento("Psicofísico (EPAP)", data['EPAP'], 
                () => _iniciarTramiteManual(etiqueta: "EPAP", campo: "EPAP", idDocumento: widget.dniUser, coleccion: 'EMPLEADOS')),

              const SizedBox(height: 30),
              _buildTituloPrincipal("VENCIMIENTOS DE EQUIPO"),
              
              if (pTractor.isNotEmpty && pTractor != "SIN ASIGNAR")
                _buildDetalleVehiculo(pTractor, "CHASIS")
              else
                _buildCardVacia("No hay chasis asignado"),

              const SizedBox(height: 20),
              if (pAcoplado.isNotEmpty && pAcoplado != "SIN ASIGNAR")
                _buildDetalleVehiculo(pAcoplado, "ACOPLADO")
              else
                _buildCardVacia("No hay acoplado asignado"),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDetalleVehiculo(String patente, String tipoSeccion) => StreamBuilder<DocumentSnapshot>(
    stream: FirebaseFirestore.instance.collection('VEHICULOS').doc(patente).snapshots(),
    builder: (context, vehiculoSnap) {
      if (!vehiculoSnap.hasData || !vehiculoSnap.data!.exists) return _buildCardVacia("Patente $patente no encontrada");
      var vData = vehiculoSnap.data!.data() as Map<String, dynamic>;
      
      // Buscamos el tipo real (TRACTOR, BATEA, TOLVA, etc.)
      String tipoReal = (vData['TIPO'] ?? tipoSeccion).toString().toUpperCase();
      String descripcionCompleta = "$tipoReal $patente";

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSubtituloUnidad(tipoSeccion, descripcionCompleta),
          
          _buildCardVencimiento("RTO", vData['VENCIMIENTO_RTO'], 
            () => _iniciarTramiteManual(
              etiqueta: "RTO", 
              campo: "VENCIMIENTO_RTO", 
              idDocumento: patente, 
              coleccion: 'VEHICULOS',
              infoExtra: descripcionCompleta
            )),
          _buildCardVencimiento("Póliza de Seguro", vData['VENCIMIENTO_POLIZA'], 
            () => _iniciarTramiteManual(
              etiqueta: "PÓLIZA", 
              campo: "VENCIMIENTO_POLIZA", 
              idDocumento: patente, 
              coleccion: 'VEHICULOS',
              infoExtra: descripcionCompleta
            )),
        ],
      );
    },
  );

  // --- COMPONENTES VISUALES ---
  Widget _buildTituloPrincipal(String titulo) => Padding(padding: const EdgeInsets.only(bottom: 8.0), child: Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A3A5A))));

  Widget _buildSubtituloUnidad(String tipoSeccion, String descripcionCompleta) => Container(
    margin: const EdgeInsets.symmetric(vertical: 5),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    width: double.infinity,
    decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blueGrey.shade100)),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(tipoSeccion, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 11)),
      Text(descripcionCompleta, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A3A5A), fontSize: 13)),
    ]),
  );

  Widget _buildCardVencimiento(String titulo, String? fecha, VoidCallback onUpload) {
    int dias = AppFormatters.calcularDiasRestantes(fecha);
    Color colorEstado = dias < 0 ? Colors.red : (dias < 15 ? Colors.orange : Colors.green);
    
    return Card(
      elevation: 0.5,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        dense: true,
        leading: Icon(Icons.circle, color: colorEstado, size: 10),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        subtitle: Text("Vence: ${AppFormatters.formatearFecha(fecha)}", style: TextStyle(fontSize: 11, color: dias < 0 ? Colors.red : Colors.black54)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(dias < 0 ? "VENCIDO" : "$dias d.", style: TextStyle(color: colorEstado, fontWeight: FontWeight.bold, fontSize: 11)),
            const SizedBox(width: 5),
            IconButton(icon: const Icon(Icons.upload_file, color: Colors.blue, size: 22), onPressed: onUpload),
          ],
        ),
      ),
    );
  }

  Widget _buildCardVacia(String mensaje) => Card(color: Colors.grey.shade50, child: ListTile(dense: true, title: Text(mensaje, style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 11))));
}

class _FechaInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.length > 8) text = text.substring(0, 8);
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      if ((i == 1 || i == 3) && i != text.length - 1) buffer.write('/');
    }
    final stringFinal = buffer.toString();
    return TextEditingValue(text: stringFinal, selection: TextSelection.collapsed(offset: stringFinal.length));
  }
}
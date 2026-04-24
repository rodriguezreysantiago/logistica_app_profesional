import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart'; 

import '../../ui/widgets/preview_screen.dart';
import '../../core/services/firebase_service.dart';
import '../../core/utils/formatters.dart';
import 'user_checklist_form_screen.dart'; 

class UserMisVencimientosScreen extends StatefulWidget {
  final String dniUser;

  const UserMisVencimientosScreen({super.key, required this.dniUser});

  @override
  State<UserMisVencimientosScreen> createState() => _UserMisVencimientosScreenState();
}

class _UserMisVencimientosScreenState extends State<UserMisVencimientosScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  void _abrirArchivo(String? url, String titulo) {
    if (url == null || url.isEmpty || url == "-") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No hay un archivo digital cargado."), backgroundColor: Colors.orange),
      );
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (context) => PreviewScreen(url: url, titulo: titulo)));
  }

  Future<void> _ejecutarTareaAsincrona({required Future<void> Function() tarea, required String mensajeExito}) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.orangeAccent)),
    );
    try {
      await tarea();
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(mensajeExito), backgroundColor: Colors.green));
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  void _iniciarTramiteManual({
    required String etiqueta, 
    required String campo, 
    required String idDocumento, 
    required String coleccion,
    required String nombreUsuario, 
  }) {
    final TextEditingController fechaCtrl = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1D2D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Actualizar $etiqueta", style: const TextStyle(color: Colors.white, fontSize: 18)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Ingresá la fecha que figura en el nuevo carnet/certificado:", style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 20),
              TextFormField(
                controller: fechaCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, color: Colors.orangeAccent, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: "DD/MM/AAAA",
                  hintStyle: const TextStyle(color: Colors.white10),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.02),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                maxLength: 10,
                inputFormatters: [_FechaInputFormatter()],
                validator: (value) => (value == null || value.length < 10) ? "Fecha incompleta" : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text("CANCELAR", style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                final partes = fechaCtrl.text.split('/');
                final fechaS = "${partes[2]}-${partes[1]}-${partes[0]}";
                Navigator.pop(dCtx);
                _mostrarSelectorArchivo(etiqueta, campo, fechaS, idDocumento, coleccion, nombreUsuario);
              }
            },
            child: const Text("CONTINUAR"),
          ),
        ],
      ),
    );
  }

  void _mostrarSelectorArchivo(String etiqueta, String campo, String fechaS, String id, String coleccion, String nombreUsuario) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1D2D),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (sCtx) => SafeArea(
        child: Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text("FOTO DEL COMPROBANTE", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blueAccent),
              title: const Text("Tomar con la Cámara", style: TextStyle(color: Colors.white)),
              onTap: () async {
                final img = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 50);
                if (sCtx.mounted) Navigator.pop(sCtx);
                if (img != null) _enviarRevision(etiqueta, campo, File(img.path), fechaS, id, coleccion, nombreUsuario);
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file, color: Colors.blueAccent),
              title: const Text("Cargar Foto o PDF", style: TextStyle(color: Colors.white)),
              onTap: () async {
                final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'png', 'jpeg']);
                if (sCtx.mounted) Navigator.pop(sCtx);
                if (res != null) _enviarRevision(etiqueta, campo, File(res.files.single.path!), fechaS, id, coleccion, nombreUsuario);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _enviarRevision(String etiqueta, String campo, File archivo, String fecha, String id, String coleccion, String nombreUsuario) {
    _ejecutarTareaAsincrona(
      tarea: () async => await _firebaseService.registrarSolicitudRevision(
        dni: id, 
        nombreUsuario: nombreUsuario,
        etiqueta: etiqueta, 
        campo: campo, 
        archivo: archivo, 
        fechaS: fecha, 
        coleccionDestino: coleccion,
      ),
      mensajeExito: "Solicitud enviada. Aguarde aprobación de la oficina.",
    );
  }

  // ✅ CORREGIDO: Acceso al Checklist Mensual 100% igualado a tu Firestore
  Widget _buildAccesoChecklist(String patente, String tipoLabel) {
    final now = DateTime.now();
    final tipoChecklist = tipoLabel == "CAMIÓN" ? "TRACTOR" : "BATEA";

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('CHECKLISTS')
          .where('DOMINIO', isEqualTo: patente) // Mayúscula
          .where('MES', isEqualTo: now.month)    // Mayúscula
          .where('ANIO', isEqualTo: now.year)    // Mayúscula
          .orderBy('FECHA', descending: true)    // Mayúscula
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        // Bloque de Debug para que veas el error en la consola
        if (snapshot.hasError) {
          debugPrint("⚠️ ERROR FIRESTORE: ${snapshot.error}");
        }

        bool completado = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
        int dia = now.day;
        
        Color colorEstado = Colors.white10;
        String msj = "Checklist Mensual Pendiente";
        IconData icono = Icons.fact_check_outlined;

        if (completado) {
          colorEstado = Colors.greenAccent;
          // ✅ Accedemos a 'FECHA' en mayúscula
          var fechaDoc = (snapshot.data!.docs.first['FECHA'] as Timestamp).toDate();
          msj = "Control realizado (${DateFormat('dd/MM').format(fechaDoc)})";
          icono = Icons.check_circle;
        } else if (dia > 15) {
          colorEstado = Colors.redAccent;
          msj = "VENCIDO: Realizar Control YA";
          icono = Icons.warning_amber_rounded;
        } else if (dia > 10) {
          colorEstado = Colors.orangeAccent;
          msj = "Pendiente (Vence el día 15)";
        }

        return Container(
          margin: const EdgeInsets.only(top: 15),
          decoration: BoxDecoration(
            color: colorEstado.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: colorEstado.withValues(alpha: 0.2)),
          ),
          child: ListTile(
            dense: true,
            onTap: () {
              Navigator.push(
                context, 
                MaterialPageRoute(builder: (context) => UserChecklistFormScreen(tipo: tipoChecklist, patente: patente))
              );
            },
            leading: Icon(icono, color: colorEstado, size: 22),
            title: Text(msj, style: TextStyle(color: colorEstado, fontWeight: FontWeight.bold, fontSize: 12)),
            trailing: Icon(Icons.arrow_forward_ios, color: colorEstado, size: 14),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, 
      appBar: AppBar(
        title: const Text("Mis Vencimientos"),
        centerTitle: true,
        backgroundColor: Colors.transparent, 
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(child: Image.asset('assets/images/fondo_login.jpg', fit: BoxFit.cover)),
          Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.85))),

          SafeArea(
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dniUser).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: CircularProgressIndicator(color: Colors.orangeAccent));

                var data = snapshot.data!.data() as Map<String, dynamic>;
                String nombreChofer = data['NOMBRE'] ?? "Chofer";
                String pVehiculo = (data['VEHICULO'] ?? "").toString().trim();
                String pEnganche = (data['ENGANCHE'] ?? "").toString().trim();

                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                  children: [
                    _buildSeccionHeader("LICENCIAS Y CARNETS"),
                    _buildCardVencimiento(
                      titulo: "Licencia de Conducir", 
                      fecha: data['VENCIMIENTO_LICENCIA_DE_CONDUCIR'], 
                      campo: "VENCIMIENTO_LICENCIA_DE_CONDUCIR", 
                      urlArchivo: data['ARCHIVO_LICENCIA_DE_CONDUCIR'], 
                      idDoc: widget.dniUser,
                      onUpload: () => _iniciarTramiteManual(
                        etiqueta: "LICENCIA", 
                        campo: "VENCIMIENTO_LICENCIA_DE_CONDUCIR", 
                        idDocumento: widget.dniUser, 
                        coleccion: 'EMPLEADOS', 
                        nombreUsuario: nombreChofer
                      )
                    ),
                    _buildCardVencimiento(
                      titulo: "Psicofísico (LINTI)", 
                      fecha: data['VENCIMIENTO_PSICOFISICO'], 
                      campo: "VENCIMIENTO_PSICOFISICO", 
                      urlArchivo: data['ARCHIVO_PSICOFISICO'], 
                      idDoc: widget.dniUser,
                      onUpload: () => _iniciarTramiteManual(
                        etiqueta: "PSICOFÍSICO", 
                        campo: "VENCIMIENTO_PSICOFISICO", 
                        idDocumento: widget.dniUser, 
                        coleccion: 'EMPLEADOS', 
                        nombreUsuario: nombreChofer
                      )
                    ),
                    _buildCardVencimiento(
                      titulo: "Manejo Defensivo", 
                      fecha: data['VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO'], 
                      campo: "VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO", 
                      urlArchivo: data['ARCHIVO_CURSO_DE_MANEJO_DEFENSIVO'], 
                      idDoc: widget.dniUser,
                      onUpload: () => _iniciarTramiteManual(
                        etiqueta: "CURSO MANEJO", 
                        campo: "VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO", 
                        idDocumento: widget.dniUser, 
                        coleccion: 'EMPLEADOS', 
                        nombreUsuario: nombreChofer
                      )
                    ),

                    const SizedBox(height: 25),
                    _buildSeccionHeader("COBERTURAS LABORALES"),
                    _buildCardVencimiento(
                      titulo: "Certificado ART", 
                      fecha: data['VENCIMIENTO_ART'], 
                      campo: "VENCIMIENTO_ART", 
                      urlArchivo: data['ARCHIVO_ART'], 
                      idDoc: widget.dniUser,
                      onUpload: () => _iniciarTramiteManual(
                        etiqueta: "ART", 
                        campo: "VENCIMIENTO_ART", 
                        idDocumento: widget.dniUser, 
                        coleccion: 'EMPLEADOS', 
                        nombreUsuario: nombreChofer
                      )
                    ),
                    
                    const SizedBox(height: 25),
                    _buildSeccionHeader("PAPELES Y CONTROLES DEL EQUIPO"),
                    
                    if (pVehiculo.isNotEmpty && pVehiculo != "-")
                      _buildDetalleEquipo(pVehiculo, "CAMIÓN", nombreChofer)
                    else
                      _buildCardInformativa("No tienes un camión asignado"),

                    const SizedBox(height: 15),
                    if (pEnganche.isNotEmpty && pEnganche != "-")
                      _buildDetalleEquipo(pEnganche, "ENGANCHE", nombreChofer)
                    else
                      _buildCardInformativa("No tienes batea/tolva asignada"),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetalleEquipo(String patente, String tipo, String nombreChofer) => StreamBuilder<DocumentSnapshot>(
    stream: FirebaseFirestore.instance.collection('VEHICULOS').doc(patente).snapshots(),
    builder: (context, vSnap) {
      if (!vSnap.hasData || !vSnap.data!.exists) return _buildCardInformativa("Unidad $patente no registrada");
      var vData = vSnap.data!.data() as Map<String, dynamic>;
      
      return Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10)
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12, left: 5),
              child: Text("$tipo: $patente", 
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
            ),
            _buildCardVencimiento(
              titulo: "RTO / VTV", 
              fecha: vData['VENCIMIENTO_RTO'], 
              campo: "VENCIMIENTO_RTO", 
              urlArchivo: vData['ARCHIVO_RTO'],
              idDoc: patente,
              onUpload: () => _iniciarTramiteManual(
                etiqueta: "RTO", 
                campo: "VENCIMIENTO_RTO", 
                idDocumento: patente, 
                coleccion: 'VEHICULOS', 
                nombreUsuario: nombreChofer
              )
            ),
            _buildCardVencimiento(
              titulo: "Seguro de Unidad", 
              fecha: vData['VENCIMIENTO_SEGURO'], 
              campo: "VENCIMIENTO_SEGURO", 
              urlArchivo: vData['ARCHIVO_SEGURO'], 
              idDoc: patente,
              onUpload: () => _iniciarTramiteManual(
                etiqueta: "SEGURO", 
                campo: "VENCIMIENTO_SEGURO", 
                idDocumento: patente, 
                coleccion: 'VEHICULOS', 
                nombreUsuario: nombreChofer
              )
            ),
            _buildAccesoChecklist(patente, tipo),
          ],
        ),
      );
    },
  );

  Widget _buildSeccionHeader(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 12, left: 5), 
    child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orangeAccent, letterSpacing: 2))
  );

  Widget _buildCardVencimiento({
    required String titulo, 
    required String? fecha, 
    required String campo, 
    required String idDoc, 
    required VoidCallback onUpload,
    String? urlArchivo, 
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('REVISIONES')
          .where('dni', isEqualTo: idDoc)
          .where('campo', isEqualTo: campo)
          .snapshots(),
      builder: (context, snapshot) {
        bool enRevision = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
        int dias = AppFormatters.calcularDiasRestantes(fecha);
        bool tieneArchivo = urlArchivo != null && urlArchivo.isNotEmpty && urlArchivo != "-";

        Color colorEstado;
        if (dias < 0) { colorEstado = Colors.red; } 
        else if (dias <= 14) { colorEstado = Colors.orange; } 
        else if (dias <= 30) { colorEstado = Colors.greenAccent; } 
        else { colorEstado = Colors.blueAccent; }

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: enRevision ? Colors.blue.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: enRevision ? Colors.blueAccent : colorEstado.withValues(alpha: 0.4),
              width: (dias <= 14 && !enRevision) ? 1.5 : 0.8, 
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
            onTap: tieneArchivo ? () => _abrirArchivo(urlArchivo, titulo) : null,
            
            leading: Icon(
              enRevision ? Icons.history_toggle_off : (tieneArchivo ? Icons.visibility_outlined : Icons.file_present_outlined), 
              color: enRevision 
                  ? Colors.blueAccent 
                  : (tieneArchivo ? Colors.blueAccent : Colors.white12), 
              size: 24
            ),

            title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
            
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                enRevision ? "VALIDACIÓN PENDIENTE..." : "Vencimiento: ${AppFormatters.formatearFecha(fecha)}", 
                style: TextStyle(
                  fontSize: 10, 
                  color: enRevision ? Colors.blueAccent : Colors.white60, 
                  fontWeight: enRevision ? FontWeight.bold : FontWeight.normal
                )
              ),
            ),

            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!enRevision)
                  Container(
                    width: 40,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: colorEstado.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colorEstado.withValues(alpha: 0.4))
                    ),
                    child: Center(
                      child: Text("${dias}d", style: TextStyle(color: colorEstado, fontWeight: FontWeight.bold, fontSize: 9)),
                    ),
                  ),
                const SizedBox(width: 8),
                
                if (enRevision)
                  const Icon(Icons.hourglass_top, color: Colors.white24, size: 18)
                else
                  IconButton(
                    icon: const Icon(Icons.upload, color: Colors.orangeAccent, size: 18),
                    onPressed: onUpload,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _buildCardInformativa(String m) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(15)),
    child: Text(m, style: const TextStyle(color: Colors.white24, fontStyle: FontStyle.italic, fontSize: 12)),
  );
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
    return TextEditingValue(
      text: stringFinal, 
      selection: TextSelection.collapsed(offset: stringFinal.length)
    );
  }
}
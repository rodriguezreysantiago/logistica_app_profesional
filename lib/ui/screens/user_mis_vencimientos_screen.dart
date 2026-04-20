import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../../ui/widgets/preview_screen.dart';
import '../../core/services/firebase_service.dart';
import '../../core/utils/formatters.dart';
import '../../core/services/notification_service.dart';

class UserMisVencimientosScreen extends StatefulWidget {
  final String dniUser;

  const UserMisVencimientosScreen({super.key, required this.dniUser});

  @override
  State<UserMisVencimientosScreen> createState() => _UserMisVencimientosScreenState();
}

class _UserMisVencimientosScreenState extends State<UserMisVencimientosScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  // --- LÓGICA DE VISUALIZACIÓN DE ARCHIVOS ---
  void _abrirArchivo(String? url, String titulo) {
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No hay un archivo digital cargado.")),
      );
      return;
    }
    // CORRECCIÓN MOUSE TRACKER PARA DESKTOP
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => PreviewScreen(url: url, titulo: titulo)));
    });
  }

  // --- FUNCIÓN PARA TAREAS CON LOADING ---
  Future<void> _ejecutarTareaAsincrona({required Future<void> Function() tarea, required String mensajeExito}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.orangeAccent)),
    );
    try {
      await tarea();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensajeExito), backgroundColor: Colors.green));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  // --- TRÁMITE MANUAL: SELECCIÓN DE FECHA Y ARCHIVO ---
  void _iniciarTramiteManual({
    required String etiqueta, 
    required String campo, 
    required String idDocumento, 
    required String coleccion,
    required String nombreUsuario, 
  }) {
    final TextEditingController fechaCtrl = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        builder: (dCtx) => AlertDialog(
          backgroundColor: const Color(0xFF0D1D2D),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text("Actualizar: $etiqueta", style: const TextStyle(color: Colors.white, fontSize: 18)),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Nueva fecha de vencimiento:", style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 15),
                TextFormField(
                  controller: fechaCtrl,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, color: Colors.orangeAccent, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    hintText: "DD/MM/AAAA",
                    hintStyle: TextStyle(color: Colors.white24),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  final partes = fechaCtrl.text.split('/');
                  final fechaS = "${partes[2]}-${partes[1]}-${partes[0]}";
                  Navigator.pop(dCtx);
                  _mostrarSelectorArchivo(etiqueta, campo, fechaS, idDocumento, coleccion, nombreUsuario);
                }
              },
              child: const Text("SIGUIENTE", style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      );
    });
  }

  void _mostrarSelectorArchivo(String etiqueta, String campo, String fechaS, String id, String coleccion, String nombreUsuario) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF0D1D2D),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
        builder: (sCtx) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.orangeAccent),
                title: const Text("Tomar Foto", style: TextStyle(color: Colors.white)),
                onTap: () async {
                  final img = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70);
                  if (img != null) _enviarRevision(etiqueta, campo, File(img.path), fechaS, id, coleccion, nombreUsuario);
                  if (sCtx.mounted) Navigator.pop(sCtx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
                title: const Text("Subir Archivo / PDF", style: TextStyle(color: Colors.white)),
                onTap: () async {
                  final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'png']);
                  if (res != null) _enviarRevision(etiqueta, campo, File(res.files.single.path!), fechaS, id, coleccion, nombreUsuario);
                  if (sCtx.mounted) Navigator.pop(sCtx);
                },
              ),
            ],
          ),
        ),
      );
    });
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
      mensajeExito: "Solicitud de revisión enviada al administrador",
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
          Positioned.fill(child: Container(color: Colors.black.withAlpha(200))),

          SafeArea(
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dniUser).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: CircularProgressIndicator(color: Colors.white));

                var data = snapshot.data!.data() as Map<String, dynamic>;
                String nombreChofer = data['NOMBRE'] ?? "Sin Nombre";
                String pVehiculo = data['VEHICULO'] ?? "";
                String pEnganche = data['ENGANCHE'] ?? "";

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildTituloPrincipal("DOCUMENTACIÓN PERSONAL"),
                    _buildCardVencimiento(
                      titulo: "Licencia de Conducir", 
                      fecha: data['VENCIMIENTO_LICENCIA_DE_CONDUCIR'], 
                      campo: "VENCIMIENTO_LICENCIA_DE_CONDUCIR", 
                      urlArchivo: data['ARCHIVO_LICENCIA_DE_CONDUCIR'], 
                      idDoc: widget.dniUser,
                      onUpload: () => _iniciarTramiteManual(
                        etiqueta: "LICENCIA", campo: "VENCIMIENTO_LICENCIA_DE_CONDUCIR", idDocumento: widget.dniUser, 
                        coleccion: 'EMPLEADOS', nombreUsuario: nombreChofer
                      )
                    ),
                    _buildCardVencimiento(
                      titulo: "Curso Manejo Defensivo", 
                      fecha: data['VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO'], 
                      campo: "VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO", 
                      urlArchivo: data['ARCHIVO_CURSO_DE_MANEJO_DEFENSIVO'], 
                      idDoc: widget.dniUser,
                      onUpload: () => _iniciarTramiteManual(
                        etiqueta: "MANEJO DEFENSIVO", campo: "VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO", idDocumento: widget.dniUser, 
                        coleccion: 'EMPLEADOS', nombreUsuario: nombreChofer
                      )
                    ),
                    _buildCardVencimiento(
                      titulo: "Psicofísico", 
                      fecha: data['VENCIMIENTO_PSICOFISICO'], 
                      campo: "VENCIMIENTO_PSICOFISICO", 
                      urlArchivo: data['ARCHIVO_PSICOFISICO'], 
                      idDoc: widget.dniUser,
                      onUpload: () => _iniciarTramiteManual(
                        etiqueta: "PSICOFÍSICO", campo: "VENCIMIENTO_PSICOFISICO", idDocumento: widget.dniUser, 
                        coleccion: 'EMPLEADOS', nombreUsuario: nombreChofer
                      )
                    ),

                    const SizedBox(height: 30),
                    _buildTituloPrincipal("DOCUMENTACIÓN LABORAL"),
                    _buildCardVencimiento(
                      titulo: "Comprobante ART", 
                      fecha: data['VENCIMIENTO_ART'], 
                      campo: "VENCIMIENTO_ART", 
                      urlArchivo: data['ARCHIVO_ART'], 
                      idDoc: widget.dniUser,
                      onUpload: () => _iniciarTramiteManual(
                        etiqueta: "ART", campo: "VENCIMIENTO_ART", idDocumento: widget.dniUser, 
                        coleccion: 'EMPLEADOS', nombreUsuario: nombreChofer
                      )
                    ),
                    _buildCardVencimiento(
                      titulo: "Formulario 931 (AFIP)", 
                      fecha: data['VENCIMIENTO_931'], 
                      campo: "VENCIMIENTO_931", 
                      urlArchivo: data['ARCHIVO_931'], 
                      idDoc: widget.dniUser,
                      onUpload: () => _iniciarTramiteManual(
                        etiqueta: "F. 931", campo: "VENCIMIENTO_931", idDocumento: widget.dniUser, 
                        coleccion: 'EMPLEADOS', nombreUsuario: nombreChofer
                      )
                    ),
                    _buildCardVencimiento(
                      titulo: "Seguro de Vida Obligatorio", 
                      fecha: data['VENCIMIENTO_SEGURO_DE_VIDA'], 
                      campo: "VENCIMIENTO_SEGURO_DE_VIDA", 
                      urlArchivo: data['ARCHIVO_SEGURO_DE_VIDA'], 
                      idDoc: widget.dniUser,
                      onUpload: () => _iniciarTramiteManual(
                        etiqueta: "SEGURO DE VIDA", campo: "VENCIMIENTO_SEGURO_DE_VIDA", idDocumento: widget.dniUser, 
                        coleccion: 'EMPLEADOS', nombreUsuario: nombreChofer
                      )
                    ),
                    _buildCardVencimiento(
                      titulo: "Libre Deuda Sindical", 
                      fecha: data['VENCIMIENTO_LIBRE_DE_DEUDA_SINDICAL'], 
                      campo: "VENCIMIENTO_LIBRE_DE_DEUDA_SINDICAL", 
                      urlArchivo: data['ARCHIVO_LIBRE_DE_DEUDA_SINDICAL'], 
                      idDoc: widget.dniUser,
                      onUpload: () => _iniciarTramiteManual(
                        etiqueta: "LIBRE DEUDA SINDICAL", campo: "VENCIMIENTO_LIBRE_DE_DEUDA_SINDICAL", idDocumento: widget.dniUser, 
                        coleccion: 'EMPLEADOS', nombreUsuario: nombreChofer
                      )
                    ),

                    const SizedBox(height: 30),
                    _buildTituloPrincipal("VENCIMIENTOS DE EQUIPO"),
                    
                    if (pVehiculo.isNotEmpty && pVehiculo != "SIN ASIGNAR")
                      _buildDetalleVehiculo(pVehiculo, "VEHÍCULO", nombreChofer)
                    else
                      _buildCardVacia("No hay vehículo asignado"),

                    const SizedBox(height: 20),
                    if (pEnganche.isNotEmpty && pEnganche != "SIN ASIGNAR")
                      _buildDetalleVehiculo(pEnganche, "ENGANCHE", nombreChofer)
                    else
                      _buildCardVacia("No hay enganche asignado"),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetalleVehiculo(String patente, String tipoSeccion, String nombreChofer) => StreamBuilder<DocumentSnapshot>(
    stream: FirebaseFirestore.instance.collection('VEHICULOS').doc(patente).snapshots(),
    builder: (context, vehiculoSnap) {
      if (!vehiculoSnap.hasData || !vehiculoSnap.data!.exists) return _buildCardVacia("Patente $patente no encontrada");
      var vData = vehiculoSnap.data!.data() as Map<String, dynamic>;
      
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSubtituloUnidad("$tipoSeccion: $patente"),
          _buildCardVencimiento(
            titulo: "RTO", 
            fecha: vData['VENCIMIENTO_RTO'], 
            campo: "VENCIMIENTO_RTO", 
            urlArchivo: vData['ARCHIVO_RTO'],
            idDoc: patente,
            onUpload: () => _iniciarTramiteManual(
              etiqueta: "RTO", campo: "VENCIMIENTO_RTO", idDocumento: patente, 
              coleccion: 'VEHICULOS', nombreUsuario: nombreChofer
            )
          ),
          _buildCardVencimiento(
            titulo: "Póliza de Seguro", 
            fecha: vData['VENCIMIENTO_SEGURO'], 
            campo: "VENCIMIENTO_SEGURO", 
            urlArchivo: vData['ARCHIVO_SEGURO'], 
            idDoc: patente,
            onUpload: () => _iniciarTramiteManual(
              etiqueta: "PÓLIZA", campo: "VENCIMIENTO_SEGURO", idDocumento: patente, 
              coleccion: 'VEHICULOS', nombreUsuario: nombreChofer
            )
          ),
        ],
      );
    },
  );

  Widget _buildTituloPrincipal(String titulo) => Padding(
    padding: const EdgeInsets.only(bottom: 12), 
    child: Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueAccent, letterSpacing: 1.2))
  );

  Widget _buildSubtituloUnidad(String texto) => Container(
    margin: const EdgeInsets.symmetric(vertical: 8), 
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withAlpha(20), 
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white12)
    ),
    width: double.infinity,
    child: Text(texto, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12)),
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
        bool tieneRevisionPendiente = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
        int dias = AppFormatters.calcularDiasRestantes(fecha);
        bool hayArchivoDigital = urlArchivo != null && urlArchivo.isNotEmpty;

        // --- LÓGICA DE SEMÁFORO UNIFICADA ---
        Color colorEstado;
        String emoji;
        
        if (dias < 0) {
          colorEstado = Colors.red;         // ROJO: VENCIDO
          emoji = "❌";
        } else if (dias <= 14) {
          colorEstado = Colors.yellow;      // AMARILLO: 0 a 14 DÍAS
          emoji = "⚠️";
        } else if (dias <= 30) {
          colorEstado = Colors.greenAccent; // VERDE: 15 a 30 DÍAS
          emoji = "✅";
        } else {
          colorEstado = Colors.blueAccent;  // AZUL: +30 DÍAS
          emoji = "📄";
        }

        // --- DISPARAR NOTIFICACIÓN SI ES CRÍTICO (≤ 30 DÍAS) ---
        if (!tieneRevisionPendiente && dias <= 30) {
           NotificationService.mostrarAlertaVencimiento(
             id: campo.hashCode + idDoc.hashCode,
             titulo: "$emoji $titulo",
             mensaje: dias < 0 
                ? "¡VENCIDO! Regularizá tu situación ahora." 
                : "Vence en $dias días. Por favor, cargá el nuevo archivo.",
           );
        }

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: tieneRevisionPendiente ? Colors.blue.withAlpha(40) : Colors.white.withAlpha(20),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: tieneRevisionPendiente ? Colors.blue : colorEstado,
              width: (dias <= 14) ? 2 : 1, 
            ),
          ),
          child: ListTile(
            dense: true,
            leading: Icon(
              tieneRevisionPendiente ? Icons.history : Icons.circle, 
              color: tieneRevisionPendiente ? Colors.blue : colorEstado, 
              size: 14
            ),
            title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
            subtitle: Text(
              tieneRevisionPendiente ? "VERIFICACIÓN EN CURSO..." : "Vence: ${AppFormatters.formatearFecha(fecha)}", 
              style: TextStyle(fontSize: 11, color: tieneRevisionPendiente ? Colors.blue : Colors.white70)
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.visibility, color: hayArchivoDigital ? Colors.blueAccent : Colors.white10, size: 20),
                  onPressed: hayArchivoDigital ? () => _abrirArchivo(urlArchivo, titulo) : null,
                ),
                if (!tieneRevisionPendiente) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorEstado.withAlpha(40), 
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      dias < 0 ? "VENCIDO" : "$dias d.", 
                      style: TextStyle(color: colorEstado, fontWeight: FontWeight.bold, fontSize: 10)
                    ),
                  ),
                ],
                IconButton(
                  icon: Icon(
                    tieneRevisionPendiente ? Icons.hourglass_top : Icons.upload_file, 
                    color: tieneRevisionPendiente ? Colors.white24 : Colors.orangeAccent, 
                    size: 20
                  ), 
                  onPressed: tieneRevisionPendiente ? null : onUpload
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _buildCardVacia(String mensaje) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Colors.white.withAlpha(10), borderRadius: BorderRadius.circular(10)),
    child: Text(mensaje, style: const TextStyle(color: Colors.white38, fontStyle: FontStyle.italic, fontSize: 12)),
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
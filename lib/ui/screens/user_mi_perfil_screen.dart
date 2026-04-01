import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

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

  // --- DIÁLOGO CAMBIO CLAVE ---
  void _mostrarDialogoClave(String claveActual) {
    final TextEditingController antCtrl = TextEditingController();
    final TextEditingController nvaCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text("Seguridad: Cambiar Clave"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: antCtrl, obscureText: true, decoration: const InputDecoration(labelText: "Clave Anterior")),
            const SizedBox(height: 10),
            TextField(controller: nvaCtrl, obscureText: true, decoration: const InputDecoration(labelText: "Nueva Clave (mín. 4)")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text("CANCELAR")),
          ElevatedButton(
            onPressed: () {
              if (antCtrl.text != claveActual) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("La clave anterior es incorrecta")));
                return;
              }
              if (nvaCtrl.text.length < 4) return;
              Navigator.pop(dCtx);
              _ejecutarTareaAsincrona(
                tarea: () async => await FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dni).update({'CLAVE': nvaCtrl.text}),
                mensajeExito: "Contraseña actualizada",
              );
            },
            child: const Text("GUARDAR"),
          ),
        ],
      ),
    );
  }

  // --- GESTIÓN FOTO PERFIL ---
  void _mostrarOpcionesFoto() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.camera_alt), title: const Text("Cámara"), onTap: () { Navigator.pop(ctx); _seleccionarImagen(ImageSource.camera); }),
          ListTile(leading: const Icon(Icons.photo_library), title: const Text("Galería"), onTap: () { Navigator.pop(ctx); _seleccionarImagen(ImageSource.gallery); }),
        ]),
      ),
    );
  }

  Future<void> _seleccionarImagen(ImageSource source) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source, imageQuality: 50);
    if (image == null) return;
    _ejecutarTareaAsincrona(
      tarea: () async {
        String url = await _firebaseService.subirArchivoGenerico(archivo: File(image.path), rutaStorage: 'PERFILES/${widget.dni}.jpg');
        await FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dni).update({'FOTO_URL': url});
      },
      mensajeExito: "Foto actualizada",
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Mi Perfil"), backgroundColor: const Color(0xFF1A3A5A), foregroundColor: Colors.white),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dni).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: CircularProgressIndicator());
          var data = snapshot.data!.data() as Map<String, dynamic>;
          String claveActual = data['CLAVE'] ?? "";

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildHeader(data),
              const SizedBox(height: 30),
              _buildEquipoCard(data),
              const SizedBox(height: 20),
              _buildSeccionTitulo("DATOS PERSONALES"),
              _buildInfoTile("EMPRESA", data['EMPRESA'] ?? "---", Icons.business),
              _buildInfoTile("DNI", AppFormatters.formatearDNI(widget.dni), Icons.perm_identity),
              _buildInfoTile("NRO. TRÁMITE DNI", data['NRO_TRAMITE'] ?? "---", Icons.pin_outlined),
              _buildInfoTile("CUIL", _formatearCUIL(data['CUIL']), Icons.badge_outlined),
              _buildInfoTile("TELÉFONO", data['TELEFONO'] ?? "---", Icons.phone_android),
              const Divider(height: 40),
              
              // Botón de seguridad
              ElevatedButton.icon(
                onPressed: () => _mostrarDialogoClave(claveActual),
                icon: const Icon(Icons.lock_reset),
                label: const Text("CAMBIAR MI CONTRASEÑA"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade200, 
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 12)
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- WIDGETS DE APOYO ---
  Widget _buildHeader(Map<String, dynamic> data) {
    return Column(children: [
      Stack(children: [
        CircleAvatar(
          radius: 55, 
          backgroundColor: Colors.blueGrey.shade100, 
          backgroundImage: (data['FOTO_URL'] != null && data['FOTO_URL'].isNotEmpty) ? NetworkImage(data['FOTO_URL']) : null, 
          child: (data['FOTO_URL'] == null || data['FOTO_URL'].isEmpty) ? const Icon(Icons.person, size: 55, color: Colors.white) : null
        ),
        Positioned(bottom: 0, right: 0, child: GestureDetector(onTap: _mostrarOpcionesFoto, child: const CircleAvatar(radius: 18, backgroundColor: Color(0xFF1A3A5A), child: Icon(Icons.camera_alt, size: 18, color: Colors.white)))),
      ]),
      const SizedBox(height: 12),
      Text(data['CHOFER'] ?? "---", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _buildEquipoCard(Map<String, dynamic> data) {
    return Card(
      color: Colors.blue.shade50, 
      child: Padding(
        padding: const EdgeInsets.all(12), 
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround, 
          children: [
            _buildDatoUnidad("TRACTOR", data['TRACTOR'] ?? "---", Icons.local_shipping),
            _buildDatoUnidad("ACOPLADO", data['BATEA_TOLVA'] ?? "---", Icons.grid_view),
          ]
        )
      )
    );
  }

  String _formatearCUIL(String? cuil) {
    if (cuil == null || cuil.isEmpty) return "---";
    String limpia = cuil.replaceAll(RegExp(r'[^0-9]'), '');
    return limpia.length == 11 ? "${limpia.substring(0, 2)}-${limpia.substring(2, 10)}-${limpia.substring(10)}" : cuil;
  }

  Widget _buildSeccionTitulo(String t) => Padding(padding: const EdgeInsets.only(bottom: 10, left: 5), child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A3A5A), fontSize: 12)));
  Widget _buildInfoTile(String l, String v, IconData i) => ListTile(leading: Icon(i, color: Colors.blueGrey), title: Text(l, style: const TextStyle(fontSize: 11, color: Colors.grey)), subtitle: Text(v, style: const TextStyle(fontWeight: FontWeight.w500)), dense: true);
  Widget _buildDatoUnidad(String l, String v, IconData i) => Column(children: [Icon(i, color: const Color(0xFF1A3A5A)), Text(l, style: const TextStyle(fontSize: 10)), Text(v, style: const TextStyle(fontWeight: FontWeight.bold))]);
}
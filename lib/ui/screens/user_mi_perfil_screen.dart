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

  // --- MOTOR DE TAREAS ASÍNCRONAS (LOADING SEGURO) ---
  Future<void> _ejecutarTareaAsincrona({
    required Future<void> Function() tarea,
    required String mensajeExito,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.orangeAccent)),
    );

    try {
      await tarea();
      if (!mounted) return;
      Navigator.of(context).pop(); // Cierra Loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensajeExito), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Cierra Loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  // --- CAMBIO DE CONTRASEÑA ---
  void _mostrarDialogoClave(String passwordActual) {
    final TextEditingController antCtrl = TextEditingController();
    final TextEditingController nvaCtrl = TextEditingController();
    
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1D2D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Seguridad: Cambiar Clave", style: TextStyle(color: Colors.white, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: antCtrl, 
              obscureText: true, 
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Contraseña Actual", 
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24))
              )
            ),
            const SizedBox(height: 15),
            TextField(
              controller: nvaCtrl, 
              obscureText: true, 
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Nueva Contraseña", 
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24))
              )
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text("CANCELAR", style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () {
              if (antCtrl.text.trim() != passwordActual.trim()) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("La contraseña actual es incorrecta")));
                return;
              }
              if (nvaCtrl.text.trim().length < 4) {
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mínimo 4 caracteres")));
                 return;
              }
              Navigator.pop(dCtx);
              _ejecutarTareaAsincrona(
                tarea: () async => await FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dni).update({'CONTRASEÑA': nvaCtrl.text.trim()}),
                mensajeExito: "Contraseña actualizada correctamente",
              );
            },
            child: const Text("GUARDAR", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // --- GESTIÓN DE FOTO DE PERFIL ---
  void _mostrarOpcionesFoto() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1D2D),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.camera_alt, color: Colors.blueAccent), 
            title: const Text("Cámara", style: TextStyle(color: Colors.white)), 
            onTap: () { Navigator.pop(ctx); _seleccionarImagen(ImageSource.camera); }
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: Colors.blueAccent), 
            title: const Text("Galería de Fotos", style: TextStyle(color: Colors.white)), 
            onTap: () { Navigator.pop(ctx); _seleccionarImagen(ImageSource.gallery); }
          ),
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
        String url = await _firebaseService.subirArchivoGenerico(
          archivo: File(image.path), 
          rutaStorage: 'PERFILES/${widget.dni}.jpg'
        );
        await FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dni).update({'ARCHIVO_PERFIL': url});
      },
      mensajeExito: "Foto de perfil actualizada",
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Mi Perfil de Legajo"),
        centerTitle: true,
        backgroundColor: Colors.transparent, 
        elevation: 0, 
        foregroundColor: Colors.white
      ),
      body: Stack(
        children: [
          Positioned.fill(child: Image.asset('assets/images/fondo_login.jpg', fit: BoxFit.cover)),
          Positioned.fill(child: Container(color: Colors.black.withAlpha(220))),
          
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dni).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return const Center(child: CircularProgressIndicator(color: Colors.orangeAccent));
              }
              var data = snapshot.data!.data() as Map<String, dynamic>;
              
              return SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildHeader(data), 
                    const SizedBox(height: 30),
                    _buildEquipoCard(data),
                    const SizedBox(height: 30),
                    _buildSeccionTitulo("DATOS PERSONALES"),
                    
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(20),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white10)
                      ),
                      child: Column(
                        children: [
                          _buildInfoTile("RAZÓN SOCIAL", data['EMPRESA'] ?? "---", Icons.business),
                          _buildInfoTile("DNI / LEGAJO", AppFormatters.formatearDNI(widget.dni), Icons.badge),
                          _buildInfoTile("CUIL", _formatearCUIL(data['CUIL']), Icons.assignment_ind),
                          _buildInfoTile("TELÉFONO", data['TELEFONO'] ?? "---", Icons.phone_android, isLast: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    
                    ElevatedButton.icon(
                      onPressed: () => _mostrarDialogoClave(data['CONTRASEÑA'] ?? ""),
                      icon: const Icon(Icons.password_rounded),
                      label: const Text("CAMBIAR MI CONTRASEÑA"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent.withAlpha(100),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic> data) {
    String? fotoUrl = data['ARCHIVO_PERFIL'];
    return Column(children: [
      Stack(children: [
        CircleAvatar(
          radius: 65, 
          backgroundColor: Colors.white12, 
          backgroundImage: (fotoUrl != null && fotoUrl.isNotEmpty) ? NetworkImage(fotoUrl) : null, 
          child: (fotoUrl == null || fotoUrl.isEmpty) ? const Icon(Icons.person, size: 70, color: Colors.white24) : null
        ),
        Positioned(
          bottom: 0, right: 0, 
          child: GestureDetector(
            onTap: _mostrarOpcionesFoto, 
            child: const CircleAvatar(radius: 20, backgroundColor: Colors.orangeAccent, child: Icon(Icons.camera_alt, size: 18, color: Colors.black))
          )
        ),
      ]),
      const SizedBox(height: 15),
      Text(data['NOMBRE'] ?? "Usuario", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
      const Text("CHOFER PROFESIONAL", style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2)),
    ]);
  }

  Widget _buildEquipoCard(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12)
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround, 
        children: [
          _buildDatoEquipo("TRACTOR", data['VEHICULO'] ?? "---", Icons.local_shipping),
          Container(width: 1, height: 40, color: Colors.white10),
          _buildDatoEquipo("ENGANCHE", data['ENGANCHE'] ?? "---", Icons.grid_view),
        ]
      )
    );
  }

  String _formatearCUIL(String? cuil) {
    if (cuil == null || cuil.isEmpty) return "---";
    String l = cuil.replaceAll(RegExp(r'[^0-9]'), '');
    if (l.length != 11) return cuil;
    return "${l.substring(0, 2)}-${l.substring(2, 10)}-${l.substring(10)}";
  }

  Widget _buildSeccionTitulo(String t) => Padding(padding: const EdgeInsets.only(bottom: 10, left: 10), child: Text(t, style: const TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)));
  
  Widget _buildInfoTile(String l, String v, IconData i, {bool isLast = false}) {
    return Column(children: [
      ListTile(
        leading: Icon(i, color: Colors.orangeAccent, size: 20), 
        title: Text(l, style: const TextStyle(fontSize: 9, color: Colors.white38, fontWeight: FontWeight.bold)), 
        subtitle: Text(v, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)), 
        dense: true
      ),
      if (!isLast) const Divider(color: Colors.white10, indent: 60, height: 1),
    ]);
  }

  Widget _buildDatoEquipo(String l, String v, IconData i) => Column(children: [
    Icon(i, color: Colors.orangeAccent, size: 28), 
    const SizedBox(height: 5),
    Text(l, style: const TextStyle(fontSize: 9, color: Colors.white38, fontWeight: FontWeight.bold)), 
    Text(v, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16, letterSpacing: 1.5))
  ]);
}
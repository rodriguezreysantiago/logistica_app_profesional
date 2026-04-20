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
      builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      await tarea();
      if (!mounted) return;
      Navigator.of(context).pop(); // Quitar loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensajeExito), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Quitar loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  // --- DIÁLOGO CAMBIO CONTRASEÑA ---
  void _mostrarDialogoClave(String passwordActual) {
    final TextEditingController antCtrl = TextEditingController();
    final TextEditingController nvaCtrl = TextEditingController();
    
    // CORRECCIÓN MOUSE TRACKER PARA WINDOWS
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        builder: (dCtx) => AlertDialog(
          backgroundColor: const Color(0xFF0D1D2D),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Seguridad: Cambiar Contraseña", style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: antCtrl, 
                  obscureText: true, 
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "Contraseña Anterior", 
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24))
                  )),
              const SizedBox(height: 10),
              TextField(
                  controller: nvaCtrl, 
                  obscureText: true, 
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "Nueva Contraseña (mín. 4)", 
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24))
                  )),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text("CANCELAR", style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
              onPressed: () {
                if (antCtrl.text != passwordActual) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("La contraseña anterior es incorrecta")));
                  return;
                }
                if (nvaCtrl.text.length < 4) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("La clave debe tener al menos 4 caracteres")));
                   return;
                }
                Navigator.pop(dCtx);
                _ejecutarTareaAsincrona(
                  tarea: () async => await FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dni).update({'CONTRASEÑA': nvaCtrl.text}),
                  mensajeExito: "Contraseña actualizada correctamente",
                );
              },
              child: const Text("GUARDAR"),
            ),
          ],
        ),
      );
    });
  }

  // --- GESTIÓN FOTO PERFIL ---
  void _mostrarOpcionesFoto() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF0D1D2D),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
        builder: (ctx) => SafeArea(
          child: Wrap(children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white), 
              title: const Text("Cámara", style: TextStyle(color: Colors.white)), 
              onTap: () { Navigator.pop(ctx); _seleccionarImagen(ImageSource.camera); }
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white), 
              title: const Text("Galería", style: TextStyle(color: Colors.white)), 
              onTap: () { Navigator.pop(ctx); _seleccionarImagen(ImageSource.gallery); }
            ),
          ]),
        ),
      );
    });
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
        title: const Text("Mi Perfil"), 
        centerTitle: true,
        backgroundColor: Colors.transparent, 
        elevation: 0, 
        foregroundColor: Colors.white
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/fondo_login.jpg', fit: BoxFit.cover, 
              errorBuilder: (context, error, stackTrace) => Container(color: const Color(0xFF0D1D2D))),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withAlpha(200)),
          ),
          
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dni).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return const Center(child: CircularProgressIndicator(color: Colors.orangeAccent));
              }
              var data = snapshot.data!.data() as Map<String, dynamic>;
              String passwordActual = data['CONTRASEÑA'] ?? "";

              return SafeArea(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  children: [
                    _buildHeader(data), 
                    const SizedBox(height: 30),
                    _buildEquipoCard(data),
                    const SizedBox(height: 25),
                    _buildSeccionTitulo("DATOS PERSONALES"),
                    
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white10)
                      ),
                      child: Column(
                        children: [
                          _buildInfoTile("EMPRESA", data['EMPRESA'] ?? "---", Icons.business),
                          _buildInfoTile("DNI", AppFormatters.formatearDNI(widget.dni), Icons.perm_identity),
                          _buildInfoTile("CUIL", _formatearCUIL(data['CUIL']), Icons.badge_outlined),
                          _buildInfoTile("TELÉFONO", data['TELEFONO'] ?? "---", Icons.phone_android, isLast: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    
                    ElevatedButton.icon(
                      onPressed: () => _mostrarDialogoClave(passwordActual),
                      icon: const Icon(Icons.lock_reset),
                      label: const Text("CAMBIAR MI CONTRASEÑA"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withAlpha(20), 
                        foregroundColor: Colors.white,
                        elevation: 0,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // --- WIDGETS DE APOYO ---
  Widget _buildHeader(Map<String, dynamic> data) {
    String? fotoUrl = data['ARCHIVO_PERFIL'];
    String nombreUsuario = data['NOMBRE'] ?? "---";

    return Column(children: [
      Stack(children: [
        CircleAvatar(
          radius: 65, 
          backgroundColor: Colors.white12, 
          backgroundImage: (fotoUrl != null && fotoUrl.isNotEmpty) ? NetworkImage(fotoUrl) : null, 
          child: (fotoUrl == null || fotoUrl.isEmpty) ? const Icon(Icons.person, size: 70, color: Colors.white38) : null
        ),
        Positioned(
          bottom: 0, 
          right: 5, 
          child: GestureDetector(
            onTap: _mostrarOpcionesFoto, 
            child: const CircleAvatar(radius: 22, backgroundColor: Colors.blueAccent, child: Icon(Icons.camera_alt, size: 20, color: Colors.white))
          )
        ),
      ]),
      const SizedBox(height: 15),
      Text(nombreUsuario, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
      const Text("Personal de la Empresa", style: TextStyle(color: Colors.white54, fontSize: 14)),
    ]);
  }

  Widget _buildEquipoCard(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blueAccent.withAlpha(40), Colors.black26]
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blueAccent.withAlpha(60))
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround, 
        children: [
          _buildDatoUnidad("VEHÍCULO", data['VEHICULO'] ?? "---", Icons.local_shipping),
          Container(width: 1, height: 45, color: Colors.white12),
          _buildDatoUnidad("ENGANCHE", data['ENGANCHE'] ?? "---", Icons.grid_view),
        ]
      )
    );
  }

  String _formatearCUIL(String? cuil) {
    if (cuil == null || cuil.isEmpty) return "---";
    String limpia = cuil.replaceAll(RegExp(r'[^0-9]'), '');
    return limpia.length == 11 ? "${limpia.substring(0, 2)}-${limpia.substring(2, 10)}-${limpia.substring(10)}" : cuil;
  }

  Widget _buildSeccionTitulo(String t) => Padding(padding: const EdgeInsets.only(bottom: 12, left: 5), child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, fontSize: 13, letterSpacing: 1.2)));
  
  Widget _buildInfoTile(String l, String v, IconData i, {bool isLast = false}) {
    return Column(
      children: [
        ListTile(
          leading: Icon(i, color: Colors.white54, size: 22), 
          title: Text(l, style: const TextStyle(fontSize: 10, color: Colors.white38, fontWeight: FontWeight.bold)), 
          subtitle: Text(v, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white, fontSize: 15)), 
          dense: true
        ),
        if (!isLast) const Divider(color: Colors.white10, indent: 60, endIndent: 20, height: 1),
      ],
    );
  }

  Widget _buildDatoUnidad(String l, String v, IconData i) => Column(children: [
    Icon(i, color: Colors.blueAccent, size: 30), 
    const SizedBox(height: 5),
    Text(l, style: const TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold)), 
    Text(v, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16))
  ]);
}
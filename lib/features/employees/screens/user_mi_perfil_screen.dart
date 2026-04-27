import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/firebase_service.dart';
import '../../../shared/utils/formatters.dart';

class UserMiPerfilScreen extends StatefulWidget {
  final String dni;
  const UserMiPerfilScreen({super.key, required this.dni});

  @override
  State<UserMiPerfilScreen> createState() => _UserMiPerfilScreenState();
}

class _UserMiPerfilScreenState extends State<UserMiPerfilScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  
  // ✅ MENTOR: Stream anclado para evitar lecturas duplicadas en Firebase
  late final Stream<DocumentSnapshot> _perfilStream;

  @override
  void initState() {
    super.initState();
    _perfilStream = FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dni).snapshots();
  }

  // --- MOTOR DE TAREAS ASÍNCRONAS (LOADING SEGURO) ---
  Future<void> _ejecutarTareaAsincrona({
    required Future<void> Function() tarea,
    required String mensajeExito,
  }) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.greenAccent)),
    );

    try {
      await tarea();
      navigator.pop(); // Cierra Loading
      messenger.showSnackBar(
        SnackBar(content: Text(mensajeExito, style: const TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.green),
      );
    } catch (e) {
      navigator.pop(); // Cierra Loading
      messenger.showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.redAccent),
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
        backgroundColor: Theme.of(context).colorScheme.surface, // ✅ MENTOR: Tema global
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withAlpha(20))
        ),
        title: const Text("Seguridad: Cambiar Clave", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: antCtrl, 
              obscureText: true, 
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "Contraseña Actual", 
                labelStyle: const TextStyle(color: Colors.white54),
                enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.primary))
              )
            ),
            const SizedBox(height: 15),
            TextField(
              controller: nvaCtrl, 
              obscureText: true, 
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "Nueva Contraseña", 
                labelStyle: const TextStyle(color: Colors.white54),
                enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.primary))
              )
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text("CANCELAR", style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () {
              if (antCtrl.text.trim() != passwordActual.trim()) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("La contraseña actual es incorrecta"), backgroundColor: Colors.redAccent));
                return;
              }
              if (nvaCtrl.text.trim().length < 4) {
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mínimo 4 caracteres"), backgroundColor: Colors.orangeAccent));
                 return;
              }
              Navigator.pop(dCtx);
              _ejecutarTareaAsincrona(
                tarea: () async => await FirebaseFirestore.instance.collection('EMPLEADOS').doc(widget.dni).update({'CONTRASEÑA': nvaCtrl.text.trim()}),
                mensajeExito: "Contraseña actualizada correctamente",
              );
            },
            child: const Text("GUARDAR", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // --- GESTIÓN DE FOTO DE PERFIL ---
  void _mostrarOpcionesFoto() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
          border: const Border(top: BorderSide(color: Colors.greenAccent, width: 2))
        ),
        child: SafeArea(
          child: Wrap(children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text("Actualizar Foto", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.greenAccent), 
              title: const Text("Tomar foto con la Cámara", style: TextStyle(color: Colors.white)), 
              onTap: () { Navigator.pop(ctx); _seleccionarImagen(ImageSource.camera); }
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.greenAccent), 
              title: const Text("Elegir de la Galería", style: TextStyle(color: Colors.white)), 
              onTap: () { Navigator.pop(ctx); _seleccionarImagen(ImageSource.gallery); }
            ),
            const SizedBox(height: 20),
          ]),
        ),
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
        title: const Text("Mi Perfil de Legajo", style: TextStyle(letterSpacing: 1.2)),
        centerTitle: true,
        backgroundColor: Colors.transparent, 
        elevation: 0, 
        foregroundColor: Colors.white
      ),
      body: Stack(
        children: [
          Positioned.fill(child: Image.asset('assets/images/fondo_login.jpg', fit: BoxFit.cover)),
          Positioned.fill(child: Container(color: Colors.black.withAlpha(200))),
          
          StreamBuilder<DocumentSnapshot>(
            stream: _perfilStream, // ✅ MENTOR: Stream en caché
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
              }
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return const Center(child: Text("Error al cargar datos", style: TextStyle(color: Colors.white54)));
              }
              
              var data = snapshot.data!.data() as Map<String, dynamic>;
              
              return SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildHeader(data), 
                    const SizedBox(height: 35),
                    _buildEquipoCard(data),
                    const SizedBox(height: 35),
                    _buildSeccionTitulo("DATOS PERSONALES"),
                    
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withAlpha(15))
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
                    const SizedBox(height: 35),
                    
                    ElevatedButton.icon(
                      onPressed: () => _mostrarDialogoClave(data['CONTRASEÑA'] ?? ""),
                      icon: const Icon(Icons.password_rounded),
                      label: const Text("CAMBIAR MI CONTRASEÑA", style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withAlpha(20),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                          side: const BorderSide(color: Colors.white24)
                        ),
                        elevation: 0,
                      ),
                    ),
                    const SizedBox(height: 20),
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
          backgroundColor: Colors.white10, 
          backgroundImage: (fotoUrl != null && fotoUrl.isNotEmpty) ? NetworkImage(fotoUrl) : null, 
          child: (fotoUrl == null || fotoUrl.isEmpty) ? const Icon(Icons.person, size: 70, color: Colors.white24) : null
        ),
        Positioned(
          bottom: 0, right: 0, 
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(50),
              onTap: _mostrarOpcionesFoto, 
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.greenAccent,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF0D1D2D), width: 3)
                ),
                child: const Icon(Icons.camera_alt, size: 20, color: Colors.black)
              )
            ),
          )
        ),
      ]),
      const SizedBox(height: 18),
      Text(data['NOMBRE'] ?? "Usuario", style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
      const SizedBox(height: 4),
      const Text("CHOFER PROFESIONAL", style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2)),
    ]);
  }

  Widget _buildEquipoCard(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(15))
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly, 
        children: [
          _buildDatoEquipo("TRACTOR", data['VEHICULO'] ?? "---", Icons.local_shipping),
          Container(width: 1, height: 50, color: Colors.white10),
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

  Widget _buildSeccionTitulo(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 12, left: 10), 
    child: Text(t, style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5))
  );
  
  Widget _buildInfoTile(String l, String v, IconData i, {bool isLast = false}) {
    return Column(children: [
      ListTile(
        leading: Icon(i, color: Colors.white54, size: 22), 
        title: Text(l, style: const TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1)), 
        subtitle: Text(v, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)), 
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      ),
      if (!isLast) const Divider(color: Colors.white10, indent: 60, height: 1),
    ]);
  }

  Widget _buildDatoEquipo(String l, String v, IconData i) => Column(children: [
    Icon(i, color: Colors.greenAccent, size: 30), 
    const SizedBox(height: 8),
    Text(l, style: const TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1)), 
    const SizedBox(height: 2),
    Text(v, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18, letterSpacing: 1.5))
  ]);
}
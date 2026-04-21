import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../core/utils/formatters.dart';
import 'admin_personal_form_screen.dart'; // Asegurate de que la ruta sea correcta

class AdminPersonalListaScreen extends StatefulWidget {
  const AdminPersonalListaScreen({super.key});

  @override
  State<AdminPersonalListaScreen> createState() => _AdminPersonalListaScreenState();
}

class _AdminPersonalListaScreenState extends State<AdminPersonalListaScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = "";

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() => _searchText = _searchController.text.toUpperCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatearCUIL(String cuil) {
    String limpio = cuil.replaceAll(RegExp(r'[^0-9]'), '');
    if (limpio.length == 11) {
      return "${limpio.substring(0, 2)}-${limpio.substring(2, 10)}-${limpio.substring(10)}";
    }
    return cuil;
  }

  // --- MÉTODO CENTRAL DE ACTUALIZACIÓN (BLINDADO) ---
  Future<void> _updateData(String coleccion, String docId, String campo, dynamic valor) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance
          .collection(coleccion)
          .doc(docId.trim())
          .update({
            campo: valor,
            "fecha_ultima_actualizacion": FieldValue.serverTimestamp(),
          });
      
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text("Actualizado: $campo"), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text("Error al actualizar: $e"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _gestionarFotoPerfil(String dni, String? urlActual) async {
    final ImagePicker picker = ImagePicker();
    final navigator = Navigator.of(context);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Foto de Perfil", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            ListTile(
              leading: const Icon(Icons.visibility, color: Colors.blue),
              title: const Text("Ver Foto Actual"),
              enabled: urlActual != null && urlActual.isNotEmpty && urlActual != "-",
              onTap: () async {
                final url = Uri.parse(urlActual!);
                if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.orange),
              title: const Text("Subir nueva desde Galería"),
              onTap: () async {
                navigator.pop();
                final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
                if (image != null) {
                  _subirArchivoFisico(dni, File(image.path), 'perfiles/$dni.jpg', 'ARCHIVO_PERFIL');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _subirArchivoFisico(String id, File file, String storagePath, String dbCampo) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(const SnackBar(content: Text("Subiendo archivo...")));
      Reference ref = FirebaseStorage.instance.ref().child(storagePath);
      await ref.putFile(file);
      String downloadUrl = await ref.getDownloadURL();
      
      await _updateData('EMPLEADOS', id, dbCampo, downloadUrl);
    } catch (e) {
      if (mounted) messenger.showSnackBar(const SnackBar(content: Text("Error al subir"), backgroundColor: Colors.red));
    }
  }

  void _gestionarDocumento({
    required String titulo,
    required String coleccion,
    required String docId,
    required String campoFecha,
    required String campoUrl,
    required String? fechaActual,
    required String? urlActual,
  }) {
    final navigator = Navigator.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            ListTile(
              leading: const Icon(Icons.calendar_today, color: Colors.blue),
              title: const Text("Editar Fecha de Vencimiento"),
              onTap: () {
                navigator.pop();
                _seleccionarFecha(coleccion, docId, campoFecha, fechaActual);
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility, color: Colors.green),
              title: const Text("Ver Documento Digital"),
              enabled: urlActual != null && urlActual.isNotEmpty,
              onTap: () async {
                final url = Uri.parse(urlActual!);
                if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _seleccionarFecha(String coleccion, String docId, String campo, String? fechaActual) async {
    DateTime initial = DateTime.tryParse(fechaActual ?? "") ?? DateTime.now();
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
    if (picked != null) {
      String nuevaFecha = picked.toString().split(' ')[0];
      await _updateData(coleccion, docId, campo, nuevaFecha);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Gestión de Personal"),
        centerTitle: true,
        backgroundColor: const Color(0xFF1A3A5A).withAlpha(230),
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.black),
              decoration: InputDecoration(
                hintText: "Nombre, Tractor o Enganche...",
                prefixIcon: const Icon(Icons.search),
                fillColor: Colors.white,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
      ),
      // --- BOTÓN FLOTANTE PARA ALTA ---
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AdminPersonalFormScreen()),
          );
        },
        backgroundColor: Colors.orangeAccent,
        icon: const Icon(Icons.person_add_alt_1, color: Colors.black),
        label: const Text("NUEVO CHOFER", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: Image.asset('assets/images/fondo_login.jpg', fit: BoxFit.cover)),
          Container(color: Colors.black.withAlpha(150)),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('EMPLEADOS').orderBy('NOMBRE').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.orangeAccent));
              
              final empleados = snapshot.data!.docs.where((doc) {
                var data = doc.data() as Map<String, dynamic>;
                String nombre = (data['NOMBRE'] ?? '').toString().toUpperCase();
                String tractor = (data['VEHICULO'] ?? '').toString().toUpperCase();
                String enganche = (data['ENGANCHE'] ?? '').toString().toUpperCase();
                return nombre.contains(_searchText) || tractor.contains(_searchText) || enganche.contains(_searchText);
              }).toList();

              return ListView.builder(
                padding: const EdgeInsets.only(top: 150, bottom: 80), // Más padding abajo por el FAB
                itemCount: empleados.length,
                itemBuilder: (context, index) {
                  var data = empleados[index].data() as Map<String, dynamic>;
                  String dni = empleados[index].id;
                  return _buildEmpleadoCard(dni, data);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmpleadoCard(String dni, Map<String, dynamic> data) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.white.withAlpha(25),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.white24,
          backgroundImage: (data['ARCHIVO_PERFIL'] != null && data['ARCHIVO_PERFIL'] != "-") 
              ? NetworkImage(data['ARCHIVO_PERFIL']) : null,
          child: (data['ARCHIVO_PERFIL'] == null || data['ARCHIVO_PERFIL'] == "-") 
              ? const Icon(Icons.person, color: Colors.white) : null,
        ),
        title: Text(data['NOMBRE'] ?? 'Sin nombre', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        subtitle: Text("Tractor: ${data['VEHICULO'] ?? '-'} | Enganche: ${data['ENGANCHE'] ?? '-'}", style: const TextStyle(color: Colors.white70)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white54),
        onTap: () => _mostrarDetalleChofer(context, dni),
      ),
    );
  }

  void _mostrarDetalleChofer(BuildContext context, String dni) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        builder: (sCtx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('EMPLEADOS').doc(dni).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              var data = snapshot.data!.data() as Map<String, dynamic>;

              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                children: [
                  Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
                  const SizedBox(height: 20),
                  _buildHeaderDetalle(dni, data),
                  const Divider(),
                  _buildSeccionTitulo(Icons.badge, "Documentación Personal"),
                  _buildDatoSimple("DNI", dni, (val) => _updateData('EMPLEADOS', dni, 'DNI', val)),
                  _buildDatoSimple("CUIL", _formatearCUIL(data['CUIL'] ?? "-"), (val) => _updateData('EMPLEADOS', dni, 'CUIL', val.replaceAll('-', ''))),
                  _buildDatoEmpresaSeleccionable("Empresa", data['EMPRESA'] ?? "-", (val) => _updateData('EMPLEADOS', dni, 'EMPRESA', val)),
                  
                  const Divider(),
                  _buildSeccionTitulo(Icons.folder_shared, "Vencimientos Críticos"),
                  _buildFilaDocumento("LICENCIA", "VENCIMIENTO_LICENCIA_DE_CONDUCIR", "ARCHIVO_LICENCIA_DE_CONDUCIR", data, dni),
                  _buildFilaDocumento("PSICOFÍSICO", "VENCIMIENTO_PSICOFISICO", "ARCHIVO_PSICOFISICO", data, dni),
                  _buildFilaDocumento("MANEJO DEFENSIVO", "VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO", "ARCHIVO_CURSO_DE_MANEJO_DEFENSIVO", data, dni),
                  
                  const Divider(),
                  _buildSeccionTitulo(Icons.work, "Seguros y Aportes"),
                  _buildFilaDocumento("ART", "VENCIMIENTO_ART", "ARCHIVO_ART", data, dni),
                  _buildFilaDocumento("F. 931", "VENCIMIENTO_931", "ARCHIVO_931", data, dni),
                  _buildFilaDocumento("SEGURO VIDA", "VENCIMIENTO_SEGURO_DE_VIDA", "ARCHIVO_SEGURO_DE_VIDA", data, dni),
                  
                  const Divider(),
                  _buildSeccionTitulo(Icons.local_shipping, "Unidades"),
                  _buildAsignacionUnidad(dni, "VEHICULO", "Tractor: ${data['VEHICULO'] ?? '-'}", data['VEHICULO'] ?? ""),
                  _buildAsignacionUnidad(dni, "ENGANCHE", "Enganche: ${data['ENGANCHE'] ?? '-'}", data['ENGANCHE'] ?? ""),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderDetalle(String dni, Map<String, dynamic> data) {
    return Column(
      children: [
        Stack(
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: const Color(0xFF1A3A5A),
              backgroundImage: (data['ARCHIVO_PERFIL'] != null && data['ARCHIVO_PERFIL'] != "-") ? NetworkImage(data['ARCHIVO_PERFIL']) : null,
              child: (data['ARCHIVO_PERFIL'] == null || data['ARCHIVO_PERFIL'] == "-") ? const Icon(Icons.person, size: 50, color: Colors.white) : null,
            ),
            Positioned(
              bottom: 0, right: 0,
              child: GestureDetector(
                onTap: () => _gestionarFotoPerfil(dni, data['ARCHIVO_PERFIL']),
                child: Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle), child: const Icon(Icons.edit, size: 20, color: Colors.white)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(data['NOMBRE'] ?? "Sin Nombre", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildFilaDocumento(String label, String campoFecha, String campoUrl, Map<String, dynamic> data, String dni) {
    return _buildDatoEditableCompleto(
      label, 
      data[campoFecha], 
      data[campoUrl], 
      () => _gestionarDocumento(
        titulo: label, 
        coleccion: 'EMPLEADOS', 
        docId: dni, 
        campoFecha: campoFecha, 
        campoUrl: campoUrl, 
        fechaActual: data[campoFecha], 
        urlActual: data[campoUrl]
      )
    );
  }

  Widget _buildDatoEditableCompleto(String etiqueta, String? fecha, String? url, VoidCallback onTap) {
    int dias = AppFormatters.calcularDiasRestantes(fecha ?? "");
    Color colorSemaforo = (dias < 0) ? Colors.red : (dias <= 14) ? Colors.orange : (dias <= 30) ? Colors.greenAccent : Colors.blueAccent;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Expanded(child: Text(etiqueta, style: const TextStyle(fontSize: 13))),
          if (url != null && url.isNotEmpty && url != "-") const Icon(Icons.file_present, size: 18, color: Colors.blue),
          const SizedBox(width: 8),
          Text(AppFormatters.formatearFecha(fecha ?? ""), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: colorSemaforo, borderRadius: BorderRadius.circular(4)),
            child: Text("${dias}d", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ]),
      ),
    );
  }

  Widget _buildAsignacionUnidad(String dni, String campo, String label, String actual) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: const Icon(Icons.edit, size: 20),
      onTap: () => _seleccionarUnidad(dni, campo, actual),
    );
  }

  void _seleccionarUnidad(String dni, String campo, String patenteActual) {
    List<String> tipos = (campo == 'VEHICULO') ? ['TRACTOR'] : ['BATEA', 'TOLVA', 'ACOPLADO'];
    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text("Asignar ${campo == 'VEHICULO' ? 'Tractor' : 'Enganche'}"),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('VEHICULOS').where('TIPO', whereIn: tipos).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              var unidades = snapshot.data!.docs;
              return ListView.builder(
                itemCount: unidades.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return ListTile(
                      leading: const Icon(Icons.not_interested, color: Colors.red),
                      title: const Text("SIN UNIDAD", style: TextStyle(color: Colors.red)),
                      onTap: () async {
                        if (patenteActual.isNotEmpty && patenteActual != "-") {
                          await FirebaseFirestore.instance.collection('VEHICULOS').doc(patenteActual).update({'ESTADO': 'LIBRE'});
                        }
                        await FirebaseFirestore.instance.collection('EMPLEADOS').doc(dni).update({campo: "-"});
                        if (!mounted) return;
                        navigator.pop();
                      },
                    );
                  }
                  var vData = unidades[index - 1].data() as Map<String, dynamic>;
                  String patente = unidades[index - 1].id;
                  if (vData['ESTADO'] == 'OCUPADO' && patente != patenteActual) return const SizedBox();
                  
                  return ListTile(
                    title: Text(patente),
                    trailing: patente == patenteActual ? const Icon(Icons.check, color: Colors.green) : null,
                    onTap: () async {
                      if (patenteActual.isNotEmpty && patenteActual != "-") {
                        await FirebaseFirestore.instance.collection('VEHICULOS').doc(patenteActual).update({'ESTADO': 'LIBRE'});
                      }
                      await FirebaseFirestore.instance.collection('VEHICULOS').doc(patente).update({'ESTADO': 'OCUPADO'});
                      await FirebaseFirestore.instance.collection('EMPLEADOS').doc(dni).update({campo: patente});
                      if (!mounted) return;
                      navigator.pop();
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDatoSimple(String etiqueta, String valor, Function(String) onEdit) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(etiqueta, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      subtitle: Text(valor, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      trailing: const Icon(Icons.edit, size: 18),
      onTap: () => _mostrarDialogoTexto(etiqueta, valor, onEdit),
    );
  }

  void _mostrarDialogoTexto(String titulo, String valorActual, Function(String) onSave) {
    TextEditingController controller = TextEditingController(text: valorActual);
    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text("Editar $titulo"),
        content: TextField(controller: controller, textCapitalization: TextCapitalization.characters),
        actions: [
          TextButton(onPressed: () => navigator.pop(), child: const Text("Cancelar")),
          ElevatedButton(onPressed: () { 
            onSave(controller.text.trim().toUpperCase()); 
            navigator.pop();
          }, child: const Text("Guardar"))
        ],
      ),
    );
  }

  void _mostrarDialogoEmpresa(String etiqueta, String valor, Function(String) onEdit) {
    final List<String> empresas = [
      "SUCESION DE VECCHI CARLOS LUIS CUIT: 20-08569424-4", 
      "VECCHI ARIEL Y VECCHI GRACIELA S.R.L (30-70910015-3)"
    ];
    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text("Seleccionar Empresa"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: empresas.map((e) => ListTile(
            title: Text(e, style: const TextStyle(fontSize: 12)),
            onTap: () { 
              onEdit(e); 
              navigator.pop();
            },
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildDatoEmpresaSeleccionable(String etiqueta, String valor, Function(String) onEdit) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(etiqueta, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      subtitle: Text(valor, style: const TextStyle(fontSize: 14)),
      trailing: const Icon(Icons.business, size: 18),
      onTap: () => _mostrarDialogoEmpresa(etiqueta, valor, onEdit),
    );
  }

  Widget _buildSeccionTitulo(IconData icono, String titulo) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Icon(icono, color: const Color(0xFF1A3A5A), size: 20),
        const SizedBox(width: 10),
        Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A3A5A))),
      ]),
    );
  }
}
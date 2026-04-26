import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../core/utils/formatters.dart';
import 'admin_personal_form_screen.dart'; 

class AdminPersonalListaScreen extends StatefulWidget {
  const AdminPersonalListaScreen({super.key});

  @override
  State<AdminPersonalListaScreen> createState() => _AdminPersonalListaScreenState();
}

class _AdminPersonalListaScreenState extends State<AdminPersonalListaScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = "";
  
  // ✅ MENTOR: Stream fijo para evitar lecturas duplicadas al buscar.
  late final Stream<QuerySnapshot> _empleadosStream;

  @override
  void initState() {
    super.initState();
    _empleadosStream = FirebaseFirestore.instance
        .collection('EMPLEADOS')
        .orderBy('NOMBRE')
        .snapshots();

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
        SnackBar(content: Text("Dato actualizado: $campo"), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text("Error al actualizar en base de datos: $e"), backgroundColor: Colors.redAccent),
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
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
          border: const Border(top: BorderSide(color: Colors.greenAccent, width: 2))
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Foto de Perfil", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 15),
            ListTile(
              leading: const Icon(Icons.visibility, color: Colors.blueAccent),
              title: const Text("Ver Foto Actual", style: TextStyle(color: Colors.white)),
              enabled: urlActual != null && urlActual.isNotEmpty && urlActual != "-",
              onTap: () async {
                final url = Uri.parse(urlActual!);
                if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.greenAccent),
              title: const Text("Subir nueva desde Galería", style: TextStyle(color: Colors.white)),
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
      
      // ✅ MENTOR: Agregamos metadatos para asegurar que el navegador sepa que es una imagen.
      SettableMetadata metadata = SettableMetadata(contentType: 'image/jpeg');
      await ref.putFile(file, metadata);
      
      String downloadUrl = await ref.getDownloadURL();
      await _updateData('EMPLEADOS', id, dbCampo, downloadUrl);
    } catch (e) {
      if (mounted) messenger.showSnackBar(const SnackBar(content: Text("Error al subir al servidor"), backgroundColor: Colors.redAccent));
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
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
          border: const Border(top: BorderSide(color: Colors.greenAccent, width: 2))
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 15),
            ListTile(
              leading: const Icon(Icons.calendar_today, color: Colors.blueAccent),
              title: const Text("Editar Fecha de Vencimiento", style: TextStyle(color: Colors.white)),
              onTap: () {
                navigator.pop();
                _seleccionarFecha(coleccion, docId, campoFecha, fechaActual);
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility, color: Colors.greenAccent),
              title: const Text("Ver Documento Digital", style: TextStyle(color: Colors.white)),
              enabled: urlActual != null && urlActual.isNotEmpty && urlActual != "-",
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
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text("Gestión de Personal"),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: "Nombre, Tractor o Enganche...",
                  prefixIcon: Icon(Icons.search, color: Colors.greenAccent),
                ),
              ),
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminPersonalFormScreen()));
          },
          backgroundColor: Colors.greenAccent,
          icon: const Icon(Icons.person_add_alt_1, color: Colors.black),
          label: const Text("NUEVO CHOFER", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
        body: Stack(
          children: [
            Positioned.fill(child: Image.asset('assets/images/fondo_login.jpg', fit: BoxFit.cover)),
            Container(color: Colors.black.withAlpha(200)),
            StreamBuilder<QuerySnapshot>(
              stream: _empleadosStream, // ✅ MENTOR: Stream filtrado en memoria
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Center(child: Text("Error al cargar personal", style: TextStyle(color: Colors.redAccent)));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
                
                final empleados = snapshot.data!.docs.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  String nombre = (data['NOMBRE'] ?? '').toString().toUpperCase();
                  String tractor = (data['VEHICULO'] ?? '').toString().toUpperCase();
                  String enganche = (data['ENGANCHE'] ?? '').toString().toUpperCase();
                  return nombre.contains(_searchText) || tractor.contains(_searchText) || enganche.contains(_searchText);
                }).toList();

                if (empleados.isEmpty) return const Center(child: Text("No se encontraron choferes", style: TextStyle(color: Colors.white54)));

                return ListView.builder(
                  padding: const EdgeInsets.only(top: 160, bottom: 90),
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
      ),
    );
  }

  Widget _buildEmpleadoCard(String dni, Map<String, dynamic> data) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF132538).withAlpha(200),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.white12,
          backgroundImage: (data['ARCHIVO_PERFIL'] != null && data['ARCHIVO_PERFIL'] != "-") 
              ? NetworkImage(data['ARCHIVO_PERFIL']) : null,
          child: (data['ARCHIVO_PERFIL'] == null || data['ARCHIVO_PERFIL'] == "-") 
              ? const Icon(Icons.person, color: Colors.white54) : null,
        ),
        title: Text(data['NOMBRE'] ?? 'Sin nombre', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        subtitle: Text("Unidad: ${data['VEHICULO'] ?? '-'} | Eng: ${data['ENGANCHE'] ?? '-'}", style: const TextStyle(color: Colors.white38, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
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
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
            border: const Border(top: BorderSide(color: Colors.greenAccent, width: 2))
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
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                  const SizedBox(height: 20),
                  _buildHeaderDetalle(dni, data),
                  const SizedBox(height: 10),
                  const Divider(color: Colors.white10),
                  _buildSeccionTitulo(Icons.badge, "Documentación Personal"),
                  _buildDatoSimple("DNI", dni, (val) => _updateData('EMPLEADOS', dni, 'DNI', val)),
                  _buildDatoSimple("CUIL", _formatearCUIL(data['CUIL'] ?? "-"), (val) => _updateData('EMPLEADOS', dni, 'CUIL', val.replaceAll('-', ''))),
                  _buildDatoEmpresaSeleccionable("Empresa", data['EMPRESA'] ?? "-", (val) => _updateData('EMPLEADOS', dni, 'EMPRESA', val)),
                  
                  const Divider(color: Colors.white10),
                  _buildSeccionTitulo(Icons.folder_shared, "Vencimientos Críticos"),
                  _buildFilaDocumento("LICENCIA", "VENCIMIENTO_LICENCIA_DE_CONDUCIR", "ARCHIVO_LICENCIA_DE_CONDUCIR", data, dni),
                  _buildFilaDocumento("PSICOFÍSICO", "VENCIMIENTO_PSICOFISICO", "ARCHIVO_PSICOFISICO", data, dni),
                  _buildFilaDocumento("MANEJO DEFENSIVO", "VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO", "ARCHIVO_CURSO_DE_MANEJO_DEFENSIVO", data, dni),
                  
                  const Divider(color: Colors.white10),
                  _buildSeccionTitulo(Icons.work, "Seguros y Aportes"),
                  _buildFilaDocumento("ART", "VENCIMIENTO_ART", "ARCHIVO_ART", data, dni),
                  _buildFilaDocumento("F. 931", "VENCIMIENTO_931", "ARCHIVO_931", data, dni),
                  _buildFilaDocumento("SEGURO VIDA", "VENCIMIENTO_SEGURO_DE_VIDA", "ARCHIVO_SEGURO_DE_VIDA", data, dni),
                  
                  const Divider(color: Colors.white10),
                  _buildSeccionTitulo(Icons.local_shipping, "Asignación de Unidades"),
                  _buildAsignacionUnidad(dni, "VEHICULO", "Tractor: ${data['VEHICULO'] ?? '-'}", data['VEHICULO'] ?? ""),
                  _buildAsignacionUnidad(dni, "ENGANCHE", "Enganche: ${data['ENGANCHE'] ?? '-'}", data['ENGANCHE'] ?? ""),
                  const SizedBox(height: 30),
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
              backgroundColor: Colors.white12,
              backgroundImage: (data['ARCHIVO_PERFIL'] != null && data['ARCHIVO_PERFIL'] != "-") ? NetworkImage(data['ARCHIVO_PERFIL']) : null,
              child: (data['ARCHIVO_PERFIL'] == null || data['ARCHIVO_PERFIL'] == "-") ? const Icon(Icons.person, size: 50, color: Colors.white24) : null,
            ),
            Positioned(
              bottom: 0, right: 0,
              child: GestureDetector(
                onTap: () => _gestionarFotoPerfil(dni, data['ARCHIVO_PERFIL']),
                child: Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle), child: const Icon(Icons.edit, size: 18, color: Colors.black)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(data['NOMBRE'] ?? "Sin Nombre", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
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
    Color colorSemaforo = (dias < 0) ? Colors.redAccent : (dias <= 14) ? Colors.orangeAccent : (dias <= 30) ? Colors.greenAccent : Colors.blueAccent;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Expanded(child: Text(etiqueta, style: const TextStyle(fontSize: 13, color: Colors.white70))),
          if (url != null && url.isNotEmpty && url != "-") const Icon(Icons.file_present, size: 18, color: Colors.blueAccent),
          const SizedBox(width: 8),
          Text(AppFormatters.formatearFecha(fecha ?? ""), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: colorSemaforo.withAlpha(50), borderRadius: BorderRadius.circular(6), border: Border.all(color: colorSemaforo, width: 0.5)),
            child: Text("${dias}d", style: TextStyle(color: colorSemaforo, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 5),
          const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
        ]),
      ),
    );
  }

  Widget _buildAsignacionUnidad(String dni, String campo, String label, String actual) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
      trailing: const Icon(Icons.sync_alt, size: 20, color: Colors.greenAccent),
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
          height: 350,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('VEHICULOS').where('TIPO', whereIn: tipos).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
              var unidades = snapshot.data!.docs;
              
              return ListView.builder(
                itemCount: unidades.length + 1,
                itemBuilder: (context, index) {
                  
                  Future<void> procesarCambio(String? patenteNueva) async {
                    try {
                      String cleanActual = patenteActual.trim();
                      final db = FirebaseFirestore.instance;
                      WriteBatch batch = db.batch();

                      if (patenteNueva != null && patenteNueva != "-") {
                        batch.update(db.collection('VEHICULOS').doc(patenteNueva), {'ESTADO': 'OCUPADO'});
                        batch.update(db.collection('EMPLEADOS').doc(dni), {campo: patenteNueva});
                      } else {
                        batch.update(db.collection('EMPLEADOS').doc(dni), {campo: "-"});
                      }

                      await batch.commit();

                      if (cleanActual.isNotEmpty && cleanActual != "-" && cleanActual != "S/D") {
                        try {
                          await db.collection('VEHICULOS').doc(cleanActual).update({'ESTADO': 'LIBRE'});
                        } catch(e) { debugPrint("Aviso: Unidad previa ya libre."); }
                      }
                    } catch (e) { debugPrint("Error en asignación: $e"); }
                    if (mounted) navigator.pop();
                  }

                  if (index == 0) {
                    return ListTile(
                      leading: const Icon(Icons.link_off, color: Colors.redAccent),
                      title: const Text("DESVINCULAR", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      onTap: () => procesarCambio(null),
                    );
                  }

                  var vDoc = unidades[index - 1];
                  var vData = vDoc.data() as Map<String, dynamic>;
                  String patenteItem = vDoc.id.trim();
                  
                  if (vData['ESTADO'] == 'OCUPADO' && patenteItem != patenteActual.trim()) return const SizedBox();
                  
                  return ListTile(
                    title: Text(patenteItem, style: const TextStyle(color: Colors.white, fontSize: 14)),
                    trailing: patenteItem == patenteActual.trim() ? const Icon(Icons.check_circle, color: Colors.greenAccent) : null,
                    onTap: () => procesarCambio(patenteItem),
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
      title: Text(etiqueta, style: const TextStyle(fontSize: 12, color: Colors.white38)),
      subtitle: Text(valor, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
      trailing: const Icon(Icons.edit_note, size: 22, color: Colors.greenAccent),
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
        content: TextField(
          controller: controller, 
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: "Escriba aquí..."),
        ),
        actions: [
          TextButton(onPressed: () => navigator.pop(), child: const Text("CANCELAR")),
          ElevatedButton(
            onPressed: () { 
              onSave(controller.text.trim().toUpperCase()); 
              navigator.pop();
            }, 
            child: const Text("GUARDAR")
          )
        ],
      ),
    );
  }

  void _mostrarDialogoEmpresa(String etiqueta, String valor, Function(String) onEdit) {
    final List<String> empresas = [
      "VECCHI ARIEL Y VECCHI GRACIELA S.R.L: (30-70910015-3)", 
      "SUCESION DE VECCHI CARLOS LUIS: (20-08569424-4)"
    ];
    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text("Seleccionar Empresa"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: empresas.map((e) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(e, style: const TextStyle(fontSize: 12, color: Colors.white)),
            onTap: () { onEdit(e); navigator.pop(); },
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildDatoEmpresaSeleccionable(String etiqueta, String valor, Function(String) onEdit) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(etiqueta, style: const TextStyle(fontSize: 12, color: Colors.white38)),
      subtitle: Text(valor, style: const TextStyle(fontSize: 13, color: Colors.white)),
      trailing: const Icon(Icons.business_center, size: 20, color: Colors.greenAccent),
      onTap: () => _mostrarDialogoEmpresa(etiqueta, valor, onEdit),
    );
  }

  Widget _buildSeccionTitulo(IconData icono, String titulo) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(children: [
        Icon(icono, color: Colors.greenAccent, size: 18),
        const SizedBox(width: 10),
        Text(titulo.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent, letterSpacing: 1.1, fontSize: 13)),
      ]),
    );
  }
}
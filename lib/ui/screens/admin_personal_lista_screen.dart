import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../core/utils/formatters.dart';

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
      setState(() => _searchText = _searchController.text.toUpperCase());
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
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance.collection(coleccion).doc(docId).update({campo: valor});
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text("Actualizado: $campo"), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text("Error al actualizar: $e"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _gestionarFotoPerfil(String dni, String? urlActual) async {
    final ImagePicker picker = ImagePicker();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
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
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.orange),
                title: const Text("Subir/Cambiar Foto"),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);
                  navigator.pop(); 
                  final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
                  if (image != null) {
                    try {
                      messenger.showSnackBar(const SnackBar(content: Text("Subiendo imagen...")));
                      File file = File(image.path);
                      String path = 'perfiles/$dni.jpg';
                      Reference ref = FirebaseStorage.instance.ref().child(path);
                      await ref.putFile(file);
                      String downloadUrl = await ref.getDownloadURL();
                      if (!mounted) return;
                      await _updateData('EMPLEADOS', dni, 'ARCHIVO_PERFIL', downloadUrl);
                    } catch (e) {
                      if (mounted) messenger.showSnackBar(const SnackBar(content: Text("Error al subir imagen"), backgroundColor: Colors.red));
                    }
                  }
                },
              ),
            ],
          ),
        ),
      );
    });
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
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
                  Navigator.pop(context);
                  _seleccionarFecha(coleccion, docId, campoFecha, fechaActual);
                },
              ),
              ListTile(
                leading: const Icon(Icons.visibility, color: Colors.green),
                title: const Text("Ver Archivo Actual"),
                enabled: urlActual != null && urlActual.isNotEmpty,
                onTap: () async {
                  final url = Uri.parse(urlActual!);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.upload_file, color: Colors.orange),
                title: const Text("Cargar Nuevo Archivo"),
                onTap: () {
                  // Aquí podrías disparar el picker manual si el admin quiere subirlo por su cuenta
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Función de carga manual en desarrollo")));
                },
              ),
            ],
          ),
        ),
      );
    });
  }

  Future<void> _seleccionarFecha(String coleccion, String docId, String campo, String? fechaActual) async {
    DateTime initial = DateTime.tryParse(fechaActual ?? "") ?? DateTime.now();
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      String nuevaFecha = picked.toString().split(' ')[0];
      if (!mounted) return;
      await _updateData(coleccion, docId, campo, nuevaFecha);
    }
  }

  void _seleccionarUnidad(String dni, String campo, String patenteActual) {
    List<String> tiposBuscados = (campo == 'VEHICULO') ? ['TRACTOR'] : ['BATEA', 'TOLVA', 'ACOPLADO'];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white.withValues(alpha: 0.95),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text("Asignar ${campo == 'VEHICULO' ? 'Tractor' : 'Enganche'}"),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('VEHICULOS').where('TIPO', whereIn: tiposBuscados).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                var unidades = snapshot.data!.docs.where((doc) {
                  var vData = doc.data() as Map<String, dynamic>;
                  return vData['ESTADO'] == 'LIBRE' || doc.id == patenteActual;
                }).toList();

                return Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.not_interested, color: Colors.red),
                      title: const Text("SIN UNIDAD (LIBRE)", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                      onTap: () async {
                        if (patenteActual.isNotEmpty && patenteActual != "-") {
                          await FirebaseFirestore.instance.collection('VEHICULOS').doc(patenteActual).update({'ESTADO': 'LIBRE'});
                        }
                        await FirebaseFirestore.instance.collection('EMPLEADOS').doc(dni).update({campo: "-"});
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: unidades.length,
                        itemBuilder: (context, index) {
                          String patente = unidades[index].id;
                          var vData = unidades[index].data() as Map<String, dynamic>;
                          bool seleccionada = patente == patenteActual;
                          return ListTile(
                            leading: Icon(vData['TIPO'] == 'TRACTOR' ? Icons.local_shipping : Icons.grid_view, 
                                          color: seleccionada ? const Color(0xFF1A3A5A) : Colors.grey),
                            title: Text(patente),
                            subtitle: Text(vData['TIPO'] ?? ""),
                            trailing: seleccionada ? const Icon(Icons.check_circle, color: Colors.green) : null,
                            onTap: () async {
                              if (patenteActual.isNotEmpty && patenteActual != "-" && !seleccionada) {
                                await FirebaseFirestore.instance.collection('VEHICULOS').doc(patenteActual).update({'ESTADO': 'LIBRE'});
                              }
                              await FirebaseFirestore.instance.collection('VEHICULOS').doc(patente).update({'ESTADO': 'OCUPADO'});
                              await FirebaseFirestore.instance.collection('EMPLEADOS').doc(dni).update({campo: patente});
                              if (context.mounted) Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Gestión de Personal"),
        backgroundColor: const Color(0xFF1A3A5A).withValues(alpha: 0.85),
        foregroundColor: Colors.white,
        flexibleSpace: ClipRect(
          child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(color: Colors.transparent)),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Buscar por nombre, tractor o enganche...",
                prefixIcon: const Icon(Icons.search),
                fillColor: Colors.white.withValues(alpha: 0.9),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: Image.asset('assets/images/fondo_login.jpg', fit: BoxFit.cover)),
          Container(color: const Color(0xFF1A3A5A).withValues(alpha: 0.3)),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('EMPLEADOS').orderBy('NOMBRE').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.white));
              final empleados = snapshot.data!.docs.where((doc) {
                var data = doc.data() as Map<String, dynamic>;
                String nombre = (data['NOMBRE'] as String? ?? '').toUpperCase();
                String tractor = (data['VEHICULO'] as String? ?? '').toUpperCase();
                String batea = (data['ENGANCHE'] as String? ?? '').toUpperCase();
                return nombre.contains(_searchText) || tractor.contains(_searchText) || batea.contains(_searchText);
              }).toList();

              return ListView.builder(
                padding: const EdgeInsets.only(top: 150, bottom: 20),
                itemCount: empleados.length,
                itemBuilder: (context, index) {
                  var data = empleados[index].data() as Map<String, dynamic>;
                  String dni = empleados[index].id;
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        backgroundImage: (data['ARCHIVO_PERFIL'] != null && data['ARCHIVO_PERFIL'] != "-") ? NetworkImage(data['ARCHIVO_PERFIL']) : null,
                        child: (data['ARCHIVO_PERFIL'] == null || data['ARCHIVO_PERFIL'] == "-") ? const Icon(Icons.person, color: Colors.white) : null,
                      ),
                      title: Text(data['NOMBRE'] ?? 'Sin nombre', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      subtitle: Text("Tractor: ${data['VEHICULO'] ?? '-'} | Enganche: ${data['ENGANCHE'] ?? '-'}", style: const TextStyle(color: Colors.white70)),
                      trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                      onTap: () {
                         WidgetsBinding.instance.addPostFrameCallback((_) {
                           _mostrarDetalleChofer(context, dni);
                         });
                      },
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  void _mostrarDetalleChofer(BuildContext context, String dni) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('EMPLEADOS').doc(dni).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              var data = snapshot.data!.data() as Map<String, dynamic>;

              return SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
                    const SizedBox(height: 20),
                    Center(
                      child: Stack(
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
                    ),
                    const SizedBox(height: 15),
                    Center(child: Text(data['NOMBRE'] ?? "Sin Nombre", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                    const Divider(),

                    _buildSeccionTitulo(Icons.badge, "Documentación Personal"),
                    _buildDatoSimple("DNI", dni, (val) => _updateData('EMPLEADOS', dni, 'DNI', val)),
                    _buildDatoSimple("CUIL", _formatearCUIL(data['CUIL'] ?? "-"), (val) => _updateData('EMPLEADOS', dni, 'CUIL', val.replaceAll(RegExp(r'[^0-9]'), ''))),
                    _buildDatoEmpresaSeleccionable("Empresa", data['EMPRESA'] ?? "-", (val) => _updateData('EMPLEADOS', dni, 'EMPRESA', val)),
                    
                    const Divider(),
                    _buildDatoEditableCompleto(
                      "LICENCIA DE CONDUCIR", data['VENCIMIENTO_LICENCIA_DE_CONDUCIR'], data['ARCHIVO_LICENCIA_DE_CONDUCIR'], 
                      () => _gestionarDocumento(titulo: "LICENCIA", coleccion: 'EMPLEADOS', docId: dni, campoFecha: 'VENCIMIENTO_LICENCIA_DE_CONDUCIR', campoUrl: 'ARCHIVO_LICENCIA_DE_CONDUCIR', fechaActual: data['VENCIMIENTO_LICENCIA_DE_CONDUCIR'], urlActual: data['ARCHIVO_LICENCIA_DE_CONDUCIR'])
                    ),
                    _buildDatoEditableCompleto(
                      "PSICOFÍSICO", data['VENCIMIENTO_PSICOFISICO'], data['ARCHIVO_PSICOFISICO'], 
                      () => _gestionarDocumento(titulo: "PSICOFÍSICO", coleccion: 'EMPLEADOS', docId: dni, campoFecha: 'VENCIMIENTO_PSICOFISICO', campoUrl: 'ARCHIVO_PSICOFISICO', fechaActual: data['VENCIMIENTO_PSICOFISICO'], urlActual: data['ARCHIVO_PSICOFISICO'])
                    ),
                    _buildDatoEditableCompleto(
                      "MANEJO DEFENSIVO", data['VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO'], data['ARCHIVO_CURSO_DE_MANEJO_DEFENSIVO'], 
                      () => _gestionarDocumento(titulo: "MANEJO DEFENSIVO", coleccion: 'EMPLEADOS', docId: dni, campoFecha: 'VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO', campoUrl: 'ARCHIVO_CURSO_DE_MANEJO_DEFENSIVO', fechaActual: data['VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO'], urlActual: data['ARCHIVO_CURSO_DE_MANEJO_DEFENSIVO'])
                    ),

                    const Divider(),
                    _buildSeccionTitulo(Icons.work, "Documentación Laboral"),
                    _buildDatoEditableCompleto("VENCIMIENTO ART", data['VENCIMIENTO_ART'], data['ARCHIVO_ART'], () => _gestionarDocumento(titulo: "ART", coleccion: 'EMPLEADOS', docId: dni, campoFecha: 'VENCIMIENTO_ART', campoUrl: 'ARCHIVO_ART', fechaActual: data['VENCIMIENTO_ART'], urlActual: data['ARCHIVO_ART'])),
                    _buildDatoEditableCompleto("FORMULARIO 931", data['VENCIMIENTO_931'], data['ARCHIVO_931'], () => _gestionarDocumento(titulo: "F. 931", coleccion: 'EMPLEADOS', docId: dni, campoFecha: 'VENCIMIENTO_931', campoUrl: 'ARCHIVO_931', fechaActual: data['VENCIMIENTO_931'], urlActual: data['ARCHIVO_931'])),
                    _buildDatoEditableCompleto("SEGURO DE VIDA", data['VENCIMIENTO_SEGURO_DE_VIDA'], data['ARCHIVO_SEGURO_DE_VIDA'], () => _gestionarDocumento(titulo: "SEGURO DE VIDA", coleccion: 'EMPLEADOS', docId: dni, campoFecha: 'VENCIMIENTO_SEGURO_DE_VIDA', campoUrl: 'ARCHIVO_SEGURO_DE_VIDA', fechaActual: data['VENCIMIENTO_SEGURO_DE_VIDA'], urlActual: data['ARCHIVO_SEGURO_DE_VIDA'])),
                    _buildDatoEditableCompleto("LIBRE DEUDA SINDICAL", data['VENCIMIENTO_LIBRE_DE_DEUDA_SINDICAL'], data['ARCHIVO_LIBRE_DE_DEUDA_SINDICAL'], () => _gestionarDocumento(titulo: "LIBRE DEUDA", coleccion: 'EMPLEADOS', docId: dni, campoFecha: 'VENCIMIENTO_LIBRE_DE_DEUDA_SINDICAL', campoUrl: 'ARCHIVO_LIBRE_DE_DEUDA_SINDICAL', fechaActual: data['VENCIMIENTO_LIBRE_DE_DEUDA_SINDICAL'], urlActual: data['ARCHIVO_LIBRE_DE_DEUDA_SINDICAL'])),

                    const Divider(),
                    _buildSeccionTitulo(Icons.local_shipping, "Unidades Asignadas"),
                    ListTile(contentPadding: EdgeInsets.zero, title: Text("TRACTOR: ${data['VEHICULO'] ?? 'No asignado'}"), trailing: const Icon(Icons.edit, size: 20), onTap: () => _seleccionarUnidad(dni, 'VEHICULO', data['VEHICULO'] ?? "")),
                    if (data['VEHICULO'] != null && data['VEHICULO'] != "-") _buildStreamVehiculoEdicion(data['VEHICULO']),
                    ListTile(contentPadding: EdgeInsets.zero, title: Text("ENGANCHE: ${data['ENGANCHE'] ?? 'No asignada'}"), trailing: const Icon(Icons.edit, size: 20), onTap: () => _seleccionarUnidad(dni, 'ENGANCHE', data['ENGANCHE'] ?? "")),
                    if (data['ENGANCHE'] != null && data['ENGANCHE'] != "-") _buildStreamVehiculoEdicion(data['ENGANCHE']),
                  ],
                ),
              );
            }
          ),
        ),
      ),
    );
  }

  Widget _buildStreamVehiculoEdicion(String patente) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('VEHICULOS').doc(patente).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox();
        var vData = snapshot.data!.data() as Map<String, dynamic>;
        return Container(
          padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            _buildDatoEditableCompleto("VENCIMIENTO RTO", vData['VENCIMIENTO_RTO'], vData['ARCHIVO_RTO'], () => _gestionarDocumento(titulo: "RTO - $patente", coleccion: 'VEHICULOS', docId: patente, campoFecha: 'VENCIMIENTO_RTO', campoUrl: 'ARCHIVO_RTO', fechaActual: vData['VENCIMIENTO_RTO'], urlActual: vData['ARCHIVO_RTO'])),
            _buildDatoEditableCompleto("VENCIMIENTO SEGURO", vData['VENCIMIENTO_SEGURO'], vData['ARCHIVO_SEGURO'], () => _gestionarDocumento(titulo: "Póliza - $patente", coleccion: 'VEHICULOS', docId: patente, campoFecha: 'VENCIMIENTO_SEGURO', campoUrl: 'ARCHIVO_SEGURO', fechaActual: vData['VENCIMIENTO_SEGURO'], urlActual: vData['ARCHIVO_SEGURO'])),
          ]),
        );
      },
    );
  }

  Widget _buildDatoEditableCompleto(String etiqueta, String? fecha, String? url, VoidCallback onTap) {
    int dias = AppFormatters.calcularDiasRestantes(fecha ?? "");
    
    // SEMÁFORO DE 4 NIVELES
    Color colorSemaforo;
    if (dias < 0) {
      colorSemaforo = Colors.red;         // Vencido
    } else if (dias <= 14) {
      colorSemaforo = Colors.orange;      // Crítico
    } else if (dias <= 30) {
      colorSemaforo = Colors.greenAccent; // Alerta
    } else {
      colorSemaforo = Colors.blueAccent;  // Seguro
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(child: Text(etiqueta, style: const TextStyle(fontSize: 13))),
          if (url != null && url.isNotEmpty) const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.file_present, size: 18, color: Colors.blue)),
          Text(AppFormatters.formatearFecha(fecha ?? ""), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), 
            decoration: BoxDecoration(color: colorSemaforo, borderRadius: BorderRadius.circular(4)), 
            child: Text("${dias}d", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ]),
      ),
    );
  }

  Widget _buildDatoSimple(String etiqueta, String valor, Function(String) onEdit) {
    return ListTile(contentPadding: EdgeInsets.zero, title: Text(etiqueta, style: const TextStyle(fontSize: 13, color: Colors.grey)), subtitle: Text(valor, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)), trailing: const Icon(Icons.edit, size: 18), onTap: () => _mostrarDialogoTexto(etiqueta, valor, onEdit));
  }

  void _mostrarDialogoTexto(String titulo, String valorActual, Function(String) onSave) {
    TextEditingController controller = TextEditingController(text: valorActual);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context, 
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white.withValues(alpha: 0.95),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text("Editar $titulo"),
          content: TextField(controller: controller, textCapitalization: TextCapitalization.characters),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")), 
            ElevatedButton(onPressed: () { onSave(controller.text.trim().toUpperCase()); Navigator.pop(context); }, child: const Text("Guardar"))
          ],
        ),
      );
    });
  }

  void _mostrarDialogoEmpresa(String etiqueta, String valor, Function(String) onEdit) {
    final List<String> empresas = ["SUCESION DE VECCHI CARLOS LUIS CUIT: 20-08569424-4", "VECCHI ARIEL Y VECCHI GRACIELA S.R.L (30-70910015-3)"]; 
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context, 
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white.withValues(alpha: 0.95), 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Seleccionar Empresa"), 
          content: Column(
            mainAxisSize: MainAxisSize.min, 
            children: empresas.map((e) => ListTile(
              title: Text(e, style: const TextStyle(fontSize: 12)), 
              onTap: () { onEdit(e); Navigator.pop(context); }
            )).toList()
          )
        )
      );
    });
  }

  Widget _buildDatoEmpresaSeleccionable(String etiqueta, String valor, Function(String) onEdit) {
    return ListTile(
      contentPadding: EdgeInsets.zero, 
      title: Text(etiqueta, style: const TextStyle(fontSize: 13, color: Colors.grey)), 
      subtitle: Text(valor, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)), 
      trailing: const Icon(Icons.business, size: 18),
      onTap: () => _mostrarDialogoEmpresa(etiqueta, valor, onEdit),
    );
  }

  Widget _buildSeccionTitulo(IconData icono, String titulo) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(children: [Icon(icono, color: const Color(0xFF1A3A5A), size: 20), const SizedBox(width: 10), Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A3A5A)))]));
  }
}
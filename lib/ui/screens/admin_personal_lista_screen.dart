import 'dart:io';
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

  // --- FUNCIÓN AUXILIAR PARA FORMATEAR CUIL ---
  String _formatearCUIL(String cuil) {
    String limpio = cuil.replaceAll(RegExp(r'[^0-9]'), '');
    if (limpio.length == 11) {
      return "${limpio.substring(0, 2)}-${limpio.substring(2, 10)}-${limpio.substring(10)}";
    }
    return cuil;
  }

  // --- FUNCIÓN GENÉRICA PARA ACTUALIZAR FIRESTORE ---
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

  // --- GESTIÓN DE FOTO DE PERFIL (CORREGIDO) ---
  Future<void> _gestionarFotoPerfil(String dni, String? urlActual) async {
    final ImagePicker picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
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
                // Capturamos el messenger antes de los procesos asíncronos
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);

                navigator.pop(); 

                final XFile? image = await picker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 50,
                );

                if (image != null) {
                  try {
                    messenger.showSnackBar(
                      const SnackBar(content: Text("Subiendo imagen..."), duration: Duration(seconds: 2)),
                    );

                    File file = File(image.path);
                    String path = 'perfiles/$dni.jpg';
                    Reference ref = FirebaseStorage.instance.ref().child(path);
                    
                    UploadTask uploadTask = ref.putFile(file);
                    TaskSnapshot snapshot = await uploadTask;

                    String downloadUrl = await snapshot.ref.getDownloadURL();
                    
                    // Verificamos si el widget sigue vivo antes de llamar a _updateData o usar context
                    if (!mounted) return;
                    await _updateData('EMPLEADOS', dni, 'FOTO_PERFIL', downloadUrl);

                  } catch (e) {
                    debugPrint("Error al subir foto: $e");
                    if (mounted) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text("Error al subir imagen"), backgroundColor: Colors.red),
                      );
                    }
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- GESTIÓN DE DOCUMENTOS ---
  void _gestionarDocumento({
    required String titulo,
    required String coleccion,
    required String docId,
    required String campoFecha,
    required String campoUrl,
    required String? fechaActual,
    required String? urlActual,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
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
              title: const Text("Subir/Actualizar Archivo"),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  // --- SELECCIONAR UNIDAD ---
  void _seleccionarUnidad(String dni, String campo, String patenteActual) {
    List<String> tiposBuscados = (campo == 'TRACTOR') ? ['TRACTOR'] : ['BATEA', 'TOLVA'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Asignar ${tiposBuscados.join('/')}"),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('VEHICULOS')
                .where('TIPO', whereIn: tiposBuscados)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
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
                      final nav = Navigator.of(context);
                      try {
                        if (patenteActual.isNotEmpty && patenteActual != "-") {
                          await FirebaseFirestore.instance.collection('VEHICULOS').doc(patenteActual).update({'ESTADO': 'LIBRE'});
                        }
                        await FirebaseFirestore.instance.collection('EMPLEADOS').doc(dni).update({campo: "-"});
                        if (!mounted) return;
                        nav.pop();
                      } catch (e) {
                        debugPrint("Error: $e");
                      }
                    },
                  ),
                  const Divider(),
                  if (unidades.isEmpty)
                    const Expanded(child: Center(child: Text("No hay unidades disponibles", style: TextStyle(fontStyle: FontStyle.italic))))
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: unidades.length,
                        itemBuilder: (context, index) {
                          String patente = unidades[index].id;
                          var vData = unidades[index].data() as Map<String, dynamic>;
                          bool seleccionada = patente == patenteActual;

                          return ListTile(
                            leading: Icon(
                              vData['TIPO'] == 'TRACTOR' ? Icons.local_shipping : Icons.airport_shuttle,
                              color: seleccionada ? const Color(0xFF1A3A5A) : Colors.grey,
                            ),
                            title: Text(patente),
                            subtitle: Text("Tipo: ${vData['TIPO']} - Estado: ${vData['ESTADO']}"),
                            trailing: seleccionada ? const Icon(Icons.check_circle, color: Colors.green) : null,
                            onTap: () async {
                              final nav = Navigator.of(context);
                              try {
                                if (patenteActual.isNotEmpty && patenteActual != "-" && !seleccionada) {
                                  await FirebaseFirestore.instance.collection('VEHICULOS').doc(patenteActual).update({'ESTADO': 'LIBRE'});
                                }
                                await FirebaseFirestore.instance.collection('VEHICULOS').doc(patente).update({'ESTADO': 'OCUPADO'});
                                await FirebaseFirestore.instance.collection('EMPLEADOS').doc(dni).update({campo: patente});
                                
                                if (!mounted) return;
                                nav.pop();
                              } catch (e) {
                                debugPrint("Error: $e");
                              }
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
  }

  Future<void> _seleccionarFecha(String coleccion, String docId, String campo, String? fechaActual) async {
    DateTime initial = DateTime.tryParse(fechaActual ?? "") ?? DateTime.now();
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      String nuevaFecha = picked.toString().split(' ')[0];
      if (!mounted) return;
      await _updateData(coleccion, docId, campo, nuevaFecha);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gestión de Personal"),
        backgroundColor: const Color(0xFF1A3A5A),
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Buscar por nombre o patente...",
                prefixIcon: const Icon(Icons.search),
                fillColor: Colors.white,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('EMPLEADOS').orderBy('CHOFER').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final empleados = snapshot.data!.docs.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            String nombre = (data['CHOFER'] as String? ?? '').toUpperCase();
            String tractor = (data['TRACTOR'] as String? ?? '').toUpperCase();
            String batea = (data['BATEA_TOLVA'] as String? ?? '').toUpperCase();
            
            return nombre.contains(_searchText) || 
                    tractor.contains(_searchText) || 
                    batea.contains(_searchText);
          }).toList();

          return ListView.builder(
            itemCount: empleados.length,
            itemBuilder: (context, index) {
              var data = empleados[index].data() as Map<String, dynamic>;
              String dni = empleados[index].id;
              
              bool coincideTractor = _searchText.isNotEmpty && (data['TRACTOR'] ?? '').toString().toUpperCase().contains(_searchText);
              bool coincideBatea = _searchText.isNotEmpty && (data['BATEA_TOLVA'] ?? '').toString().toUpperCase().contains(_searchText);

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF1A3A5A),
                    backgroundImage: (data['FOTO_PERFIL'] != null && data['FOTO_PERFIL'] != "-") 
                        ? NetworkImage(data['FOTO_PERFIL']) 
                        : null,
                    child: (data['FOTO_PERFIL'] == null || data['FOTO_PERFIL'] == "-") 
                        ? const Icon(Icons.person, color: Colors.white) 
                        : null,
                  ),
                  title: Text(data['CHOFER'] ?? 'Sin nombre', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Row(
                    children: [
                      Text("TRACTOR: ", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                      Text("${data['TRACTOR'] ?? '-'}", 
                        style: TextStyle(
                          fontWeight: coincideTractor ? FontWeight.bold : FontWeight.normal,
                          color: coincideTractor ? Colors.blue[900] : Colors.black87
                        )
                      ),
                      const Text(" | "),
                      Text("ENGANCHE: ", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                      Text("${data['BATEA_TOLVA'] ?? '-'}",
                        style: TextStyle(
                          fontWeight: coincideBatea ? FontWeight.bold : FontWeight.normal,
                          color: coincideBatea ? Colors.blue[900] : Colors.black87
                        )
                      ),
                    ],
                  ),
                  onTap: () => _mostrarDetalleChofer(context, dni),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _mostrarDetalleChofer(BuildContext context, String dni) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('EMPLEADOS').doc(dni).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            if (!snapshot.data!.exists) return const Center(child: Text("Empleado no encontrado"));
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
                          backgroundImage: (data['FOTO_PERFIL'] != null && data['FOTO_PERFIL'] != "-") 
                              ? NetworkImage(data['FOTO_PERFIL']) 
                              : null,
                          child: (data['FOTO_PERFIL'] == null || data['FOTO_PERFIL'] == "-")
                              ? const Icon(Icons.person, size: 50, color: Colors.white)
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () => _gestionarFotoPerfil(dni, data['FOTO_PERFIL']),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                              child: const Icon(Icons.edit, size: 20, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  Center(
                    child: Text(data['CHOFER'] ?? "Sin Nombre", 
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)
                    ),
                  ),
                  const Divider(),

                  _buildSeccionTitulo(Icons.badge, "Documentación Personal"),
                  _buildDatoSimple("DNI", dni, (val) => _updateData('EMPLEADOS', dni, 'DNI', val)),
                  _buildDatoSimple(
                    "CUIL", 
                    _formatearCUIL(data['CUIL'] ?? "-"), 
                    (val) {
                      String soloNumeros = val.replaceAll(RegExp(r'[^0-9]'), '');
                      _updateData('EMPLEADOS', dni, 'CUIL', soloNumeros);
                    }
                  ),
                  _buildDatoEmpresaSeleccionable("Empresa", data['EMPRESA'] ?? "-", (val) => _updateData('EMPLEADOS', dni, 'EMPRESA', val)),
                  const Divider(),
                  _buildDatoEditableCompleto("LICENCIA DE CONDUCIR", data['LIC_COND'], data['URL_LICENCIA'], 
                    () => _gestionarDocumento(
                      titulo: "LICENCIA DE CONDUCIR", coleccion: 'EMPLEADOS', docId: dni,
                      campoFecha: 'LIC_COND', campoUrl: 'URL_LICENCIA', fechaActual: data['LIC_COND'], urlActual: data['URL_LICENCIA']
                    )),
                  _buildDatoEditableCompleto("CURSO DE MANEJO DEFENSIVO", data['CURSO_MANEJO'], data['URL_CURSO'], 
                    () => _gestionarDocumento(
                      titulo: "CURSO DE MANEJO DEFENSIVO", coleccion: 'EMPLEADOS', docId: dni,
                      campoFecha: 'CURSO_MANEJO', campoUrl: 'URL_CURSO', fechaActual: data['CURSO_MANEJO'], urlActual: data['URL_CURSO']
                    )),
                  _buildDatoEditableCompleto("PREOCUPACIONAL", data['EPAP'], data['URL_EPAP'], 
                    () => _gestionarDocumento(
                      titulo: "PREOCUPACIONAL", coleccion: 'EMPLEADOS', docId: dni,
                      campoFecha: 'EPAP', campoUrl: 'URL_EPAP', fechaActual: data['EPAP'], urlActual: data['URL_EPAP']
                    )),
                  const SizedBox(height: 20),
                  _buildSeccionTitulo(Icons.local_shipping, "Unidades Asignadas"),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text("TRACTOR: ${data['TRACTOR'] ?? 'No asignado'}"),
                    trailing: const Icon(Icons.edit, size: 20),
                    onTap: () => _seleccionarUnidad(dni, 'TRACTOR', data['TRACTOR'] ?? ""),
                  ),
                  if (data['TRACTOR'] != null && data['TRACTOR'].toString().isNotEmpty && data['TRACTOR'] != "-")
                    _buildStreamVehiculoEdicion(data['TRACTOR']),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text("ENGANCHE: ${data['BATEA_TOLVA'] ?? 'No asignada'}"),
                    trailing: const Icon(Icons.edit, size: 20),
                    onTap: () => _seleccionarUnidad(dni, 'BATEA_TOLVA', data['BATEA_TOLVA'] ?? ""),
                  ),
                  if (data['BATEA_TOLVA'] != null && data['BATEA_TOLVA'].toString().isNotEmpty && data['BATEA_TOLVA'] != "-")
                    _buildStreamVehiculoEdicion(data['BATEA_TOLVA']),
                ],
              ),
            );
          }
        ),
      ),
    );
  }

  Widget _buildDatoEmpresaSeleccionable(String etiqueta, String valor, Function(String) onEdit) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      title: Text(etiqueta, style: const TextStyle(fontSize: 13, color: Colors.grey)),
      subtitle: Text(valor, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black)),
      trailing: const Icon(Icons.business, size: 18),
      onTap: () => _mostrarDialogoEmpresas(onEdit),
    );
  }

  void _mostrarDialogoEmpresas(Function(String) onSave) {
    final List<String> empresas = ["SUCESION DE VECCHI CARLOS LUIS CUIT: 20-08569424-4", "VECCHI ARIEL Y VECCHI GRACIELA S.R.L CUIT: 30-70910015-3"]; 
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Seleccionar Empresa"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: empresas.map((e) => ListTile(
            title: Text(e),
            onTap: () {
              onSave(e);
              Navigator.pop(context);
            },
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildDatoSimple(String etiqueta, String valor, Function(String) onEdit) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      title: Text(etiqueta, style: const TextStyle(fontSize: 13, color: Colors.grey)),
      subtitle: Text(valor, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black)),
      trailing: const Icon(Icons.edit, size: 18),
      onTap: () => _mostrarDialogoTexto(etiqueta, valor, onEdit),
    );
  }

  void _mostrarDialogoTexto(String titulo, String valorActual, Function(String) onSave) {
    TextEditingController customController = TextEditingController(text: valorActual);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Editar $titulo"),
        content: TextField(
          controller: customController, 
          decoration: const InputDecoration(border: OutlineInputBorder()),
          textCapitalization: TextCapitalization.characters,
          keyboardType: (titulo == "CUIL" || titulo == "DNI") ? TextInputType.number : TextInputType.text,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () {
              onSave(customController.text.trim().toUpperCase());
              Navigator.pop(context);
            },
            child: const Text("Guardar"),
          ),
        ],
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
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
          child: Column(
            children: [
              _buildDatoEditableCompleto("VTV", vData['VENCIMIENTO_RTO'], vData['URL_RTO'], 
                () => _gestionarDocumento(
                  titulo: "RTO - $patente", coleccion: 'VEHICULOS', docId: patente,
                  campoFecha: 'VENCIMIENTO_RTO', campoUrl: 'URL_RTO', fechaActual: vData['VENCIMIENTO_RTO'], urlActual: vData['URL_RTO']
                )),
              _buildDatoEditableCompleto("SEGURO", vData['VENCIMIENTO_POLIZA'], vData['URL_POLIZA'], 
                () => _gestionarDocumento(
                  titulo: "Póliza - $patente", coleccion: 'VEHICULOS', docId: patente,
                  campoFecha: 'VENCIMIENTO_POLIZA', campoUrl: 'URL_POLIZA', fechaActual: vData['VENCIMIENTO_POLIZA'], urlActual: vData['URL_POLIZA']
                )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDatoEditableCompleto(String etiqueta, String? fecha, String? url, VoidCallback onTap) {
    int dias = AppFormatters.calcularDiasRestantes(fecha ?? "");
    Color colorSemaforo = dias < 0 ? Colors.red : (dias <= 30 ? Colors.orange : Colors.green);
    bool tieneArchivo = url != null && url.isNotEmpty;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text(etiqueta, style: const TextStyle(fontSize: 13))),
            if (tieneArchivo)
              const Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: Icon(Icons.image, size: 18, color: Colors.blue),
              ),
            Text(AppFormatters.formatearFecha(fecha ?? ""), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: colorSemaforo, borderRadius: BorderRadius.circular(4)),
              child: Text("${dias}d", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildSeccionTitulo(IconData icono, String titulo) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [Icon(icono, color: const Color(0xFF1A3A5A), size: 20), const SizedBox(width: 10), Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A3A5A)))]),
    );
  }
}
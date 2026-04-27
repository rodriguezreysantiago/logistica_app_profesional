import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../../shared/utils/formatters.dart';
import '../services/volvo_api_service.dart';

class AdminVehiculoFormScreen extends StatefulWidget {
  final String vehiculoId;
  final Map<String, dynamic> datosIniciales;

  const AdminVehiculoFormScreen({
    super.key,
    required this.vehiculoId,
    required this.datosIniciales,
  });

  @override
  State<AdminVehiculoFormScreen> createState() => _AdminVehiculoFormScreenState();
}

class _AdminVehiculoFormScreenState extends State<AdminVehiculoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  bool _isSyncing = false;

  late TextEditingController _marcaController;
  late TextEditingController _modeloController;
  late TextEditingController _anioController;
  late TextEditingController _empresaController;
  late TextEditingController _vinController;
  late TextEditingController _kmController;

  String? _fechaRto;
  String? _fechaSeguro;
  String? _urlRto;
  String? _urlSeguro;

  @override
  void initState() {
    super.initState();
    _marcaController = TextEditingController(text: widget.datosIniciales['MARCA'] ?? '');
    _modeloController = TextEditingController(text: widget.datosIniciales['MODELO'] ?? '');
    _anioController = TextEditingController(text: (widget.datosIniciales['ANIO'] ?? widget.datosIniciales['AÑO'])?.toString() ?? '');
    _empresaController = TextEditingController(text: widget.datosIniciales['EMPRESA'] ?? '');
    _vinController = TextEditingController(text: widget.datosIniciales['VIN'] ?? '');
    _kmController = TextEditingController(text: widget.datosIniciales['KM_ACTUAL']?.toString() ?? '0');
    _fechaRto = widget.datosIniciales['VENCIMIENTO_RTO'];
    _fechaSeguro = widget.datosIniciales['VENCIMIENTO_SEGURO'];
    _urlRto = widget.datosIniciales['ARCHIVO_RTO'];
    _urlSeguro = widget.datosIniciales['ARCHIVO_SEGURO'];
  }

  @override
  void dispose() {
    _marcaController.dispose();
    _modeloController.dispose();
    _anioController.dispose();
    _empresaController.dispose();
    _vinController.dispose();
    _kmController.dispose();
    super.dispose();
  }

  Future<void> _subirDocumento(String campoUrl, String tipoDoc) async {
    final messenger = ScaffoldMessenger.of(context);

    File? fileToUpload;
    String fileName = "";

    // ✅ MENTOR: El BottomSheet ahora usa el color surface del Theme Global
    final int? source = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: const Border(top: BorderSide(color: Colors.greenAccent, width: 2))
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(15),
                child: Text("Adjuntar Documento", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.greenAccent),
                title: const Text("Tomar Foto", style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, 1),
              ),
              ListTile(
                leading: const Icon(Icons.file_present, color: Colors.blueAccent),
                title: const Text("Seleccionar Archivo (PDF/Imagen)", style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, 2),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );

    if (source == 1) {
      final XFile? photo = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 50);
      if (photo != null) {
        fileToUpload = File(photo.path);
        fileName = "${tipoDoc}_${DateTime.now().millisecondsSinceEpoch}.jpg";
      }
    } else if (source == 2) {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result != null) {
        fileToUpload = File(result.files.single.path!);
        fileName = result.files.single.name;
      }
    }

    if (fileToUpload != null) {
      setState(() => _isSaving = true);
      
      try {
        String path = "vehiculos/${widget.vehiculoId.trim()}/$fileName";
        Reference ref = FirebaseStorage.instance.ref().child(path);
        
        // ✅ MENTOR: Intentamos adivinar el tipo para que el navegador lo abra bien después
        SettableMetadata? metadata;
        if (fileName.toLowerCase().endsWith('.pdf')) {
          metadata = SettableMetadata(contentType: 'application/pdf');
        } else if (fileName.toLowerCase().endsWith('.jpg') || fileName.toLowerCase().endsWith('.jpeg')) {
          metadata = SettableMetadata(contentType: 'image/jpeg');
        }

        await ref.putFile(fileToUpload, metadata);
        String downloadUrl = await ref.getDownloadURL();

        if (mounted) {
          setState(() {
            if (tipoDoc == 'RTO') _urlRto = downloadUrl;
            if (tipoDoc == 'SEGURO') _urlSeguro = downloadUrl;
            _isSaving = false;
          });
          messenger.showSnackBar(
            SnackBar(content: Text("Documento $tipoDoc cargado."), backgroundColor: Colors.blueAccent),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isSaving = false);
          messenger.showSnackBar(SnackBar(content: Text("Error al subir: $e"), backgroundColor: Colors.redAccent));
        }
      }
    }
  }

  Future<void> _sincronizarConVolvoManual() async {
    final messenger = ScaffoldMessenger.of(context);

    if (_vinController.text.length < 10) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Se requiere un VIN válido (Mín. 10 caracteres)"), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    setState(() => _isSyncing = true);
    
    try {
      final metros = await VolvoApiService().traerKilometrajeCualquierVia(_vinController.text.trim().toUpperCase());
      
      if (!mounted) return;
      
      if (metros != null && metros > 0) {
        final double kmReal = metros / 1000;
        setState(() => _kmController.text = kmReal.toStringAsFixed(0));
        messenger.showSnackBar(
          const SnackBar(content: Text("¡Sincronizado! KM Actualizado."), backgroundColor: Colors.green),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text("Unidad en reposo o no encontrada en Volvo."), backgroundColor: Colors.orangeAccent),
        );
      }
    } catch (e) {
      debugPrint("Error sincro: $e");
      if (mounted) {
         messenger.showSnackBar(
          SnackBar(content: Text("Error de conexión con Volvo: $e"), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _seleccionarFecha(BuildContext context, bool esRto) async {
    final String? fechaActual = esRto ? _fechaRto : _fechaSeguro;
    final DateTime initialDate = (fechaActual != null && fechaActual.isNotEmpty) 
        ? DateTime.parse(fechaActual) 
        : DateTime.now();

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );

    if (picked != null && mounted) {
      setState(() {
        String f = picked.toString().split(' ')[0];
        if (esRto) {
          _fechaRto = f;
        } else {
          _fechaSeguro = f;
        }
      });
    }
  }

  void _mostrarSelectorEmpresa() {
    final List<String> empresas = [
      "VECCHI ARIEL Y VECCHI GRACIELA S.R.L: (30-70910015-3)",
      "SUCESION DE VECCHI CARLOS LUIS: (20-08569424-4)"
    ];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Seleccionar Empresa"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: empresas.map((e) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(e, style: const TextStyle(color: Colors.white, fontSize: 13)),
            onTap: () {
              setState(() => _empresaController.text = e);
              Navigator.pop(context);
            },
          )).toList(),
        ),
      ),
    );
  }

  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSaving) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _isSaving = true);
    
    try {
      final String idLimpio = widget.vehiculoId.trim().toUpperCase();
      
      await FirebaseFirestore.instance.collection('VEHICULOS').doc(idLimpio).update({
        'MARCA': _marcaController.text.trim().toUpperCase(),
        'MODELO': _modeloController.text.trim().toUpperCase(),
        'ANIO': int.tryParse(_anioController.text.trim()) ?? 0,
        'EMPRESA': _empresaController.text.trim().toUpperCase(),
        'VIN': _vinController.text.trim().toUpperCase(),
        'KM_ACTUAL': double.tryParse(_kmController.text) ?? 0.0,
        'VENCIMIENTO_RTO': _fechaRto ?? "",
        'VENCIMIENTO_SEGURO': _fechaSeguro ?? "",
        'ARCHIVO_RTO': _urlRto ?? "-",
        'ARCHIVO_SEGURO': _urlSeguro ?? "-",
        'fecha_ultima_actualizacion': FieldValue.serverTimestamp(),
      });
      
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text("Ficha actualizada con éxito"), backgroundColor: Colors.green)
      );
      navigator.pop();
      
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        messenger.showSnackBar(
          SnackBar(content: Text("Error al guardar: $e"), backgroundColor: Colors.redAccent)
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool esVolvo = _marcaController.text.toUpperCase().contains("VOLVO");

    // ✅ MENTOR: GestureDetector en la raíz cierra el teclado si tocan el fondo
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(title: Text("Ficha: ${widget.vehiculoId}")),
        body: Stack(
          children: [
            Positioned.fill(child: Image.asset('assets/images/fondo_login.jpg', fit: BoxFit.cover)),
            Positioned.fill(child: Container(color: Colors.black.withAlpha(200))),
            SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildSectionTitle("INFORMACIÓN TÉCNICA"),
                    
                    _buildTextField(
                      controller: _marcaController, 
                      label: "Marca del Fabricante", 
                      icon: Icons.branding_watermark,
                    ),
                    _buildTextField(
                      controller: _modeloController, 
                      label: "Modelo de la Unidad", 
                      icon: Icons.directions_car,
                    ),
                    _buildTextField(
                      controller: _anioController, 
                      label: "Año de Fabricación", 
                      icon: Icons.calendar_today, 
                      isNumber: true,
                    ),
                    
                    if (esVolvo) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withAlpha(20), 
                          borderRadius: BorderRadius.circular(14), 
                          border: Border.all(color: Colors.blueAccent.withAlpha(50))
                        ),
                        child: Column(children: [
                          _buildTextField(
                            controller: _vinController, 
                            label: "Código VIN (Volvo)", 
                            icon: Icons.fingerprint,
                            textInputAction: TextInputAction.done,
                          ),
                          const SizedBox(height: 15),
                          _isSyncing 
                            ? const CircularProgressIndicator(color: Colors.blueAccent) 
                            : SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _sincronizarConVolvoManual, 
                                  icon: const Icon(Icons.sync, color: Colors.blueAccent), 
                                  label: const Text("FORZAR SINCRO VOLVO", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.blueAccent),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                                  ),
                                ),
                              ),
                        ]),
                      ),
                      const SizedBox(height: 20),
                    ],

                    _buildTextField(
                      controller: _kmController, 
                      label: "Kilometraje Actual", 
                      icon: Icons.speed, 
                      isNumber: true,
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 10),
                    _buildEmpresaTile(),

                    const SizedBox(height: 35),
                    _buildSectionTitle("AUDITORÍA DE VENCIMIENTOS"),

                    _buildDatePickerTile(
                      "Vencimiento RTO", _fechaRto, _urlRto,
                      () => _seleccionarFecha(context, true),
                      () => _subirDocumento('ARCHIVO_RTO', 'RTO'),
                    ),
                    const Divider(color: Colors.white10, height: 1),
                    _buildDatePickerTile(
                      "Póliza de Seguro", _fechaSeguro, _urlSeguro,
                      () => _seleccionarFecha(context, false),
                      () => _subirDocumento('ARCHIVO_SEGURO', 'SEGURO'),
                    ),

                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _guardarCambios, 
                        icon: _isSaving 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) 
                          : const Icon(Icons.save), 
                        label: Text(
                          _isSaving ? "GUARDANDO..." : "GUARDAR CAMBIOS",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                        ), 
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15, left: 5), 
      child: Text(title, style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5))
    );
  }

  // ✅ MENTOR: Input ultra limpio. El diseño pesado ahora lo hace main.dart
  Widget _buildTextField({
    required TextEditingController controller, 
    required String label, 
    required IconData icon, 
    bool isNumber = false,
    TextInputAction textInputAction = TextInputAction.next,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        textCapitalization: TextCapitalization.characters,
        textInputAction: textInputAction,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) return "Campo requerido";
          return null;
        }
      )
    );
  }

  Widget _buildEmpresaTile() {
    return InkWell(
      onTap: _mostrarSelectorEmpresa, 
      borderRadius: BorderRadius.circular(14), 
      child: Container(
        padding: const EdgeInsets.all(16), 
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface, 
          borderRadius: BorderRadius.circular(14)
        ), 
        child: Row(children: [
          const Icon(Icons.business, color: Colors.greenAccent), 
          const SizedBox(width: 15), 
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Empresa Titular", style: TextStyle(color: Colors.white54, fontSize: 11)), 
            const SizedBox(height: 4),
            Text(_empresaController.text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))
          ])), 
          const Icon(Icons.edit, color: Colors.white24, size: 18)
        ])
      )
    );
  }

  Widget _buildDatePickerTile(String label, String? fecha, String? urlActual, VoidCallback onTapDate, VoidCallback onTapFile) {
    int dias = AppFormatters.calcularDiasRestantes(fecha ?? "");
    Color colorSemaforo = dias < 0 ? Colors.redAccent : (dias <= 14 ? Colors.orangeAccent : (dias <= 30 ? Colors.greenAccent : Colors.blueAccent));

    return ListTile(
      onTap: onTapDate,
      contentPadding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
      leading: Icon(Icons.edit_calendar, color: colorSemaforo, size: 28),
      title: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      subtitle: Text(AppFormatters.formatearFecha(fecha ?? ""), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fecha != null && fecha.isNotEmpty) 
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), 
              decoration: BoxDecoration(
                color: colorSemaforo.withAlpha(40), 
                borderRadius: BorderRadius.circular(6), 
                border: Border.all(color: colorSemaforo.withAlpha(100))
              ), 
              child: Text("${dias}d", style: TextStyle(color: colorSemaforo, fontWeight: FontWeight.bold, fontSize: 11))
            ),
          const SizedBox(width: 15),
          IconButton(
            icon: Icon(
              urlActual != null && urlActual != "-" ? Icons.file_download_done : Icons.upload_file, 
              color: urlActual != null && urlActual != "-" ? Colors.blueAccent : Colors.white54,
              size: 26,
            ),
            onPressed: onTapFile,
          ),
        ],
      ),
    );
  }
}
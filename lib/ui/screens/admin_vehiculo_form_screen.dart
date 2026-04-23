import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../core/utils/formatters.dart';
import '../../core/services/volvo_api_service.dart';

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
    File? fileToUpload;
    String fileName = "";

    final int? source = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF1A3A5A),
      builder: (bCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.orangeAccent),
              title: const Text("Tomar Foto", style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, 1),
            ),
            ListTile(
              leading: const Icon(Icons.file_present, color: Colors.blueAccent),
              title: const Text("Seleccionar Archivo (PDF/Imagen)", style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, 2),
            ),
          ],
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
        await ref.putFile(fileToUpload);
        String downloadUrl = await ref.getDownloadURL();

        setState(() {
          if (tipoDoc == 'RTO') {
            _urlRto = downloadUrl;
          }
          if (tipoDoc == 'SEGURO') {
            _urlSeguro = downloadUrl;
          }
          _isSaving = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Documento $tipoDoc cargado."), backgroundColor: Colors.blue),
          );
        }
      } catch (e) {
        setState(() => _isSaving = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
        }
      }
    }
  }

  Future<void> _sincronizarConVolvoManual() async {
    if (_vinController.text.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Se requiere un VIN válido"), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => _isSyncing = true);
    try {
      final metros = await VolvoApiService().traerKilometrajeCualquierVia(_vinController.text);
      if (!mounted) {
        return;
      }
      if (metros != null && metros > 0) {
        final double kmReal = metros / 1000;
        setState(() => _kmController.text = kmReal.toStringAsFixed(0));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("¡Sincronizado! KM Actualizado."), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Unidad en reposo (Sin corriente)"), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      debugPrint("Error sincro: $e");
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
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
      locale: const Locale('es', 'AR'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.orangeAccent,
              onPrimary: Colors.black,
              surface: Color(0xFF1A3A5A),
            ),
          ),
          child: child!,
        );
      },
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
        backgroundColor: const Color(0xFF0D1D2D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Seleccionar Empresa", style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: empresas.map((e) => ListTile(
            title: Text(e, style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_fechaRto == null || _fechaSeguro == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Faltan fechas"), backgroundColor: Colors.orange));
      return;
    }

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
        'VENCIMIENTO_RTO': _fechaRto,
        'VENCIMIENTO_SEGURO': _fechaSeguro,
        'ARCHIVO_RTO': _urlRto,
        'ARCHIVO_SEGURO': _urlSeguro,
        'fecha_ultima_actualizacion': FieldValue.serverTimestamp(),
      });
      if (!mounted) {
        return;
      }
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool esVolvo = _marcaController.text.toUpperCase().contains("VOLVO");

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text("Ficha: ${widget.vehiculoId}"), centerTitle: true, backgroundColor: Colors.transparent, elevation: 0, foregroundColor: Colors.white),
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
                  
                  // SEPARADOS: Marca y Modelo con iconos distintos
                  _buildTextField(_marcaController, "Marca del Fabricante", Icons.branding_watermark),
                  _buildTextField(_modeloController, "Modelo de la Unidad", Icons.directions_car),
                  
                  _buildTextField(_anioController, "Año de Fabricación", Icons.calendar_today, isNumber: true),
                  
                  if (esVolvo) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blue.withAlpha(20), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blueAccent.withAlpha(50))),
                      child: Column(children: [
                        _buildTextField(_vinController, "Código VIN", Icons.fingerprint),
                        const SizedBox(height: 10),
                        _isSyncing 
                          ? const CircularProgressIndicator(color: Colors.blueAccent) 
                          : TextButton.icon(
                              onPressed: _sincronizarConVolvoManual, 
                              icon: const Icon(Icons.sync, color: Colors.blueAccent), 
                              label: const Text("SINCRONIZAR VOLVO", style: TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold))
                            ),
                      ]),
                    ),
                  ],

                  _buildTextField(_kmController, "Kilometraje Actual", Icons.speed, isNumber: true),
                  const SizedBox(height: 10),
                  _buildEmpresaTile(),

                  const SizedBox(height: 30),
                  _buildSectionTitle("AUDITORÍA DE VENCIMIENTOS Y DOCUMENTACIÓN"),

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
                  _isSaving 
                    ? const Center(child: CircularProgressIndicator(color: Colors.orangeAccent)) 
                    : ElevatedButton.icon(
                        onPressed: _guardarCambios, 
                        icon: const Icon(Icons.save), 
                        label: const Text("GUARDAR CAMBIOS"), 
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 55), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))
                      ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(padding: const EdgeInsets.only(bottom: 15, left: 5), child: Text(title, style: const TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)));
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isNumber = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        textCapitalization: TextCapitalization.characters,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
          prefixIcon: Icon(icon, color: Colors.orangeAccent, size: 18),
          filled: true,
          fillColor: Colors.white.withAlpha(20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return "Campo requerido";
          }
          return null;
        }
      )
    );
  }

  Widget _buildEmpresaTile() {
    return InkWell(onTap: _mostrarSelectorEmpresa, borderRadius: BorderRadius.circular(12), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white.withAlpha(20), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.business, color: Colors.orangeAccent), const SizedBox(width: 15), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Empresa Titular", style: TextStyle(color: Colors.white54, fontSize: 10)), Text(_empresaController.text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))])), const Icon(Icons.chevron_right, color: Colors.white24)])));
  }

  Widget _buildDatePickerTile(String label, String? fecha, String? urlActual, VoidCallback onTapDate, VoidCallback onTapFile) {
    int dias = AppFormatters.calcularDiasRestantes(fecha ?? "");
    Color colorSemaforo = dias < 0 ? Colors.red : (dias <= 14 ? Colors.orange : (dias <= 30 ? Colors.greenAccent : Colors.blueAccent));

    return ListTile(
      onTap: onTapDate,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      leading: Icon(Icons.edit_calendar, color: colorSemaforo, size: 24),
      title: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      subtitle: Text(AppFormatters.formatearFecha(fecha ?? ""), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), 
            decoration: BoxDecoration(
              color: colorSemaforo.withAlpha(40), 
              borderRadius: BorderRadius.circular(6), 
              border: Border.all(color: colorSemaforo.withAlpha(100))
            ), 
            child: Text("${dias}d", style: TextStyle(color: colorSemaforo, fontWeight: FontWeight.bold, fontSize: 11))
          ),
          const SizedBox(width: 10),
          IconButton(
            icon: Icon(
              urlActual != null ? Icons.file_download_done : Icons.upload_file, 
              color: urlActual != null ? Colors.blueAccent : Colors.orangeAccent
            ),
            onPressed: onTapFile,
          ),
        ],
      ),
    );
  }
}
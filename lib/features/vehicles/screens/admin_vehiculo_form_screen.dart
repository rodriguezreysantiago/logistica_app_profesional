import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../services/volvo_api_service.dart';

/// Form de edición de la ficha de un vehículo existente.
///
/// Permite:
/// - Editar datos técnicos (marca, modelo, año, VIN, KM)
/// - Cambiar empresa propietaria
/// - Sincronizar KM con Volvo Connect manualmente
/// - Editar fechas de RTO y Seguro
/// - Subir comprobantes (foto o PDF) para RTO y Seguro
class AdminVehiculoFormScreen extends StatefulWidget {
  final String vehiculoId;
  final Map<String, dynamic> datosIniciales;

  const AdminVehiculoFormScreen({
    super.key,
    required this.vehiculoId,
    required this.datosIniciales,
  });

  @override
  State<AdminVehiculoFormScreen> createState() =>
      _AdminVehiculoFormScreenState();
}

class _AdminVehiculoFormScreenState extends State<AdminVehiculoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  bool _isSyncing = false;

  late final TextEditingController _marcaCtrl;
  late final TextEditingController _modeloCtrl;
  late final TextEditingController _anioCtrl;
  late final TextEditingController _empresaCtrl;
  late final TextEditingController _vinCtrl;
  late final TextEditingController _kmCtrl;

  String? _fechaRto;
  String? _fechaSeguro;
  String? _urlRto;
  String? _urlSeguro;

  @override
  void initState() {
    super.initState();
    final d = widget.datosIniciales;
    _marcaCtrl = TextEditingController(text: d['MARCA']?.toString() ?? '');
    _modeloCtrl =
        TextEditingController(text: d['MODELO']?.toString() ?? '');
    _anioCtrl = TextEditingController(
      text: (d['ANIO'] ?? d['AÑO'])?.toString() ?? '',
    );
    _empresaCtrl =
        TextEditingController(text: d['EMPRESA']?.toString() ?? '');
    _vinCtrl = TextEditingController(text: d['VIN']?.toString() ?? '');
    _kmCtrl =
        TextEditingController(text: d['KM_ACTUAL']?.toString() ?? '0');
    _fechaRto = d['VENCIMIENTO_RTO']?.toString();
    _fechaSeguro = d['VENCIMIENTO_SEGURO']?.toString();
    _urlRto = d['ARCHIVO_RTO']?.toString();
    _urlSeguro = d['ARCHIVO_SEGURO']?.toString();
  }

  @override
  void dispose() {
    _marcaCtrl.dispose();
    _modeloCtrl.dispose();
    _anioCtrl.dispose();
    _empresaCtrl.dispose();
    _vinCtrl.dispose();
    _kmCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // ACCIONES
  // ---------------------------------------------------------------------------

  Future<void> _subirDocumento(String tipoDoc) async {
    final messenger = ScaffoldMessenger.of(context);
    final source = await _elegirFuenteArchivo();
    if (source == null) return;

    File? fileToUpload;
    String fileName = '';

    if (source == _FuenteArchivo.camera) {
      final photo = await ImagePicker()
          .pickImage(source: ImageSource.camera, imageQuality: 50);
      if (photo != null) {
        fileToUpload = File(photo.path);
        fileName =
            '${tipoDoc}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      }
    } else {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result != null && result.files.single.path != null) {
        fileToUpload = File(result.files.single.path!);
        fileName = result.files.single.name;
      }
    }

    if (fileToUpload == null) return;

    setState(() => _isSaving = true);
    try {
      final path = 'vehiculos/${widget.vehiculoId.trim()}/$fileName';
      final ref = FirebaseStorage.instance.ref().child(path);

      SettableMetadata? metadata;
      final lower = fileName.toLowerCase();
      if (lower.endsWith('.pdf')) {
        metadata = SettableMetadata(contentType: 'application/pdf');
      } else if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
        metadata = SettableMetadata(contentType: 'image/jpeg');
      }

      await ref.putFile(fileToUpload, metadata);
      final downloadUrl = await ref.getDownloadURL();

      if (!mounted) return;
      setState(() {
        if (tipoDoc == 'RTO') _urlRto = downloadUrl;
        if (tipoDoc == 'SEGURO') _urlSeguro = downloadUrl;
        _isSaving = false;
      });

      messenger.showSnackBar(
        SnackBar(
          content: Text('Documento $tipoDoc cargado.'),
          backgroundColor: Colors.blueAccent,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error al subir: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<_FuenteArchivo?> _elegirFuenteArchivo() {
    return showModalBottomSheet<_FuenteArchivo>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
          border: const Border(
              top: BorderSide(color: Colors.greenAccent, width: 2)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(15),
                child: Text(
                  'Adjuntar documento',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              ListTile(
                leading:
                    const Icon(Icons.camera_alt, color: Colors.greenAccent),
                title: const Text('Tomar foto',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, _FuenteArchivo.camera),
              ),
              ListTile(
                leading:
                    const Icon(Icons.file_present, color: Colors.blueAccent),
                title: const Text('Seleccionar archivo (PDF/imagen)',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, _FuenteArchivo.fileSystem),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sincronizarConVolvo() async {
    final messenger = ScaffoldMessenger.of(context);

    if (_vinCtrl.text.length < 10) {
      messenger.showSnackBar(
        const SnackBar(
          content:
              Text('Se requiere un VIN válido (mínimo 10 caracteres)'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    setState(() => _isSyncing = true);

    try {
      final metros = await VolvoApiService()
          .traerKilometrajeCualquierVia(_vinCtrl.text.trim().toUpperCase());

      if (!mounted) return;

      if (metros != null && metros > 0) {
        setState(() => _kmCtrl.text = (metros / 1000).toStringAsFixed(0));
        messenger.showSnackBar(
          const SnackBar(
            content: Text('¡Sincronizado! KM actualizado.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Unidad en reposo o no encontrada en Volvo.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error sincro: $e');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error de conexión con Volvo: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _seleccionarFecha(bool esRto) async {
    final fechaActual = esRto ? _fechaRto : _fechaSeguro;
    final initial = (fechaActual != null && fechaActual.isNotEmpty)
        ? (DateTime.tryParse(fechaActual) ?? DateTime.now())
        : DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );

    if (picked != null && mounted) {
      setState(() {
        final f = picked.toString().split(' ').first;
        if (esRto) {
          _fechaRto = f;
        } else {
          _fechaSeguro = f;
        }
      });
    }
  }

  void _seleccionarEmpresa() {
    const empresas = [
      'VECCHI ARIEL Y VECCHI GRACIELA S.R.L: (30-70910015-3)',
      'SUCESION DE VECCHI CARLOS LUIS: (20-08569424-4)',
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seleccionar empresa'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: empresas
              .map((e) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      e,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13),
                    ),
                    onTap: () {
                      setState(() => _empresaCtrl.text = e);
                      Navigator.pop(ctx);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSaving) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSaving = true);

    try {
      final id = widget.vehiculoId.trim().toUpperCase();
      await FirebaseFirestore.instance
          .collection('VEHICULOS')
          .doc(id)
          .update({
        'MARCA': _marcaCtrl.text.trim().toUpperCase(),
        'MODELO': _modeloCtrl.text.trim().toUpperCase(),
        'ANIO': int.tryParse(_anioCtrl.text.trim()) ?? 0,
        'EMPRESA': _empresaCtrl.text.trim().toUpperCase(),
        'VIN': _vinCtrl.text.trim().toUpperCase(),
        'KM_ACTUAL': double.tryParse(_kmCtrl.text) ?? 0.0,
        'VENCIMIENTO_RTO': _fechaRto ?? '',
        'VENCIMIENTO_SEGURO': _fechaSeguro ?? '',
        'ARCHIVO_RTO': _urlRto ?? '-',
        'ARCHIVO_SEGURO': _urlSeguro ?? '-',
        'fecha_ultima_actualizacion': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Ficha actualizada con éxito'),
          backgroundColor: Colors.green,
        ),
      );
      navigator.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final esVolvo =
        _marcaCtrl.text.toUpperCase().contains('VOLVO');

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: AppScaffold(
        title: 'Ficha: ${widget.vehiculoId}',
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const _SectionTitle('Información técnica'),
              _FInput(
                controller: _marcaCtrl,
                label: 'Marca del fabricante',
                icon: Icons.branding_watermark,
              ),
              _FInput(
                controller: _modeloCtrl,
                label: 'Modelo de la unidad',
                icon: Icons.directions_car,
              ),
              _FInput(
                controller: _anioCtrl,
                label: 'Año de fabricación',
                icon: Icons.calendar_today,
                isNumber: true,
              ),
              if (esVolvo) ...[
                const SizedBox(height: 8),
                _BloqueVolvo(
                  vinController: _vinCtrl,
                  isSyncing: _isSyncing,
                  onSync: _sincronizarConVolvo,
                ),
                const SizedBox(height: 16),
              ],
              _FInput(
                controller: _kmCtrl,
                label: 'Kilometraje actual',
                icon: Icons.speed,
                isNumber: true,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 8),
              _EmpresaTile(
                empresa: _empresaCtrl.text,
                onTap: _seleccionarEmpresa,
              ),
              const SizedBox(height: 28),
              const _SectionTitle('Auditoría de vencimientos'),
              _DateTile(
                label: 'Vencimiento RTO',
                fecha: _fechaRto,
                url: _urlRto,
                onTapDate: () => _seleccionarFecha(true),
                onTapFile: () => _subirDocumento('RTO'),
                tituloVisor: 'RTO ${widget.vehiculoId}',
              ),
              const Divider(color: Colors.white10, height: 1),
              _DateTile(
                label: 'Póliza de seguro',
                fecha: _fechaSeguro,
                url: _urlSeguro,
                onTapDate: () => _seleccionarFecha(false),
                onTapFile: () => _subirDocumento('SEGURO'),
                tituloVisor: 'Seguro ${widget.vehiculoId}',
              ),
              const SizedBox(height: 32),
              _BotonGuardar(
                guardando: _isSaving,
                onPressed: _guardar,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

enum _FuenteArchivo { camera, fileSystem }

// =============================================================================
// COMPONENTES
// =============================================================================

class _SectionTitle extends StatelessWidget {
  final String label;
  const _SectionTitle(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 5),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Colors.greenAccent,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _FInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool isNumber;
  final TextInputAction textInputAction;

  const _FInput({
    required this.controller,
    required this.label,
    required this.icon,
    this.isNumber = false,
    this.textInputAction = TextInputAction.next,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        keyboardType:
            isNumber ? TextInputType.number : TextInputType.text,
        textCapitalization: TextCapitalization.characters,
        textInputAction: textInputAction,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
            size: 20,
          ),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Campo requerido';
          }
          return null;
        },
      ),
    );
  }
}

class _BloqueVolvo extends StatelessWidget {
  final TextEditingController vinController;
  final bool isSyncing;
  final VoidCallback onSync;

  const _BloqueVolvo({
    required this.vinController,
    required this.isSyncing,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withAlpha(20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blueAccent.withAlpha(50)),
      ),
      child: Column(
        children: [
          _FInput(
            controller: vinController,
            label: 'Código VIN (Volvo)',
            icon: Icons.fingerprint,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 10),
          if (isSyncing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: CircularProgressIndicator(color: Colors.blueAccent),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onSync,
                icon: const Icon(Icons.sync, color: Colors.blueAccent),
                label: const Text(
                  'FORZAR SINCRO VOLVO',
                  style: TextStyle(
                    color: Colors.blueAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.blueAccent),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmpresaTile extends StatelessWidget {
  final String empresa;
  final VoidCallback onTap;

  const _EmpresaTile({required this.empresa, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.business, color: Colors.greenAccent),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Empresa titular',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(
                  empresa,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.edit, color: Colors.white24, size: 18),
        ],
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final String? fecha;
  final String? url;
  final VoidCallback onTapDate;
  final VoidCallback onTapFile;
  final String tituloVisor;

  const _DateTile({
    required this.label,
    required this.fecha,
    required this.url,
    required this.onTapDate,
    required this.onTapFile,
    required this.tituloVisor,
  });

  @override
  Widget build(BuildContext context) {
    final tieneArchivo = url != null && url!.isNotEmpty && url != '-';

    return ListTile(
      onTap: onTapDate,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
      leading: AppFileThumbnail(
        url: url,
        tituloVisor: tituloVisor,
        size: 40,
      ),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      subtitle: Text(
        AppFormatters.formatearFecha(fecha ?? ''),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          VencimientoBadge(fecha: fecha),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              tieneArchivo ? Icons.file_download_done : Icons.upload_file,
              color: tieneArchivo ? Colors.blueAccent : Colors.white54,
              size: 24,
            ),
            tooltip: tieneArchivo ? 'Reemplazar archivo' : 'Subir archivo',
            onPressed: onTapFile,
          ),
        ],
      ),
    );
  }
}

class _BotonGuardar extends StatelessWidget {
  final bool guardando;
  final VoidCallback onPressed;

  const _BotonGuardar({
    required this.guardando,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton.icon(
        onPressed: guardando ? null : onPressed,
        icon: guardando
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black,
                ),
              )
            : const Icon(Icons.save),
        label: Text(
          guardando ? 'GUARDANDO...' : 'GUARDAR CAMBIOS',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

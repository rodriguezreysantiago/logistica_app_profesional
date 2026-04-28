import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/vencimientos_config.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/fecha_dialog.dart';
import '../services/volvo_api_service.dart';
import 'diagnostico_volvo_screen.dart';

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

  /// Estado de los vencimientos, indexado por el nombre del campo de
  /// Firestore. Usar maps en lugar de variables individuales nos permite
  /// agregar nuevos vencimientos en el futuro tocando SOLO la lista
  /// `AppVencimientos`.
  final Map<String, String?> _fechas = {};
  final Map<String, String?> _urls = {};

  /// Lista de vencimientos que aplica a este vehículo, según su tipo
  /// (tractor → 4 vencimientos; enganche → 2). Se calcula una sola vez
  /// en initState y se usa en _guardar y en build.
  late final List<VencimientoSpec> _vencimientos;

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

    _vencimientos = AppVencimientos.forTipo(d['TIPO']?.toString());
    for (final spec in _vencimientos) {
      _fechas[spec.campoFecha] = d[spec.campoFecha]?.toString();
      _urls[spec.campoArchivo] = d[spec.campoArchivo]?.toString();
    }
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

  Future<void> _subirDocumento(VencimientoSpec spec) async {
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
        // Nombre de archivo: usamos el campoArchivo (sin prefijo ARCHIVO_)
        // como tag para que sea fácil identificar el archivo en Storage.
        final tag = spec.campoArchivo.replaceFirst('ARCHIVO_', '');
        fileName = '${tag}_${DateTime.now().millisecondsSinceEpoch}.jpg';
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
        _urls[spec.campoArchivo] = downloadUrl;
      });

      messenger.showSnackBar(
        SnackBar(
          content: Text('${spec.etiqueta} cargado.'),
          backgroundColor: Colors.blueAccent,
        ),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error al subir: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      // Siempre reseteamos _isSaving — incluso si la subida falló o el
      // widget se desmontó (el chequeo de mounted protege el setState).
      if (mounted) setState(() => _isSaving = false);
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

  void _abrirDiagnostico() {
    final vin = _vinCtrl.text.trim().toUpperCase();
    if (vin.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Necesito un VIN válido para diagnosticar.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiagnosticoVolvoScreen(
          patente: widget.vehiculoId,
          vin: vin,
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

  Future<void> _seleccionarFecha(VencimientoSpec spec) async {
    final fechaActual = _fechas[spec.campoFecha];
    final initial = (fechaActual != null && fechaActual.isNotEmpty)
        ? DateTime.tryParse(fechaActual)
        : null;

    final picked = await pickFecha(
      context,
      initial: initial,
      titulo: 'Vencimiento ${spec.etiqueta}',
    );

    if (picked != null && mounted) {
      setState(() {
        _fechas[spec.campoFecha] = picked.toString().split(' ').first;
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

    bool guardadoOk = false;
    try {
      final id = widget.vehiculoId.trim().toUpperCase();
      final updates = <String, dynamic>{
        'MARCA': _marcaCtrl.text.trim().toUpperCase(),
        'MODELO': _modeloCtrl.text.trim().toUpperCase(),
        'ANIO': int.tryParse(_anioCtrl.text.trim()) ?? 0,
        'EMPRESA': _empresaCtrl.text.trim().toUpperCase(),
        'VIN': _vinCtrl.text.trim().toUpperCase(),
        'KM_ACTUAL': double.tryParse(_kmCtrl.text) ?? 0.0,
        'fecha_ultima_actualizacion': FieldValue.serverTimestamp(),
      };
      // Persistimos cada vencimiento iterando la lista — sumar uno
      // nuevo a AppVencimientos lo guarda automáticamente.
      for (final spec in _vencimientos) {
        updates[spec.campoFecha] = _fechas[spec.campoFecha] ?? '';
        updates[spec.campoArchivo] = _urls[spec.campoArchivo] ?? '-';
      }
      await FirebaseFirestore.instance
          .collection('VEHICULOS')
          .doc(id)
          .update(updates);
      guardadoOk = true;

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
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      // Solo reseteamos el flag si NO hicimos pop (si se hizo pop, la
      // pantalla se va a desmontar y no necesitamos tocar nada). Esto
      // garantiza que el botón vuelva a habilitarse si la operación falló.
      if (!guardadoOk && mounted) {
        setState(() => _isSaving = false);
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
                  onDiagnostico: _abrirDiagnostico,
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
              // Tiles generados desde la lista de specs: sumar un
              // VencimientoSpec a AppVencimientos.tractor / .enganche y
              // automáticamente aparece acá.
              for (int i = 0; i < _vencimientos.length; i++) ...[
                _DateTile(
                  label: 'Vencimiento ${_vencimientos[i].etiqueta}',
                  fecha: _fechas[_vencimientos[i].campoFecha],
                  url: _urls[_vencimientos[i].campoArchivo],
                  onTapDate: () => _seleccionarFecha(_vencimientos[i]),
                  onTapFile: () => _subirDocumento(_vencimientos[i]),
                  tituloVisor:
                      '${_vencimientos[i].etiqueta} ${widget.vehiculoId}',
                ),
                if (i < _vencimientos.length - 1)
                  const Divider(color: Colors.white10, height: 1),
              ],
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
  final VoidCallback onDiagnostico;

  const _BloqueVolvo({
    required this.vinController,
    required this.isSyncing,
    required this.onSync,
    required this.onDiagnostico,
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
          const SizedBox(height: 8),
          // Botón de diagnóstico — abre una pantalla con el JSON crudo
          // del response de Volvo y un análisis automático de qué campos
          // están viniendo. Útil cuando algún dato no aparece en la UI.
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: onDiagnostico,
              icon: const Icon(Icons.bug_report,
                  color: Colors.orangeAccent, size: 18),
              label: const Text(
                'DIAGNÓSTICO',
                style: TextStyle(
                  color: Colors.orangeAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1,
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

    // No usamos ListTile.onTap porque colisiona con los taps internos de
    // los iconos. En lugar de eso, hacemos clickeable solo la zona del
    // título/fecha (que abre el date picker) y dejamos los iconos del
    // trailing como botones explícitos: Ver + Reemplazar/Subir.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
      child: Row(
        children: [
          AppFileThumbnail(
            url: url,
            tituloVisor: tituloVisor,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: onTapDate,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppFormatters.formatearFecha(fecha ?? ''),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          VencimientoBadge(fecha: fecha),
          const SizedBox(width: 4),
          if (tieneArchivo)
            IconButton(
              icon: const Icon(Icons.visibility,
                  color: Colors.greenAccent, size: 22),
              tooltip: 'Ver archivo',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      PreviewScreen(url: url!, titulo: tituloVisor),
                ),
              ),
            ),
          IconButton(
            icon: Icon(
              tieneArchivo ? Icons.file_upload_outlined : Icons.upload_file,
              color: tieneArchivo ? Colors.blueAccent : Colors.white54,
              size: 22,
            ),
            tooltip:
                tieneArchivo ? 'Reemplazar archivo' : 'Subir archivo',
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

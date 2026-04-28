import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../../../shared/utils/formatters.dart';
import 'vencimiento_item.dart';

/// Bottom sheet para editar un vencimiento puntual.
///
/// Permite al admin:
/// - Cambiar la fecha de vencimiento
/// - Adjuntar un archivo nuevo (jpg/png/pdf)
/// - Guardar los cambios → actualiza Firestore + sube a Storage
///
/// Reusable entre choferes / chasis / acoplados (toda la lógica de subida y
/// actualización está acá, antes estaba duplicada 3 veces).
///
/// Uso:
/// ```
/// VencimientoEditorSheet.show(context, item);
/// ```
class VencimientoEditorSheet {
  VencimientoEditorSheet._();

  static Future<void> show(BuildContext context, VencimientoItem item) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditorSheetBody(item: item),
    );
  }
}

class _EditorSheetBody extends StatefulWidget {
  final VencimientoItem item;
  const _EditorSheetBody({required this.item});

  @override
  State<_EditorSheetBody> createState() => _EditorSheetBodyState();
}

class _EditorSheetBodyState extends State<_EditorSheetBody> {
  late DateTime _fechaSeleccionada;
  File? _archivoSeleccionado;
  bool _subiendo = false;

  @override
  void initState() {
    super.initState();
    _fechaSeleccionada =
        DateTime.tryParse(widget.item.fecha) ?? DateTime.now();
  }

  Future<void> _seleccionarFecha() async {
    final picker = await showDatePicker(
      context: context,
      initialDate: _fechaSeleccionada,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
    if (picker != null && mounted) {
      setState(() => _fechaSeleccionada = picker);
    }
  }

  Future<void> _seleccionarArchivo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result != null && result.files.single.path != null && mounted) {
      setState(() =>
          _archivoSeleccionado = File(result.files.single.path!));
    }
  }

  Future<String?> _subirArchivo() async {
    if (_archivoSeleccionado == null) return widget.item.urlArchivo;

    final extension =
        _archivoSeleccionado!.path.split('.').last.toLowerCase();
    final nombre =
        '${widget.item.docId}_ADMIN_${widget.item.campoBase}_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final ref = FirebaseStorage.instance
        .ref()
        .child('${widget.item.storagePath}/$nombre');

    SettableMetadata? metadata;
    if (extension == 'pdf') {
      metadata = SettableMetadata(contentType: 'application/pdf');
    } else if (['jpg', 'jpeg', 'png'].contains(extension)) {
      metadata = SettableMetadata(contentType: 'image/jpeg');
    }

    await ref.putFile(_archivoSeleccionado!, metadata);
    return await ref.getDownloadURL();
  }

  Future<void> _guardar() async {
    setState(() => _subiendo = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final urlFinal = await _subirArchivo();
      final fechaStr = _fechaSeleccionada.toString().split(' ').first;

      await FirebaseFirestore.instance
          .collection(widget.item.coleccion)
          .doc(widget.item.docId)
          .update({
        'VENCIMIENTO_${widget.item.campoBase}': fechaStr,
        'ARCHIVO_${widget.item.campoBase}': urlFinal,
        'ultima_modificacion_admin': FieldValue.serverTimestamp(),
      });

      messenger.showSnackBar(
        SnackBar(
          content: Text('${widget.item.tipoDoc} actualizado con éxito'),
          backgroundColor: Colors.green,
        ),
      );
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error al guardar: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
      if (mounted) setState(() => _subiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
        border: const Border(
          top: BorderSide(color: Colors.greenAccent, width: 2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle visual
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Título
          Text(
            'Actualizar ${widget.item.tipoDoc}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            widget.item.titulo,
            style: const TextStyle(
              color: Colors.greenAccent,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Divider(color: Colors.white10, height: 25),

          // Selector de fecha
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Fecha de vencimiento',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            subtitle: Text(
              AppFormatters.formatearFecha(
                  _fechaSeleccionada.toString().split(' ').first),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            trailing: const Icon(Icons.calendar_month,
                color: Colors.greenAccent, size: 28),
            onTap: _seleccionarFecha,
          ),

          const SizedBox(height: 15),

          // Selector de archivo
          InkWell(
            onTap: _seleccionarArchivo,
            borderRadius: BorderRadius.circular(15),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: _archivoSeleccionado == null
                      ? Colors.white10
                      : Colors.greenAccent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _archivoSeleccionado == null
                        ? Icons.upload_file
                        : Icons.check_circle,
                    color: _archivoSeleccionado == null
                        ? Colors.white38
                        : Colors.greenAccent,
                    size: 28,
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Text(
                      _archivoSeleccionado == null
                          ? 'Cargar comprobante nuevo'
                          : 'Archivo listo para subir',
                      style: TextStyle(
                        color: _archivoSeleccionado == null
                            ? Colors.white54
                            : Colors.greenAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (_archivoSeleccionado == null)
                    const Icon(Icons.add_a_photo_outlined,
                        color: Colors.greenAccent, size: 20),
                ],
              ),
            ),
          ),

          const SizedBox(height: 30),

          // Botones de acción
          if (_subiendo)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: CircularProgressIndicator(color: Colors.greenAccent),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'CANCELAR',
                      style: TextStyle(
                        color: Colors.white54,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _guardar,
                    child: const Text('GUARDAR CAMBIOS'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

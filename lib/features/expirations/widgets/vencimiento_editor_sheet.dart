import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/services/prefs_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../shared/utils/app_feedback.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/whatsapp_helper.dart';
import '../../../shared/widgets/fecha_dialog.dart';
import '../services/aviso_vencimiento_builder.dart';
import '../services/aviso_vencimiento_service.dart';
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
  Uint8List? _archivoBytes;
  String? _archivoNombre;
  bool _subiendo = false;

  final StorageService _storageService = StorageService();

  @override
  void initState() {
    super.initState();
    _fechaSeleccionada =
        DateTime.tryParse(widget.item.fecha) ?? DateTime.now();
  }

  Future<void> _seleccionarFecha() async {
    final picker = await pickFecha(
      context,
      initial: _fechaSeleccionada,
      titulo: 'Vencimiento ${widget.item.tipoDoc}',
    );
    if (picker != null && mounted) {
      setState(() => _fechaSeleccionada = picker);
    }
  }

  Future<void> _seleccionarArchivo() async {
    // withData: true para que `bytes` venga poblado en todas las plataformas
    // (en Web `path` es null porque no hay filesystem).
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    final picked = result?.files.singleOrNull;
    if (picked != null && picked.bytes != null && mounted) {
      setState(() {
        _archivoBytes = picked.bytes;
        _archivoNombre = picked.name;
      });
    }
  }

  Future<String?> _subirArchivo() async {
    if (_archivoBytes == null) return widget.item.urlArchivo;

    final extension =
        (_archivoNombre ?? '').split('.').last.toLowerCase();
    final nombre =
        '${widget.item.docId}_ADMIN_${widget.item.campoBase}_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final ruta = '${widget.item.storagePath}/$nombre';

    return await _storageService.subirArchivo(
      bytes: _archivoBytes!,
      nombreOriginal: _archivoNombre ?? 'archivo.$extension',
      rutaStorage: ruta,
    );
  }

  /// Resuelve el chofer al que hay que avisarle según el tipo de
  /// vencimiento y abre WhatsApp con el mensaje pre-armado.
  ///
  /// - Si la auditoría es de EMPLEADOS (chofer), el chofer es el dueño
  ///   del docId — leemos su TELEFONO directamente.
  /// - Si la auditoría es de VEHICULOS (tractor/batea), buscamos al
  ///   empleado que tiene asignada esa patente como VEHICULO o ENGANCHE.
  Future<void> _avisarPorWhatsApp() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _subiendo = true);

    String? telefono;
    String? primerNombre;

    try {
      final db = FirebaseFirestore.instance;

      if (widget.item.coleccion == 'EMPLEADOS') {
        final snap =
            await db.collection('EMPLEADOS').doc(widget.item.docId).get();
        if (snap.exists) {
          final data = snap.data()!;
          telefono = data['TELEFONO']?.toString();
          primerNombre = _extraerPrimerNombre(data['NOMBRE']?.toString());
        }
      } else {
        // VEHICULOS: el docId es la patente. Buscamos al chofer que la
        // tiene asignada como tractor (VEHICULO) o como enganche.
        final patente = widget.item.docId;
        final qVehiculo = await db
            .collection('EMPLEADOS')
            .where('VEHICULO', isEqualTo: patente)
            .limit(1)
            .get();
        QueryDocumentSnapshot? doc;
        if (qVehiculo.docs.isNotEmpty) {
          doc = qVehiculo.docs.first;
        } else {
          final qEnganche = await db
              .collection('EMPLEADOS')
              .where('ENGANCHE', isEqualTo: patente)
              .limit(1)
              .get();
          if (qEnganche.docs.isNotEmpty) doc = qEnganche.docs.first;
        }
        if (doc != null) {
          final data = doc.data() as Map<String, dynamic>;
          telefono = data['TELEFONO']?.toString();
          primerNombre = _extraerPrimerNombre(data['NOMBRE']?.toString());
        }
      }
    } catch (e) {
      // Seguimos abriendo WhatsApp aunque falle el lookup: al menos el
      // mensaje queda pre-armado y el admin elige el destinatario.
      debugPrint('No se pudo resolver chofer destinatario: $e');
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }

    if (!mounted) return;

    final mensaje = AvisoVencimientoBuilder.build(
      item: widget.item,
      destinatarioNombre: primerNombre,
    );
    final tieneTel = telefono != null && telefono.trim().isNotEmpty;

    final ok =
        await WhatsAppHelper.abrir(numero: telefono, mensaje: mensaje);

    if (!mounted) return;
    if (!ok) {
      AppFeedback.errorOn(messenger, 'No se pudo abrir WhatsApp en este dispositivo.');
      return;
    }

    if (!tieneTel) {
      // Abrimos WhatsApp pero sin destinatario para que el admin lo
      // cargue manualmente. NO registramos en el historial porque no
      // sabemos si efectivamente lo terminó enviando ni a quién.
      AppFeedback.warningOn(messenger, 'El chofer no tiene teléfono cargado — elegí el contacto en WhatsApp.');
      return;
    }

    // Registramos el aviso en el historial. Lo hacemos en background:
    // si Firestore falla, el aviso ya se mandó igual y no queremos
    // bloquear al admin con un error secundario.
    try {
      await AvisoVencimientoService.registrar(
        destinatarioColeccion: widget.item.coleccion,
        destinatarioId: widget.item.docId,
        campoBase: widget.item.campoBase,
        tipoDoc: widget.item.tipoDoc,
        canal: 'WHATSAPP',
        diasRestantes: widget.item.dias,
        mensaje: mensaje,
        adminDni: PrefsService.dni,
        adminNombre: PrefsService.nombre,
      );
    } catch (e) {
      debugPrint('No se pudo registrar el aviso en historial: $e');
    }
  }

  /// Para nombres tipo "PEREZ JUAN CARLOS" devuelve "Juan" (formato
  /// APELLIDO NOMBRE… que usa la app).
  ///
  /// Si el campo viene con un solo token (ej. solo "PEREZ"), devuelve
  /// `null` en lugar de arriesgar — preferimos saludar con "Hola"
  /// genérico que llamar al chofer por su apellido.
  String? _extraerPrimerNombre(String? nombreCompleto) {
    if (nombreCompleto == null || nombreCompleto.trim().isEmpty) return null;
    final partes = nombreCompleto.trim().split(RegExp(r'\s+'));
    if (partes.length < 2) return null;
    final n = partes[1];
    if (n.isEmpty) return null;
    // Capitalizamos: primera mayúscula, resto minúscula.
    return '${n[0].toUpperCase()}${n.substring(1).toLowerCase()}';
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

      AppFeedback.successOn(messenger, '${widget.item.tipoDoc} actualizado con éxito');
      navigator.pop();
    } catch (e) {
      AppFeedback.errorOn(messenger, 'Error al guardar: $e');
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
            trailing: const Icon(Icons.event_note,
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
                  color: _archivoBytes == null
                      ? Colors.white10
                      : Colors.greenAccent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _archivoBytes == null
                        ? Icons.upload_file
                        : Icons.check_circle,
                    color: _archivoBytes == null
                        ? Colors.white38
                        : Colors.greenAccent,
                    size: 28,
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Text(
                      _archivoBytes == null
                          ? 'Cargar comprobante nuevo'
                          : 'Archivo listo para subir',
                      style: TextStyle(
                        color: _archivoBytes == null
                            ? Colors.white54
                            : Colors.greenAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (_archivoBytes == null)
                    const Icon(Icons.add_a_photo_outlined,
                        color: Colors.greenAccent, size: 20),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Historial de avisos previos para este vencimiento
          // específico. Se actualiza en vivo: cuando el admin manda un
          // WhatsApp y vuelve al sheet, el contador y la fila de
          // "último aviso" reflejan el cambio sin recargar.
          _HistorialAvisos(item: widget.item),

          const SizedBox(height: 12),

          // Botón "Avisar por WhatsApp" — abre WhatsApp del admin con
          // el chofer cargado (si tiene teléfono en su legajo) y el
          // mensaje pre-armado según los días restantes.
          if (!_subiendo)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _avisarPorWhatsApp,
                icon: const Icon(Icons.send,
                    color: Color(0xFF25D366), size: 20),
                label: const Text(
                  'AVISAR POR WHATSAPP',
                  style: TextStyle(
                    color: Color(0xFF25D366),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF25D366)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

          const SizedBox(height: 12),

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

// =============================================================================
// HISTORIAL DE AVISOS
// =============================================================================

/// Bloque colapsable que muestra el historial de avisos enviados para
/// este vencimiento puntual: cuántos se mandaron, cuándo fue el último,
/// y al expandirlo, la lista detallada (por canal, por admin, días que
/// faltaban en ese momento).
///
/// Lee directo de Firestore con un Stream, así si el admin manda un
/// WhatsApp y vuelve al sheet, el contador se actualiza en vivo sin
/// necesidad de cerrar y abrir de nuevo.
class _HistorialAvisos extends StatelessWidget {
  final VencimientoItem item;
  const _HistorialAvisos({required this.item});

  String _hace(DateTime cuando) {
    final diff = DateTime.now().difference(cuando);
    if (diff.inMinutes < 1) return 'recién';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return 'hace $m ${m == 1 ? "min" : "min"}';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return 'hace $h ${h == 1 ? "hora" : "horas"}';
    }
    if (diff.inDays < 30) {
      final d = diff.inDays;
      return 'hace $d ${d == 1 ? "día" : "días"}';
    }
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(cuando.day)}/${two(cuando.month)}/${cuando.year}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AvisoVencimiento>>(
      stream: AvisoVencimientoService.streamHistorial(
        destinatarioColeccion: item.coleccion,
        destinatarioId: item.docId,
        campoBase: item.campoBase,
      ),
      builder: (ctx, snap) {
        // ── ERROR ───────────────────────────────────────────────────
        // Si la query falla (típicamente: permisos de Firestore o un
        // problema de red), lo mostramos en lugar de quedar invisible.
        if (snap.hasError) {
          return _Caja(
            color: Colors.redAccent,
            icono: Icons.error_outline,
            texto: 'No se pudo cargar el historial: ${snap.error}',
          );
        }

        // ── LOADING ─────────────────────────────────────────────────
        // Visible (no vacío como antes) para que el usuario sepa que
        // hay un bloque ocupando ese espacio.
        if (!snap.hasData) {
          return const _Caja(
            color: Colors.white24,
            icono: Icons.history,
            texto: 'Cargando historial de avisos...',
            mostrarSpinner: true,
          );
        }

        final avisos = snap.data!;

        // ── VACÍO ───────────────────────────────────────────────────
        if (avisos.isEmpty) {
          return const _Caja(
            color: Colors.white24,
            icono: Icons.history,
            texto: 'Sin avisos previos para este vencimiento.',
          );
        }

        final ultimo = avisos.first;
        return Theme(
          // Quitamos el divider/borde gris del ExpansionTile.
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF25D366).withAlpha(12),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: const Color(0xFF25D366).withAlpha(60)),
            ),
            child: ExpansionTile(
              tilePadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
              childrenPadding:
                  const EdgeInsets.fromLTRB(14, 0, 14, 12),
              leading: const Icon(Icons.history,
                  color: Color(0xFF25D366), size: 18),
              title: Text(
                '${avisos.length} aviso${avisos.length == 1 ? "" : "s"} '
                'enviado${avisos.length == 1 ? "" : "s"}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              subtitle: Text(
                'Último: ${_hace(ultimo.enviadoEn)} · '
                'por ${_extraerPrimerNombre(ultimo.enviadoPorNombre) ?? "Admin"}',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                ),
              ),
              children: avisos.map((a) => _ItemHistorial(aviso: a)).toList(),
            ),
          ),
        );
      },
    );
  }

  String? _extraerPrimerNombre(String? nombreCompleto) {
    if (nombreCompleto == null || nombreCompleto.trim().isEmpty) return null;
    final partes = nombreCompleto.trim().split(RegExp(r'\s+'));
    if (partes.length >= 2) {
      final n = partes[1];
      return '${n[0].toUpperCase()}${n.substring(1).toLowerCase()}';
    }
    return partes.first;
  }
}

class _ItemHistorial extends StatelessWidget {
  final AvisoVencimiento aviso;
  const _ItemHistorial({required this.aviso});

  String _formatFecha(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  IconData get _icono {
    switch (aviso.canal) {
      case 'WHATSAPP':
        return Icons.chat;
      case 'MAIL':
        return Icons.mail_outline;
      case 'PUSH':
        return Icons.notifications_active_outlined;
      default:
        return Icons.notifications_none;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icono, color: const Color(0xFF25D366), size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _formatFecha(aviso.enviadoEn),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      aviso.canal,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                if (aviso.enviadoPorNombre.isNotEmpty)
                  Text(
                    'por ${aviso.enviadoPorNombre.toUpperCase()} · '
                    '${aviso.diasRestantes < 0 ? "vencido hace ${-aviso.diasRestantes}d" : "${aviso.diasRestantes}d restantes"}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// CAJA INFORMATIVA — usada por _HistorialAvisos para sus estados
// (error / cargando / vacío). Muestra un panel pequeño con borde de color,
// icono y mensaje, opcionalmente con un spinner mientras carga.
// =============================================================================

class _Caja extends StatelessWidget {
  final Color color;
  final IconData icono;
  final String texto;
  final bool mostrarSpinner;

  const _Caja({
    required this.color,
    required this.icono,
    required this.texto,
    this.mostrarSpinner = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        children: [
          if (mostrarSpinner)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
              ),
            )
          else
            Icon(icono, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

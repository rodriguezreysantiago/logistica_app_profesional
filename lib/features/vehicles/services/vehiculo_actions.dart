import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/audit_log_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../shared/constants/app_colors.dart';
import '../../../shared/utils/app_feedback.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/fecha_dialog.dart';

// =============================================================================
// SERVICIO DE ACTUALIZACIÓN — NAMESPACE VehiculoActions
//
// Centraliza las operaciones que tocan Firestore/Storage para gestión de
// flota desde el bottom sheet de detalle del vehículo.
//
// Espejo conceptual de `EmpleadoActions` (papeles del chofer): cada
// inline-edit del sheet de detalle delega acá. Centralizamos para que:
// - Cada update lleve `fecha_ultima_actualizacion` para trackear cambios.
// - Audit log fire-and-forget (`AuditAccion.editarVehiculo`) en bitácora.
// - Manejo de errores con SnackBar consistente.
//
// **Lo que NO hace este servicio**: la sincronización con Volvo
// (`VolvoApiService`), uploads ad-hoc fuera de papeles, ni la lógica del
// odómetro retroactivo (TELEMETRIA_HISTORICO). Eso queda en sus servicios
// dedicados.
// =============================================================================

enum _FuenteArchivoVehiculo { camara, galeria, archivo }

class VehiculoActions {
  VehiculoActions._();

  /// Actualiza un campo simple en el doc del vehículo. `valor` puede
  /// ser `null` para limpiar el campo.
  static Future<void> dato(
    BuildContext context,
    String patente,
    String campo,
    dynamic valor,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final pat = patente.trim().toUpperCase();
    if (pat.isEmpty) {
      AppFeedback.errorOn(messenger, 'Patente vacía.');
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection(AppCollections.vehiculos)
          .doc(pat)
          .update({
        campo: valor,
        'fecha_ultima_actualizacion': FieldValue.serverTimestamp(),
      });
      unawaited(AuditLog.registrar(
        accion: AuditAccion.editarVehiculo,
        entidad: 'VEHICULOS',
        entidadId: pat,
        detalles: {'campo': campo, 'nuevo_valor': valor?.toString() ?? ''},
      ));
      AppFeedback.successOn(messenger, 'Actualizado: $campo');
    } catch (e) {
      AppFeedback.errorOn(messenger, 'Error al actualizar: $e');
    }
  }

  /// Sheet con opciones para gestionar un vencimiento del vehículo
  /// (RTO, Seguro, Extintor Cabina, Extintor Exterior): editar fecha,
  /// ver el archivo cargado, o subir/reemplazar el archivo.
  ///
  /// Espejo del `EmpleadoActions.documento` que usa la ficha de
  /// personal — mismo UX para el admin.
  static void documento(
    BuildContext context, {
    required String patente,
    required String etiqueta,
    required String campoFecha,
    required String campoUrl,
    required String? fechaActual,
    required String? urlActual,
  }) {
    final pat = patente.trim().toUpperCase();
    final navigator = Navigator.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
          border: const Border(
              top: BorderSide(color: AppColors.accentGreen, width: 2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              etiqueta,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 15),
            ListTile(
              leading:
                  const Icon(Icons.event_note, color: AppColors.accentBlue),
              title: const Text('Editar fecha de vencimiento',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                navigator.pop();
                _seleccionarFecha(context, pat, campoFecha, fechaActual);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.visibility, color: AppColors.accentGreen),
              title: const Text('Ver documento digital',
                  style: TextStyle(color: Colors.white)),
              enabled: urlActual != null &&
                  urlActual.isNotEmpty &&
                  urlActual != '-',
              onTap: () {
                navigator.pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PreviewScreen(
                      url: urlActual!,
                      titulo: '$etiqueta - $pat',
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file,
                  color: AppColors.accentOrange),
              title: Text(
                urlActual != null &&
                        urlActual.isNotEmpty &&
                        urlActual != '-'
                    ? 'Reemplazar archivo cargado'
                    : 'Subir archivo nuevo',
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Foto o PDF',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              onTap: () {
                navigator.pop();
                _reemplazarDocumento(
                  context: context,
                  patente: pat,
                  etiqueta: etiqueta,
                  campoUrl: campoUrl,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ===== privados ==========================================================

  static Future<void> _seleccionarFecha(
    BuildContext context,
    String patente,
    String campo,
    String? fechaActual,
  ) async {
    final initial = AppFormatters.tryParseFecha(fechaActual ?? '');
    final picked = await pickFecha(
      context,
      initial: initial,
      titulo:
          'Vencimiento ${campo.replaceAll("VENCIMIENTO_", "").replaceAll("_", " ")}',
    );
    if (picked != null && context.mounted) {
      final nuevaFecha = AppFormatters.aIsoFechaLocal(picked);
      await dato(context, patente, campo, nuevaFecha);
    }
  }

  /// Sheet de origen del archivo (cámara / galería / PDF) y upload.
  static Future<void> _reemplazarDocumento({
    required BuildContext context,
    required String patente,
    required String etiqueta,
    required String campoUrl,
  }) async {
    final picker = ImagePicker();

    final fuente = await showModalBottomSheet<_FuenteArchivoVehiculo>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sCtx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(sCtx).colorScheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(25)),
          border: const Border(
              top: BorderSide(color: AppColors.accentGreen, width: 2)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  etiqueta,
                  style: const TextStyle(
                    color: AppColors.accentGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              ListTile(
                leading:
                    const Icon(Icons.camera_alt, color: AppColors.accentGreen),
                title: const Text('Tomar foto con la cámara',
                    style: TextStyle(color: Colors.white)),
                onTap: () =>
                    Navigator.pop(sCtx, _FuenteArchivoVehiculo.camara),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library,
                    color: AppColors.accentBlue),
                title: const Text('Foto desde la galería',
                    style: TextStyle(color: Colors.white)),
                onTap: () =>
                    Navigator.pop(sCtx, _FuenteArchivoVehiculo.galeria),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf,
                    color: AppColors.accentRed),
                title: const Text('PDF / archivo del dispositivo',
                    style: TextStyle(color: Colors.white)),
                onTap: () =>
                    Navigator.pop(sCtx, _FuenteArchivoVehiculo.archivo),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );

    if (fuente == null) return;
    if (!context.mounted) return;

    Uint8List? bytes;
    String nombreOriginal = '';
    String extension = 'jpg';

    switch (fuente) {
      case _FuenteArchivoVehiculo.camara:
      case _FuenteArchivoVehiculo.galeria:
        final source = fuente == _FuenteArchivoVehiculo.camara
            ? ImageSource.camera
            : ImageSource.gallery;
        final img = await picker.pickImage(source: source, imageQuality: 60);
        if (img == null) return;
        bytes = await img.readAsBytes();
        nombreOriginal = img.name;
        extension = 'jpg';
        break;
      case _FuenteArchivoVehiculo.archivo:
        final res = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
          withData: true,
        );
        final picked = res?.files.singleOrNull;
        if (picked == null || picked.bytes == null) return;
        bytes = picked.bytes;
        nombreOriginal = picked.name;
        extension = picked.extension?.toLowerCase() ?? 'pdf';
        break;
    }

    if (!context.mounted) return;
    if (bytes == null) return;
    final storagePath =
        'VEHICULOS/$patente/${campoUrl}_${DateTime.now().millisecondsSinceEpoch}.$extension';
    await _subirArchivo(
        context, patente, bytes, nombreOriginal, storagePath, campoUrl);
  }

  static Future<void> _subirArchivo(
    BuildContext context,
    String patente,
    Uint8List bytes,
    String nombreOriginal,
    String storagePath,
    String dbCampo,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      AppFeedback.infoOn(messenger, 'Subiendo archivo...');
      final downloadUrl = await StorageService().subirArchivo(
        bytes: bytes,
        nombreOriginal: nombreOriginal,
        rutaStorage: storagePath,
      );
      if (context.mounted) {
        await dato(context, patente, dbCampo, downloadUrl);
      }
    } catch (e) {
      if (context.mounted) {
        AppFeedback.errorOn(messenger, 'Error al subir: $e');
      }
    }
  }
}

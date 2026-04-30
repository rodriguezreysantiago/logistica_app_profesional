import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
// `flutter/services` re-exporta Uint8List (dart:typed_data) — lo usa
// `_subirArchivo` para los uploads cross-platform.
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/audit_log_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../shared/utils/app_feedback.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/fecha_dialog.dart';

// =============================================================================
// SERVICIOS DE ACTUALIZACIÓN — NAMESPACE EmpleadoActions
//
// Centraliza las operaciones que tocan Firestore/Storage para gestión de
// personal desde las pantallas de admin (dialogs, sheets, audit, feedback).
//
// Esta capa es UI-aware: abre showModalBottomSheet, levanta SnackBars,
// registra `AuditLog`, etc. Si necesitás CRUD puro de Firestore sin UI,
// usá `EmpleadoService` en este mismo directorio.
//
// Originalmente vivía como `_Actualizar` privado dentro de
// `admin_personal_lista_screen.dart`. Extraído acá para bajar de 1295
// líneas a ~740 ese archivo y permitir reuso desde otras pantallas.
// =============================================================================

enum _FuenteArchivoChofer { camara, galeria, archivo }

class EmpleadoActions {
  EmpleadoActions._();

  /// Actualiza un campo simple en EMPLEADOS.
  static Future<void> dato(
    BuildContext context,
    String dni,
    String campo,
    dynamic valor,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance
          .collection('EMPLEADOS')
          .doc(dni.trim())
          .update({
        campo: valor,
        'fecha_ultima_actualizacion': FieldValue.serverTimestamp(),
      });
      unawaited(AuditLog.registrar(
        accion: AuditAccion.editarChofer,
        entidad: 'EMPLEADOS',
        entidadId: dni.trim(),
        detalles: {'campo': campo, 'nuevo_valor': valor?.toString() ?? ''},
      ));
      AppFeedback.successOn(messenger, 'Dato actualizado: $campo');
    } catch (e) {
      AppFeedback.errorOn(messenger, 'Error al actualizar: $e');
    }
  }

  /// Endpoint del callable `actualizarRolEmpleado`. Mismo patrón que
  /// AuditLog y volvoProxy — llamamos por HTTPS directo con Dio porque
  /// el plugin oficial `cloud_functions` no tiene impl Windows.
  static const String _endpointActualizarRol =
      'https://us-central1-logisticaapp-e539a.cloudfunctions.net/actualizarRolEmpleado';

  static Dio? _dioCallable;
  static Dio get _httpCallable => _dioCallable ??= Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 12),
          sendTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 12),
        ),
      );

  /// Actualiza ROL y/o ÁREA de un empleado vía Cloud Function. La
  /// function valida server-side que el caller sea ADMIN, actualiza
  /// Firestore Y refresca el custom claim del usuario afectado para
  /// que su próximo getIdToken(true) traiga el rol nuevo.
  ///
  /// Pasar `null` en alguno de los dos campos significa "no tocar".
  /// Pero al menos uno debe venir poblado.
  static Future<void> actualizarRol(
    BuildContext context,
    String dni, {
    String? nuevoRol,
    String? nuevaArea,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    if (nuevoRol == null && nuevaArea == null) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        AppFeedback.errorOn(messenger, 'Sin sesión activa.');
        return;
      }
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        AppFeedback.errorOn(messenger, 'No se pudo obtener el token de sesión.');
        return;
      }

      final response = await _httpCallable.post<Map<String, dynamic>>(
        _endpointActualizarRol,
        data: {
          // Protocolo callable: payload va envuelto en `data`.
          'data': {
            'dni': dni.trim(),
            if (nuevoRol != null) 'rol': nuevoRol,
            if (nuevaArea != null) 'area': nuevaArea,
          },
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          validateStatus: (_) => true,
          responseType: ResponseType.json,
        ),
      );

      if (response.statusCode == null || response.statusCode! >= 400) {
        final err = response.data?['error'] as Map<String, dynamic>?;
        final mensaje = err?['message']?.toString() ??
            'Error ${response.statusCode} al actualizar rol.';
        // 403 → permission denied; lo decimos en lenguaje del usuario.
        final txtUI = response.statusCode == 403
            ? 'Solo ADMIN puede cambiar roles.'
            : mensaje;
        AppFeedback.errorOn(messenger, txtUI);
        return;
      }

      final result = response.data?['result'] as Map<String, dynamic>?;
      unawaited(AuditLog.registrar(
        accion: AuditAccion.editarChofer,
        entidad: 'EMPLEADOS',
        entidadId: dni.trim(),
        detalles: {
          'campo': nuevoRol != null ? 'ROL/AREA' : 'AREA',
          'rol_nuevo': result?['rol']?.toString() ?? '',
          'area_nueva': result?['area']?.toString() ?? '',
        },
      ));
      final mensaje = nuevoRol != null
          ? 'Rol actualizado a ${nuevoRol.toLowerCase()}'
          : 'Área actualizada';
      AppFeedback.successOn(messenger, mensaje);
    } catch (e) {
      AppFeedback.errorOn(messenger, 'Error al actualizar rol: $e');
    }
  }

  /// Abre un sheet con opciones para gestionar la foto de perfil.
  static Future<void> fotoPerfil(
    BuildContext context,
    String dni,
    String? urlActual,
  ) async {
    final picker = ImagePicker();
    final navigator = Navigator.of(context);

    // El Future de showModalBottomSheet se completa cuando el sheet
    // se cierra. Acá solo lo abrimos y nos vamos — la lógica de subir
    // la foto vive dentro de los onTap de los ListTile, no dependemos
    // del valor de retorno.
    unawaited(showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(25)),
          border: const Border(
              top: BorderSide(color: Colors.greenAccent, width: 2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Foto de perfil',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 15),
            ListTile(
              leading: const Icon(Icons.visibility, color: Colors.blueAccent),
              title: const Text('Ver foto actual',
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
                      titulo: 'Foto de $dni',
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library,
                  color: Colors.greenAccent),
              title: const Text('Subir nueva desde galería',
                  style: TextStyle(color: Colors.white)),
              onTap: () async {
                navigator.pop();
                final image = await picker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 50,
                );
                if (image != null && context.mounted) {
                  // readAsBytes() es cross-platform; image.path en Web es un
                  // blob URL que no se puede abrir como dart:io.File.
                  final bytes = await image.readAsBytes();
                  if (!context.mounted) return;
                  await _subirArchivo(
                    context,
                    dni,
                    bytes,
                    image.name,
                    'perfiles/$dni.jpg',
                    'ARCHIVO_PERFIL',
                  );
                }
              },
            ),
          ],
        ),
      ),
    ));
  }

  /// Sube los bytes de un archivo a Storage y guarda la URL en Firestore.
  /// Detecta el contentType según la extensión vía `StorageService` —
  /// que es cross-platform (no usa `dart:io.File`).
  static Future<void> _subirArchivo(
    BuildContext context,
    String id,
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
        await dato(context, id, dbCampo, downloadUrl);
      }
    } catch (e) {
      if (context.mounted) {
        AppFeedback.errorOn(messenger, 'Error al subir: $e');
      }
    }
  }

  /// Abre un sheet para que el admin elija de dónde tomar el archivo
  /// (cámara, galería, o PDF/imagen del dispositivo) y lo sube.
  /// Pensado para reemplazar papeles del chofer (licencia, ART, etc.).
  static Future<void> _reemplazarDocumentoChofer({
    required BuildContext context,
    required String dni,
    required String etiqueta,
    required String campoUrl,
  }) async {
    final picker = ImagePicker();

    final fuente = await showModalBottomSheet<_FuenteArchivoChofer>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sCtx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(sCtx).colorScheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(25)),
          border: const Border(
              top: BorderSide(color: Colors.greenAccent, width: 2)),
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
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              ListTile(
                leading:
                    const Icon(Icons.camera_alt, color: Colors.greenAccent),
                title: const Text('Tomar foto con la cámara',
                    style: TextStyle(color: Colors.white)),
                onTap: () =>
                    Navigator.pop(sCtx, _FuenteArchivoChofer.camara),
              ),
              ListTile(
                leading:
                    const Icon(Icons.photo_library, color: Colors.blueAccent),
                title: const Text('Foto desde la galería',
                    style: TextStyle(color: Colors.white)),
                onTap: () =>
                    Navigator.pop(sCtx, _FuenteArchivoChofer.galeria),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf,
                    color: Colors.redAccent),
                title: const Text('PDF / archivo del dispositivo',
                    style: TextStyle(color: Colors.white)),
                onTap: () =>
                    Navigator.pop(sCtx, _FuenteArchivoChofer.archivo),
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
      case _FuenteArchivoChofer.camara:
      case _FuenteArchivoChofer.galeria:
        final source = fuente == _FuenteArchivoChofer.camara
            ? ImageSource.camera
            : ImageSource.gallery;
        final img = await picker.pickImage(source: source, imageQuality: 60);
        if (img == null) return;
        // readAsBytes(): cross-platform (Web devuelve blob bytes, no File).
        bytes = await img.readAsBytes();
        nombreOriginal = img.name;
        extension = 'jpg';
        break;
      case _FuenteArchivoChofer.archivo:
        // withData: true para que `bytes` venga poblado en Web también.
        final res = await FilePicker.platform.pickFiles(
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

    // Después del picker viene otro await: revalidamos contra el mismo
    // BuildContext que vamos a pasar a _subirArchivo (el lint pide eso).
    if (!context.mounted) return;
    if (bytes == null) return;
    final storagePath =
        'EMPLEADOS/$dni/${campoUrl}_${DateTime.now().millisecondsSinceEpoch}.$extension';
    await _subirArchivo(
        context, dni, bytes, nombreOriginal, storagePath, campoUrl);
  }

  /// Sheet con opciones para gestionar un documento (fecha + archivo).
  static void documento(
    BuildContext context, {
    required String dni,
    required String etiqueta,
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
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(25)),
          border: const Border(
              top: BorderSide(color: Colors.greenAccent, width: 2)),
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
                  const Icon(Icons.event_note, color: Colors.blueAccent),
              title: const Text('Editar fecha de vencimiento',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                navigator.pop();
                _seleccionarFecha(context, dni, campoFecha, fechaActual);
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility, color: Colors.greenAccent),
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
                      titulo: '$etiqueta - $dni',
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file,
                  color: Colors.orangeAccent),
              title: Text(
                urlActual != null &&
                        urlActual.isNotEmpty &&
                        urlActual != '-'
                    ? 'Reemplazar archivo cargado'
                    : 'Subir archivo nuevo',
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Foto o PDF — sin pasar por el flujo de revisión',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              onTap: () {
                navigator.pop();
                _reemplazarDocumentoChofer(
                  context: context,
                  dni: dni,
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

  static Future<void> _seleccionarFecha(
    BuildContext context,
    String dni,
    String campo,
    String? fechaActual,
  ) async {
    final initial = DateTime.tryParse(fechaActual ?? '');
    final picked = await pickFecha(
      context,
      initial: initial,
      titulo: 'Vencimiento ${campo.replaceAll("VENCIMIENTO_", "").replaceAll("_", " ")}',
    );
    if (picked != null && context.mounted) {
      final nuevaFecha = picked.toString().split(' ').first;
      await dato(context, dni, campo, nuevaFecha);
    }
  }

  /// Selector de unidad (tractor o enganche).
  static void unidad(
    BuildContext context,
    String dni,
    String campo,
    String patenteActual,
  ) {
    final tipos = (campo == 'VEHICULO')
        ? <String>[AppTiposVehiculo.tractor]
        : AppTiposVehiculo.enganches;
    // Capturamos el messenger del scaffold padre antes de abrir el dialog;
    // lo usamos después del batch.commit para mostrar feedback al admin
    // (ScaffoldMessenger.of(dCtx) no aplica una vez cerrado el dialog).
    final messenger = ScaffoldMessenger.of(context);
    final esTractor = campo == 'VEHICULO';
    final etiquetaUnidad = esTractor ? 'tractor' : 'enganche';

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text("Asignar $etiquetaUnidad"),
        content: SizedBox(
          width: double.maxFinite,
          height: 350,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('VEHICULOS')
                .where('TIPO', whereIn: tipos)
                .snapshots(),
            builder: (ctx, snap) {
              if (!snap.hasData) {
                return const Center(
                  child: CircularProgressIndicator(
                      color: Colors.greenAccent),
                );
              }

              final unidades = snap.data!.docs;

              Future<void> procesarCambio(String? nueva) async {
                final db = FirebaseFirestore.instance;
                final batch = db.batch();
                final cleanActual = patenteActual.trim();

                // Bug C5 del code review: el update de la unidad anterior
                // estaba FUERA del batch. Si fallaba, la unidad anterior
                // quedaba en OCUPADO sin que nadie pudiera asignarla.
                // Ahora todo va en el mismo batch — atómico.
                final hayActualValido = cleanActual.isNotEmpty &&
                    cleanActual != '-' &&
                    cleanActual != 'S/D';

                if (nueva != null && nueva != '-') {
                  batch.update(
                    db.collection('VEHICULOS').doc(nueva),
                    {'ESTADO': 'OCUPADO'},
                  );
                  batch.update(
                    db.collection('EMPLEADOS').doc(dni),
                    {campo: nueva},
                  );
                } else {
                  batch.update(
                    db.collection('EMPLEADOS').doc(dni),
                    {campo: '-'},
                  );
                }

                // Liberar la unidad anterior siempre dentro del mismo batch.
                // Si el doc no existe, batch.commit() falla — pero eso ya
                // pasaba antes con el update individual, así que el
                // comportamiento es equivalente al del fix.
                if (hayActualValido) {
                  batch.update(
                    db.collection('VEHICULOS').doc(cleanActual),
                    {'ESTADO': 'LIBRE'},
                  );
                }

                try {
                  await batch.commit();

                  unawaited(AuditLog.registrar(
                    accion: (nueva == null || nueva == '-')
                        ? AuditAccion.desvincularEquipo
                        : AuditAccion.asignarEquipo,
                    entidad: 'EMPLEADOS',
 
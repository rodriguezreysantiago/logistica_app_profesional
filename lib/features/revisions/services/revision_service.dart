import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
// `flutter/foundation` re-exporta Uint8List (de dart:typed_data) además de
// debugPrint, así que cubre los dos usos de este archivo en un solo import.
import 'package:flutter/foundation.dart';

import '../../../core/services/storage_service.dart';

/// Servicio del feature de revisiones.
///
/// Centraliza:
/// - **Chofer**: registrar una nueva solicitud de renovación de papel
///   (sube el archivo + crea el doc en `REVISIONES`).
/// - **Admin**: aprobar/rechazar revisiones (procesa el cambio en la
///   colección destino y elimina la solicitud).
/// - Stream paginado de pendientes.
///
/// Antes esto vivía en `core/services/firebase_service.dart` mezclado
/// con storage, empleados y paginación.
class RevisionService {
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final StorageService _storageService;

  RevisionService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    StorageService? storageService,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _storageService = storageService ?? StorageService();

  // ===========================================================================
  // CHOFER → registrar solicitud
  // ===========================================================================

  /// Sube el comprobante a Storage y crea el documento de solicitud
  /// en la colección `REVISIONES`.
  ///
  /// [archivoBytes] son los bytes del archivo (cross-platform: el caller
  /// los obtiene de `XFile.readAsBytes()` o `FilePicker(withData: true)`).
  /// [nombreOriginal] se usa solo para extraer la extensión.
  Future<void> registrarSolicitud({
    required String dni,
    required String nombreUsuario,
    required String etiqueta,
    required String campo,
    required Uint8List archivoBytes,
    required String nombreOriginal,
    required String fechaS,
    required String coleccionDestino,
  }) async {
    // Defensa profunda: nunca dejamos crear solicitudes con campos críticos
    // vacíos. De lo contrario, después el admin no la puede aprobar porque
    // .doc('') revienta. Mejor fallar acá con mensaje claro.
    if (dni.trim().isEmpty ||
        campo.trim().isEmpty ||
        coleccionDestino.trim().isEmpty) {
      throw ArgumentError(
        'Solicitud incompleta: faltan dni, campo o coleccion_destino.',
      );
    }

    try {
      final extension = nombreOriginal.split('.').last.toLowerCase();
      final nombreArchivo =
          'REVISIONES/${dni}_${campo}_${DateTime.now().millisecondsSinceEpoch}.$extension';

      // Reutilizamos el StorageService genérico (incluye timeout y content-type)
      final url = await _storageService.subirArchivo(
        bytes: archivoBytes,
        nombreOriginal: nombreOriginal,
        rutaStorage: nombreArchivo,
      );

      await _db.collection('REVISIONES').add({
        'dni': dni.trim(),
        'nombre_usuario': nombreUsuario,
        'campo': campo,
        'coleccion_destino': coleccionDestino,
        'etiqueta': etiqueta,
        'fecha_vencimiento': fechaS,
        'url_archivo': url,
        'path_storage': nombreArchivo,
        'estado': 'PENDIENTE',
        'fecha_solicitud': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Error al registrar solicitud: $e');
    }
  }

  // ===========================================================================
  // ADMIN → aprobar/rechazar
  // ===========================================================================

  /// Aprueba o rechaza una revisión.
  ///
  /// Si [aprobado]:
  /// - Para `VENCIMIENTO_*`: actualiza fecha + URL del archivo en el doc destino.
  /// - Para `SOLICITUD_VEHICULO/SOLICITUD_ENGANCHE`: cambia la asignación del
  ///   chofer y actualiza ESTADO de las unidades vieja/nueva.
  ///
  /// Si rechazada: borra el archivo de Storage para no acumular basura.
  ///
  /// En ambos casos, la solicitud se elimina al final (no quedan registros
  /// históricos). Si querés histórico, cambiar `delete` por un `update` con
  /// `estado: APROBADO`/`RECHAZADO`.
  Future<void> finalizarRevision({
    required String idSolicitud,
    required bool aprobado,
    Map<String, dynamic>? datos,
  }) async {
    // Sin id de la solicitud no podemos ni siquiera borrarla; abortamos
    // antes de tocar Firestore para evitar el "document path must be a
    // non-empty string" que se ve clarísimo en producción.
    if (idSolicitud.trim().isEmpty) {
      throw StateError('La solicitud no tiene ID válido.');
    }

    try {
      final batch = _db.batch();

      if (aprobado && datos != null) {
        final colDestino = (datos['coleccion_destino'] ?? '').toString().trim();
        final idDoc = (datos['dni'] ?? '').toString().trim();
        final campoAct = (datos['campo'] ?? '').toString().trim();

        // Cualquier campo path-relevante vacío ⇒ Firestore revienta.
        if (colDestino.isEmpty || idDoc.isEmpty || campoAct.isEmpty) {
          // Limpiamos la solicitud inválida y devolvemos un error útil.
          await _db.collection('REVISIONES').doc(idSolicitud).delete();
          throw StateError(
            'La solicitud está incompleta (faltan datos de destino o '
            'campo a actualizar). Se eliminó del listado.',
          );
        }

        final destinoRef = _db.collection(colDestino).doc(idDoc);
        final camposAActualizar = <String, dynamic>{};

        if (campoAct.startsWith('VENCIMIENTO_')) {
          final campoArchivo =
              campoAct.replaceAll('VENCIMIENTO_', 'ARCHIVO_');
          camposAActualizar[campoAct] = datos['fecha_vencimiento'];
          camposAActualizar[campoArchivo] = datos['url_archivo'];
          camposAActualizar['ultima_auditoria'] =
              FieldValue.serverTimestamp();
        } else if (campoAct == 'SOLICITUD_VEHICULO' ||
            campoAct == 'SOLICITUD_ENGANCHE') {
          final campoDestino =
              campoAct == 'SOLICITUD_VEHICULO' ? 'VEHICULO' : 'ENGANCHE';
          final nuevaUnidad = (datos['patente'] ?? '').toString().trim();
          final unidadActual = (datos['unidad_actual'] ?? '').toString().trim();

          camposAActualizar[campoDestino] = nuevaUnidad;

          if (nuevaUnidad.isNotEmpty && nuevaUnidad != '-') {
            batch.update(
              _db.collection('VEHICULOS').doc(nuevaUnidad),
              {'ESTADO': 'ASIGNADO'},
            );
          }
          if (unidadActual.isNotEmpty &&
              unidadActual != '-' &&
              unidadActual.toUpperCase() != 'SIN ASIGNAR') {
            batch.update(
              _db.collection('VEHICULOS').doc(unidadActual),
              {'ESTADO': 'LIBRE'},
            );
          }
        } else {
          camposAActualizar[campoAct] = datos['fecha_vencimiento'];
        }

        batch.update(destinoRef, camposAActualizar);
      }

      // Si fue rechazada, borramos el archivo de Storage
      if (!aprobado &&
          datos != null &&
          datos['path_storage'] != null &&
          datos['path_storage'].toString().isNotEmpty) {
        try {
          await _storage.ref().child(datos['path_storage']).delete();
        } catch (e) {
          debugPrint('No se pudo borrar archivo: $e');
        }
      }

      // Eliminar la solicitud al cerrar el batch
      batch.delete(_db.collection('REVISIONES').doc(idSolicitud));
      await batch.commit();
    } on StateError {
      // Re-lanzamos los errores estructurados sin envolverlos: el caller
      // los muestra con su mensaje legible.
      rethrow;
    } catch (e) {
      throw Exception('Error al finalizar la revisión: $e');
    }
  }

  // ===========================================================================
  // STREAMS
  // ===========================================================================

  /// Stream de las primeras 50 solicitudes pendientes,
  /// ordenadas por fecha (más recientes primero).
  Stream<QuerySnapshot> getPendientes() {
    return _db
        .collection('REVISIONES')
        .where('estado', isEqualTo: 'PENDIENTE')
        .orderBy('fecha_solicitud', descending: true)
        .limit(50)
        .snapshots();
  }
}

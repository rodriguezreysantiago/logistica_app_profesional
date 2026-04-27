import 'dart:io';
import 'dart:async'; // ✅ MENTOR: Necesario para manejar TimeoutException
import 'package:flutter/foundation.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // ===========================================================================
  // 1. MÉTODOS DE SUBIDA GENÉRICOS
  // ===========================================================================

  Future<String> subirArchivoGenerico({
    required File archivo,
    required String rutaStorage,
  }) async {
    try {
      String extension = archivo.path.split('.').last.toLowerCase();
      String contentType = _obtenerContentType(extension);

      final ref = _storage.ref().child(rutaStorage);
      
      // ✅ MEJORA PRO: Timeout de 30s. Evita que la app se congele en rutas sin 4G.
      await ref.putFile(archivo, SettableMetadata(contentType: contentType))
          .timeout(const Duration(seconds: 30), onTimeout: () {
            throw TimeoutException('La conexión es demasiado lenta para subir el archivo.');
          });
      
      return await ref.getDownloadURL();
    } catch (e) {
      throw Exception("Error en FirebaseStorage: $e");
    }
  }

  // ===========================================================================
  // 2. SOLICITUDES DE REVISIÓN (Chofer)
  // ===========================================================================
  
  Future<void> registrarSolicitudRevision({
    required String dni,
    required String nombreUsuario, 
    required String etiqueta,
    required String campo,
    required File archivo,
    required String fechaS,
    required String coleccionDestino,
  }) async {
    try {
      String extension = archivo.path.split('.').last.toLowerCase();
      String contentType = _obtenerContentType(extension);

      final String nombreArchivo = 'REVISIONES/${dni}_${campo}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      
      final ref = _storage.ref().child(nombreArchivo);
      
      // ✅ MEJORA PRO: Protección de red para las subidas de los choferes
      await ref.putFile(archivo, SettableMetadata(contentType: contentType))
          .timeout(const Duration(seconds: 30), onTimeout: () {
            throw TimeoutException('Sin señal suficiente para subir la imagen de revisión.');
          });
          
      String url = await ref.getDownloadURL();

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
      throw Exception("Error al registrar solicitud: $e");
    }
  }

  // --- Helper para Content-Type ---
  String _obtenerContentType(String extension) {
    if (extension == 'pdf') return 'application/pdf';
    if (extension == 'png') return 'image/png';
    return 'image/jpeg'; // Fallback por defecto para jpg/jpeg
  }

  // ===========================================================================
  // 3. GESTIÓN DE USUARIOS / EMPLEADOS
  // ===========================================================================

  Future<void> actualizarDatoEmpleado(String dni, String campo, dynamic valor) async {
    try {
      await _db.collection('EMPLEADOS').doc(dni).update({
        campo: valor,
      });
    } catch (e) {
      throw Exception("Error al actualizar $campo: $e");
    }
  }

  // ===========================================================================
  // 4. CONSULTAS Y PROCESAMIENTO (Admin)
  // ===========================================================================

  Future<void> finalizarRevision({
    required String idSolicitud,
    required bool aprobado,
    Map<String, dynamic>? datos,
  }) async {
    try {
      WriteBatch batch = _db.batch();

      if (aprobado && datos != null) {
        String colDestino = datos['coleccion_destino'];
        String idDoc = datos['dni'];
        String campoAct = datos['campo'];
        
        DocumentReference destinoRef = _db.collection(colDestino).doc(idDoc);
        Map<String, dynamic> camposAActualizar = {};

        if (campoAct.startsWith('VENCIMIENTO_')) {
          String campoArchivo = campoAct.replaceAll('VENCIMIENTO_', 'ARCHIVO_');
          camposAActualizar[campoAct] = datos['fecha_vencimiento'];
          camposAActualizar[campoArchivo] = datos['url_archivo'];
          camposAActualizar['ultima_auditoria'] = FieldValue.serverTimestamp();
          
        } else if (campoAct == 'SOLICITUD_VEHICULO' || campoAct == 'SOLICITUD_ENGANCHE') {
          String campoDestino = campoAct == 'SOLICITUD_VEHICULO' ? 'VEHICULO' : 'ENGANCHE';
          String nuevaUnidad = datos['patente'] ?? '';
          String unidadActual = datos['unidad_actual'] ?? '';
          
          camposAActualizar[campoDestino] = nuevaUnidad;
          
          if (nuevaUnidad.isNotEmpty && nuevaUnidad != "-") {
            DocumentReference vehiculoNuevoRef = _db.collection('VEHICULOS').doc(nuevaUnidad);
            batch.update(vehiculoNuevoRef, {'ESTADO': 'ASIGNADO'});
          }
          if (unidadActual.isNotEmpty && unidadActual != "-" && unidadActual != "SIN ASIGNAR") {
            DocumentReference vehiculoViejoRef = _db.collection('VEHICULOS').doc(unidadActual);
            batch.update(vehiculoViejoRef, {'ESTADO': 'LIBRE'});
          }
          
        } else {
          camposAActualizar[campoAct] = datos['fecha_vencimiento'];
        }

        batch.update(destinoRef, camposAActualizar);
      } 
      
      if (!aprobado && datos != null && datos['path_storage'] != null && datos['path_storage'].toString().isNotEmpty) {
        try {
          // El borrado de archivos en background no necesita trabar el proceso principal
          // por lo que no es estrictamente necesario un timeout aquí, pero controlamos el error.
          await _storage.ref().child(datos['path_storage']).delete();
        } catch (e) {
          debugPrint("El archivo no existía o no se pudo borrar: $e");
        }
      }

      DocumentReference solicitudRef = _db.collection('REVISIONES').doc(idSolicitud);
      batch.delete(solicitudRef);

      await batch.commit();
    } catch (e) {
      throw Exception("Error al finalizar la revisión: $e");
    }
  }

  Stream<QuerySnapshot> getSolicitudesPendientes() {
    return _db
        .collection('REVISIONES')
        .where('estado', isEqualTo: 'PENDIENTE')
        .orderBy('fecha_solicitud', descending: true)
        .limit(50) 
        .snapshots();
  }

  // ===========================================================================
  // 5. MOTOR DE PAGINACIÓN DE FLOTA Y PERSONAL (CONTROL DE COSTOS)
  // ===========================================================================

  Future<QuerySnapshot> getVehiculosPaginados({
    required int limit,
    DocumentSnapshot? lastDocument,
  }) async {
    Query query = _db
        .collection('VEHICULOS')
        .orderBy(FieldPath.documentId) 
        .limit(limit);

    if (lastDocument != null) {
      query = query.startAfterDocument(lastDocument);
    }

    return await query.get();
  }

  Future<QuerySnapshot> getEmpleadosPaginados({
    required int limit,
    DocumentSnapshot? lastDocument,
  }) async {
    Query query = _db
        .collection('EMPLEADOS')
        // ✅ CORRECCIÓN CRÍTICA: El campo en la base es 'NOMBRE', no 'nombre_completo'.
        // Si no se cambia, esta consulta devolverá 0 resultados siempre o fallará por falta de índice.
        .orderBy('NOMBRE') 
        .limit(limit);

    if (lastDocument != null) {
      query = query.startAfterDocument(lastDocument);
    }

    return await query.get();
  }
}
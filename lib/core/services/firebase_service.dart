import 'dart:io';
import 'package:flutter/foundation.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // --- 1. MÉTODOS DE SUBIDA GENÉRICOS ---

  Future<String> subirArchivoGenerico({
    required File archivo,
    required String rutaStorage,
  }) async {
    try {
      String extension = archivo.path.split('.').last.toLowerCase();
      String contentType = _obtenerContentType(extension);

      final ref = _storage.ref().child(rutaStorage);
      await ref.putFile(archivo, SettableMetadata(contentType: contentType));
      
      return await ref.getDownloadURL();
    } catch (e) {
      throw Exception("Error en FirebaseStorage: $e");
    }
  }

  // --- 2. SOLICITUDES DE REVISIÓN (Chofer) ---
  
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
      await ref.putFile(archivo, SettableMetadata(contentType: contentType));
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

  // --- 3. GESTIÓN DE USUARIOS / EMPLEADOS ---

  Future<void> actualizarDatoEmpleado(String dni, String campo, dynamic valor) async {
    try {
      await _db.collection('EMPLEADOS').doc(dni).update({
        campo: valor,
      });
    } catch (e) {
      throw Exception("Error al actualizar $campo: $e");
    }
  }

  // --- 4. CONSULTAS Y PROCESAMIENTO (Admin) ---

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
          // Trámite de Papeles: Guardamos la fecha Y la URL del archivo
          String campoArchivo = campoAct.replaceAll('VENCIMIENTO_', 'ARCHIVO_');
          camposAActualizar[campoAct] = datos['fecha_vencimiento'];
          camposAActualizar[campoArchivo] = datos['url_archivo'];
          camposAActualizar['ultima_auditoria'] = FieldValue.serverTimestamp();
          
        } else if (campoAct == 'SOLICITUD_VEHICULO' || campoAct == 'SOLICITUD_ENGANCHE') {
          // ✅ MENTOR: Lógica corregida para la rotación de flota
          String campoDestino = campoAct == 'SOLICITUD_VEHICULO' ? 'VEHICULO' : 'ENGANCHE';
          String nuevaUnidad = datos['patente'] ?? '';
          String unidadActual = datos['unidad_actual'] ?? '';
          
          camposAActualizar[campoDestino] = nuevaUnidad;
          
          // Ocupamos la nueva unidad
          if (nuevaUnidad.isNotEmpty && nuevaUnidad != "-") {
            DocumentReference vehiculoNuevoRef = _db.collection('VEHICULOS').doc(nuevaUnidad);
            batch.update(vehiculoNuevoRef, {'ESTADO': 'ASIGNADO'});
          }
          // Liberamos la unidad vieja
          if (unidadActual.isNotEmpty && unidadActual != "-" && unidadActual != "SIN ASIGNAR") {
            DocumentReference vehiculoViejoRef = _db.collection('VEHICULOS').doc(unidadActual);
            batch.update(vehiculoViejoRef, {'ESTADO': 'LIBRE'});
          }
          
        } else {
          // Fallback de seguridad
          camposAActualizar[campoAct] = datos['fecha_vencimiento'];
        }

        batch.update(destinoRef, camposAActualizar);
      } 
      
      // Borramos el archivo del Storage solo si se RECHAZA. 
      if (!aprobado && datos != null && datos['path_storage'] != null && datos['path_storage'].toString().isNotEmpty) {
        try {
          await _storage.ref().child(datos['path_storage']).delete();
        } catch (e) {
          debugPrint("El archivo no existía o no se pudo borrar: $e");
        }
      }

      // Borramos la solicitud
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
        .snapshots();
  }
}
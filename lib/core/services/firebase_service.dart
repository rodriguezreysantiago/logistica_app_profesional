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
      String contentType = (extension == 'pdf') ? 'application/pdf' : 'image/jpeg';

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
    required String nombreUsuario, // <-- NUEVO: Recibimos el nombre
    required String etiqueta,
    required String campo,
    required File archivo,
    required String fechaS,
    required String coleccionDestino,
  }) async {
    try {
      String extension = archivo.path.split('.').last.toLowerCase();
      String contentType = extension == 'pdf' ? 'application/pdf' : 'image/jpeg';

      final String nombreArchivo = 'REVISIONES/${dni}_${campo}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      
      final ref = _storage.ref().child(nombreArchivo);
      await ref.putFile(archivo, SettableMetadata(contentType: contentType));
      String url = await ref.getDownloadURL();

      await _db.collection('REVISIONES').add({
        'dni': dni.trim(),
        'nombre_usuario': nombreUsuario, // <-- NUEVO: Guardamos el nombre en Firestore
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
        String nuevaF = datos['fecha_vencimiento'];

        DocumentReference destinoRef = _db.collection(colDestino).doc(idDoc);
        batch.update(destinoRef, {campoAct: nuevaF});
      } 
      
      if (!aprobado && datos != null && datos['path_storage'] != null) {
        try {
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
        .snapshots();
  }
}
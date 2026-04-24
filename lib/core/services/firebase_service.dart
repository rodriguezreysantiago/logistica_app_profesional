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
    required String nombreUsuario, 
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

        // ✅ Mentora: Lógica inteligente de enrutamiento de datos
        if (campoAct.startsWith('VENCIMIENTO_')) {
          // Trámite de Papeles: Guardamos la fecha Y la URL del archivo
          String campoArchivo = campoAct.replaceAll('VENCIMIENTO_', 'ARCHIVO_');
          camposAActualizar[campoAct] = datos['fecha_vencimiento'];
          camposAActualizar[campoArchivo] = datos['url_archivo'];
          camposAActualizar['ultima_auditoria'] = FieldValue.serverTimestamp();
          
        } else if (campoAct == 'SOLICITUD_VEHICULO') {
          // Trámite de Mi Equipo (Tractor)
          camposAActualizar['VEHICULO'] = datos['patente'];
          
        } else if (campoAct == 'SOLICITUD_ENGANCHE') {
          // Trámite de Mi Equipo (Batea/Tolva)
          camposAActualizar['ENGANCHE'] = datos['patente'];
          
        } else {
          // Fallback de seguridad
          camposAActualizar[campoAct] = datos['fecha_vencimiento'];
        }

        batch.update(destinoRef, camposAActualizar);
      } 
      
      // ✅ Mentora: Borramos el archivo del Storage solo si se RECHAZA. 
      // Si se aprueba, lo necesitamos alojado para verlo en los perfiles.
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
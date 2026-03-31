import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // --- 1. SOLICITUDES DE REVISIÓN (Chofer) ---
  
  Future<void> registrarSolicitudRevision({
    required String dni,
    required String etiqueta,
    required String campo,
    required File archivo,
    required String fechaS,
    required String coleccionDestino,
  }) async {
    // Detectar extensión y tipo de contenido para Storage
    String extension = archivo.path.split('.').last.toLowerCase();
    String contentType = extension == 'pdf' ? 'application/pdf' : 'image/jpeg';

    final String nombreArchivo = '${dni}_${campo}_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final ref = _storage.ref().child('REVISIONES/$nombreArchivo');
    
    // Subida con Metadatos (clave para que el navegador sepa si es PDF o Imagen)
    await ref.putFile(archivo, SettableMetadata(contentType: contentType));
    String url = await ref.getDownloadURL();

    // Crear el documento en la colección de trámites pendientes
    await _db.collection('REVISIONES').add({
      'DNI': dni.trim(),
      'CAMPO': campo,
      'COLECCION_DESTINO': coleccionDestino,
      'ETIQUETA': etiqueta,
      'NUEVA_FECHA': fechaS,
      'URL_ADJUNTO': url,
      'ESTADO': 'PENDIENTE', // Estado inicial siempre pendiente
      'FECHA_SOLICITUD': FieldValue.serverTimestamp(),
    });
  }

  // --- 2. CONSULTAS PARA EL ADMIN ---

  /// Obtiene el Stream de trámites pendientes (Arregla el error undefined_method)
  Stream<QuerySnapshot> getSolicitudesPendientes() {
    return _db
        .collection('REVISIONES')
        .where('ESTADO', isEqualTo: 'PENDIENTE')
        .orderBy('FECHA_SOLICITUD', descending: true)
        .snapshots();
  }

  /// Procesa una solicitud (Aprobar o Rechazar)
  Future<void> procesarSolicitud({
    required String solicitudId,
    required String nuevoEstado,
    String? dni,
    String? campo,
    String? nuevaFecha,
    String? coleccionDestino,
  }) async {
    WriteBatch batch = _db.batch();

    // 1. Actualizar el estado de la solicitud
    DocumentReference solicitudRef = _db.collection('REVISIONES').doc(solicitudId);
    batch.update(solicitudRef, {
      'ESTADO': nuevoEstado,
      'FECHA_PROCESADO': FieldValue.serverTimestamp(),
    });

    // 2. Si es APROBADO, impactar la nueva fecha en la ficha del empleado/vehículo
    if (nuevoEstado == 'APROBADO' && dni != null && campo != null && nuevaFecha != null) {
      DocumentReference destinoRef = _db.collection(coleccionDestino!).doc(dni);
      batch.update(destinoRef, {campo: nuevaFecha});
    }

    await batch.commit();
  }

  // --- 3. ACTUALIZACIÓN DIRECTA (Uso interno Admin) ---
  
  Future<void> actualizarImagenDirecta(String id, String campo, File archivo, String coleccion) async {
    String fileName = "admin_update_${id}_${DateTime.now().millisecondsSinceEpoch}.jpg";
    Reference ref = _storage.ref().child('documentos').child(fileName);
    await ref.putFile(archivo);
    String url = await ref.getDownloadURL();

    await _db.collection(coleccion).doc(id).update({'FOTO_$campo': url});
  }
}

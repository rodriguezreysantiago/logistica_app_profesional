import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // --- 1. MÉTODOS DE SUBIDA GENÉRICOS (Para Fotos de Perfil y otros) ---

  /// Sube cualquier archivo a Storage y devuelve la URL de descarga.
  /// Se usa para la Foto de Perfil.
  Future<String> subirArchivoGenerico({
    required File archivo,
    required String rutaStorage,
  }) async {
    try {
      // Determinamos el tipo de contenido según la extensión
      String extension = archivo.path.split('.').last.toLowerCase();
      String contentType = (extension == 'pdf') ? 'application/pdf' : 'image/jpeg';

      final ref = _storage.ref().child(rutaStorage);
      
      // Subida con metadatos para que se previsualice bien en la web/app
      await ref.putFile(archivo, SettableMetadata(contentType: contentType));
      
      return await ref.getDownloadURL();
    } catch (e) {
      throw Exception("Error en FirebaseStorage: $e");
    }
  }

  // --- 2. SOLICITUDES DE REVISIÓN (Trámites del Chofer) ---
  
  Future<void> registrarSolicitudRevision({
    required String dni,
    required String etiqueta,
    required String campo,
    required File archivo,
    required String fechaS,
    required String coleccionDestino,
  }) async {
    String extension = archivo.path.split('.').last.toLowerCase();
    String contentType = extension == 'pdf' ? 'application/pdf' : 'image/jpeg';

    final String nombreArchivo = 'REVISIONES/${dni}_${campo}_${DateTime.now().millisecondsSinceEpoch}.$extension';
    
    // Usamos el método genérico internamente o lo hacemos directo
    final ref = _storage.ref().child(nombreArchivo);
    await ref.putFile(archivo, SettableMetadata(contentType: contentType));
    String url = await ref.getDownloadURL();

    await _db.collection('REVISIONES').add({
      'DNI': dni.trim(),
      'CAMPO': campo,
      'COLECCION_DESTINO': coleccionDestino,
      'ETIQUETA': etiqueta,
      'NUEVA_FECHA': fechaS,
      'URL_ADJUNTO': url,
      'ESTADO': 'PENDIENTE',
      'FECHA_SOLICITUD': FieldValue.serverTimestamp(),
    });
  }

  // --- 3. GESTIÓN DE USUARIOS / EMPLEADOS ---

  /// Actualiza datos específicos de un empleado (como el MAIL)
  Future<void> actualizarDatoEmpleado(String dni, String campo, dynamic valor) async {
    try {
      await _db.collection('EMPLEADOS').doc(dni).update({
        campo: valor,
      });
    } catch (e) {
      throw Exception("Error al actualizar $campo: $e");
    }
  }

  // --- 4. CONSULTAS PARA EL ADMIN ---

  Stream<QuerySnapshot> getSolicitudesPendientes() {
    return _db
        .collection('REVISIONES')
        .where('ESTADO', isEqualTo: 'PENDIENTE')
        .orderBy('FECHA_SOLICITUD', descending: true)
        .snapshots();
  }

  Future<void> procesarSolicitud({
    required String solicitudId,
    required String nuevoEstado,
    String? dni,
    String? campo,
    String? nuevaFecha,
    String? coleccionDestino,
  }) async {
    WriteBatch batch = _db.batch();

    DocumentReference solicitudRef = _db.collection('REVISIONES').doc(solicitudId);
    batch.update(solicitudRef, {
      'ESTADO': nuevoEstado,
      'FECHA_PROCESADO': FieldValue.serverTimestamp(),
    });

    if (nuevoEstado == 'APROBADO' && dni != null && campo != null && nuevaFecha != null) {
      DocumentReference destinoRef = _db.collection(coleccionDestino!).doc(dni);
      batch.update(destinoRef, {campo: nuevaFecha});
    }

    await batch.commit();
  }
}
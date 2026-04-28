import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

/// Servicio genérico para subir archivos a Firebase Storage.
///
/// Detecta automáticamente el `Content-Type` según la extensión, así el
/// browser/visor sabe cómo abrir el archivo después.
///
/// Esto vive en `core/services/` porque lo usan varios features
/// (employees, revisions, vehicles).
class StorageService {
  final FirebaseStorage _storage;

  StorageService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  /// Sube un archivo a Firebase Storage en la ruta indicada y devuelve la URL.
  ///
  /// Throws [TimeoutException] si la subida tarda más de 30 segundos.
  Future<String> subirArchivo({
    required File archivo,
    required String rutaStorage,
  }) async {
    try {
      final extension = archivo.path.split('.').last.toLowerCase();
      final contentType = _obtenerContentType(extension);

      final ref = _storage.ref().child(rutaStorage);

      // Timeout de 30s — evita que la app se congele en redes lentas (4G).
      await ref
          .putFile(archivo, SettableMetadata(contentType: contentType))
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException(
              'La conexión es demasiado lenta para subir el archivo.');
        },
      );

      return await ref.getDownloadURL();
    } catch (e) {
      throw Exception('Error en FirebaseStorage: $e');
    }
  }

  /// Borra un archivo de Storage por su path.
  /// No tira si el archivo no existe — solo loggea silenciosamente.
  Future<void> borrarArchivo(String pathStorage) async {
    try {
      await _storage.ref().child(pathStorage).delete();
    } catch (_) {
      // El archivo no existía o no se pudo borrar; ignoramos.
    }
  }

  /// Devuelve el Content-Type apropiado según la extensión del archivo.
  static String _obtenerContentType(String extension) {
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      default:
        return 'image/jpeg';
    }
  }
}

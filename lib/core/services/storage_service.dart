import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Servicio genérico para subir archivos a Firebase Storage.
///
/// Detecta automáticamente el `Content-Type` según la extensión, así el
/// browser/visor sabe cómo abrir el archivo después.
///
/// Esto vive en `core/services/` porque lo usan varios features
/// (employees, revisions, vehicles).
///
/// **Cross-platform**: trabaja con `Uint8List` (bytes) en lugar de `File`.
/// Eso permite que la misma API corra en Android, iOS, Windows y Web —
/// donde `dart:io.File` no existe. Los callers obtienen los bytes así:
///
/// - Desde `image_picker`: `await xfile.readAsBytes()`
/// - Desde `file_picker`:  `pickFiles(withData: true)` → `result.files.single.bytes!`
/// - Desde `dart:io.File`: `await file.readAsBytes()` (mobile/desktop)
class StorageService {
  final FirebaseStorage _storage;

  StorageService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  /// Sube los [bytes] a Firebase Storage en [rutaStorage] y devuelve la URL.
  ///
  /// [nombreOriginal] se usa solo para inferir la extensión (y de ahí el
  /// content-type). Puede ser el nombre del file picker o cualquier string
  /// que termine con `.pdf`, `.png`, `.jpg`, etc.
  ///
  /// Throws [TimeoutException] si la subida tarda más de 30 segundos.
  Future<String> subirArchivo({
    required Uint8List bytes,
    required String nombreOriginal,
    required String rutaStorage,
  }) async {
    try {
      final extension = nombreOriginal.split('.').last.toLowerCase();
      final contentType = _obtenerContentType(extension);

      final ref = _storage.ref().child(rutaStorage);

      // Timeout de 30s — evita que la app se congele en redes lentas (4G).
      await ref
          .putData(bytes, SettableMetadata(contentType: contentType))
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

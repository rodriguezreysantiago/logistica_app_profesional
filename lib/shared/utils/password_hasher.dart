import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';

/// Hash de contraseñas con soporte dual: Bcrypt (nuevo) y SHA-256 (legacy).
///
/// **Estrategia de migración silenciosa:**
/// - Las contraseñas nuevas se hashean con Bcrypt (con salt automático).
/// - Las viejas siguen siendo SHA-256 hasta que el usuario logue exitosamente.
/// - Al login exitoso con SHA-256, el AuthService aprovecha y reescribe el
///   hash a Bcrypt en Firestore (sin que el usuario se entere).
/// - Eventualmente, todos los usuarios tendrán Bcrypt y el SHA-256 quedará
///   solo como fallback histórico.
///
/// **Detección del formato:**
/// - Bcrypt: empieza con `$2a$`, `$2b$` o `$2y$` (estándar)
/// - SHA-256: 64 caracteres hexadecimales
class PasswordHasher {
  PasswordHasher._();

  /// Hashea una contraseña usando Bcrypt con salt random (cost factor 10).
  /// Resultado: ~60 caracteres, comienza con `$2a$10$...`.
  static String hashBcrypt(String password) {
    return BCrypt.hashpw(
      password.trim(),
      BCrypt.gensalt(logRounds: 10),
    );
  }

  /// Verifica una contraseña en plano contra cualquier formato de hash
  /// (Bcrypt o SHA-256). Detecta automáticamente el formato.
  ///
  /// Devuelve `true` si la contraseña coincide.
  static bool verify(String password, String storedHash) {
    if (storedHash.isEmpty) return false;
    final clean = password.trim();

    if (_isBcrypt(storedHash)) {
      try {
        return BCrypt.checkpw(clean, storedHash);
      } catch (_) {
        return false;
      }
    }

    // Fallback legacy: SHA-256
    return _hashSha256(clean) == storedHash;
  }

  /// Indica si un hash almacenado todavía está en formato legacy (SHA-256)
  /// y por lo tanto el AuthService debería migrarlo a Bcrypt en el próximo
  /// login exitoso.
  static bool isLegacy(String storedHash) {
    return !_isBcrypt(storedHash);
  }

  // ===========================================================================
  // INTERNOS
  // ===========================================================================

  static bool _isBcrypt(String hash) {
    return hash.startsWith(r'$2a$') ||
        hash.startsWith(r'$2b$') ||
        hash.startsWith(r'$2y$');
  }

  static String _hashSha256(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }
}

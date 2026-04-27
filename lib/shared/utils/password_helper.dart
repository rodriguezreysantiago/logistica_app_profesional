import 'dart:convert';
import 'package:crypto/crypto.dart';

class PasswordHelper {
  // ✅ MEJORA PRO: Constructor privado para evitar que la clase sea instanciada en memoria.
  PasswordHelper._();

  /// Genera un hash SHA-256 de la contraseña.
  ///
  /// ⚠️ NOTA DE ARQUITECTURA:
  /// Se mantiene SHA-256 puro estrictamente por retrocompatibilidad con las
  /// credenciales ya almacenadas en la base de datos (Firestore).
  /// Para una futura V2 del sistema, se recomienda migrar a un algoritmo con "Salt" 
  /// (ej. Bcrypt) para mayor seguridad contra ataques de diccionario.
  static String hashPassword(String password) {
    final bytes = utf8.encode(password.trim());
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
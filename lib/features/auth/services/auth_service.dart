import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/services/prefs_service.dart';
import '../../../shared/utils/password_hasher.dart';

class LoginResult {
  final bool success;
  final String? message;
  final String? dni;
  final String? nombre;
  final String? rol;

  LoginResult({
    required this.success,
    this.message,
    this.dni,
    this.nombre,
    this.rol,
  });

  factory LoginResult.error(String message) {
    return LoginResult(success: false, message: message);
  }

  factory LoginResult.ok({
    required String dni,
    required String nombre,
    required String rol,
  }) {
    return LoginResult(success: true, dni: dni, nombre: nombre, rol: rol);
  }
}

/// Servicio de autenticación.
///
/// Soporta dos formatos de hash de contraseña:
/// - **Bcrypt** (nuevo, con salt) — usado para empleados nuevos y contraseñas
///   actualizadas.
/// - **SHA-256** (legacy) — formato antiguo, todavía válido para login pero
///   se migra automáticamente a Bcrypt en el primer login exitoso.
///
/// La migración es **silenciosa**: el usuario logue normalmente con su
/// contraseña de siempre y la próxima vez que login el hash ya estará en
/// formato moderno.
class AuthService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Login con DNI + contraseña.
  ///
  /// Si el usuario está en formato legacy (SHA-256) y la contraseña es
  /// correcta, dispara una migración silenciosa a Bcrypt en background.
  /// Si la migración falla, el login igualmente termina exitoso (no
  /// queremos romper UX por algo que no es bloqueante).
  Future<LoginResult> login({
    required String dni,
    required String password,
  }) async {
    try {
      final cleanDni = dni.replaceAll(RegExp(r'[^0-9]'), '');
      final cleanPass = password.trim();

      // Pre-validación rápida — no quemamos lecturas de Firebase si el form
      // está vacío.
      if (cleanDni.isEmpty || cleanPass.isEmpty) {
        return LoginResult.error('Complete todos los campos requeridos.');
      }

      final doc = await _db
          .collection('EMPLEADOS')
          .doc(cleanDni)
          .get()
          .timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw TimeoutException('Sin conexión.'),
      );

      if (!doc.exists) {
        return LoginResult.error(
          'El usuario no existe o el DNI es incorrecto.',
        );
      }

      final data = doc.data();
      if (data == null) {
        return LoginResult.error(
          'No se pudo obtener la información del usuario.',
        );
      }

      // Bloqueo de usuarios inactivos
      final bool isActive =
          data['ACTIVO'] is bool ? data['ACTIVO'] : true;
      if (!isActive) {
        return LoginResult.error(
          'Usuario inactivo. Contacte a administración.',
        );
      }

      final storedHash = data['CONTRASEÑA']?.toString() ?? '';

      // ✅ Verificación dual (Bcrypt nuevo / SHA-256 legacy)
      if (!PasswordHasher.verify(cleanPass, storedHash)) {
        return LoginResult.error('Contraseña incorrecta.');
      }

      // ✅ Migración silenciosa si todavía está en formato legacy
      if (PasswordHasher.isLegacy(storedHash)) {
        // Disparamos en background — si falla, el login ya fue exitoso.
        _migrarHashSilencioso(cleanDni, cleanPass);
      }

      final nombre = data['NOMBRE']?.toString() ?? 'Usuario';
      final rol = data['ROL']?.toString() ?? 'USUARIO';

      await PrefsService.guardarUsuario(
        dni: cleanDni,
        nombre: nombre,
        rol: rol,
      );

      return LoginResult.ok(dni: cleanDni, nombre: nombre, rol: rol);
    } on TimeoutException catch (_) {
      return LoginResult.error(
        'Tiempo de espera agotado. Verifique su señal de internet.',
      );
    } catch (e, stack) {
      debugPrint('🚨 AuthService.login error: $e');
      debugPrint(stack.toString());
      return LoginResult.error('Error interno al iniciar sesión.');
    }
  }

  Future<void> logout() async {
    await PrefsService.clear();
  }

  /// Genera un hash Bcrypt para guardar en Firestore.
  /// Lo usan las pantallas de creación de empleado y cambio de contraseña.
  String generarHash(String password) {
    return PasswordHasher.hashBcrypt(password);
  }

  // ===========================================================================
  // INTERNOS
  // ===========================================================================

  /// Reemplaza el hash SHA-256 actual del usuario por uno Bcrypt.
  /// Si falla, lo loggeamos pero NO interrumpimos el login.
  Future<void> _migrarHashSilencioso(String dni, String passwordPlana) async {
    try {
      final nuevoHash = PasswordHasher.hashBcrypt(passwordPlana);
      await _db.collection('EMPLEADOS').doc(dni).update({
        'CONTRASEÑA': nuevoHash,
        'hash_migrado_a_bcrypt': FieldValue.serverTimestamp(),
      });
      debugPrint('🔐 Hash migrado a Bcrypt para DNI: $dni');
    } catch (e) {
      debugPrint('⚠️ No se pudo migrar hash a Bcrypt para $dni: $e');
    }
  }
}

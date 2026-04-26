import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

import 'prefs_service.dart';

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
    return LoginResult(
      success: false,
      message: message,
    );
  }

  factory LoginResult.ok({
    required String dni,
    required String nombre,
    required String rol,
  }) {
    return LoginResult(
      success: true,
      dni: dni,
      nombre: nombre,
      rol: rol,
    );
  }
}

class AuthService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _hashPassword(String password) {
    final bytes = utf8.encode(password.trim());
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<LoginResult> login({
    required String dni,
    required String password,
  }) async {
    try {
      final cleanDni = dni.replaceAll(RegExp(r'[^0-9]'), '');
      final hashedPassword = _hashPassword(password);

      final doc = await _db.collection('EMPLEADOS').doc(cleanDni).get();

      if (!doc.exists) {
        return LoginResult.error('El usuario no existe');
      }

      final data = doc.data();
      if (data == null) {
        return LoginResult.error('No se pudo obtener la información del usuario');
      }

      final storedPassword = data['CONTRASEÑA']?.toString() ?? '';

      if (storedPassword != hashedPassword) {
        return LoginResult.error('Contraseña incorrecta');
      }

      final nombre = data['NOMBRE']?.toString() ?? 'Usuario';
      final rol = data['ROL']?.toString() ?? 'USUARIO';

      await PrefsService.guardarUsuario(
        dni: cleanDni,
        nombre: nombre,
        rol: rol,
      );

      return LoginResult.ok(
        dni: cleanDni,
        nombre: nombre,
        rol: rol,
      );
    } catch (e, stack) {
      debugPrint('AuthService.login error: $e');
      debugPrint(stack.toString());

      return LoginResult.error('Error interno al iniciar sesión');
    }
  }

  Future<void> logout() async {
    await PrefsService.clear();
  }

  String generarHash(String password) {
    return _hashPassword(password);
  }
}
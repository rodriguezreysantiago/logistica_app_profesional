import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

class MigrationService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  static Future<void> migrarTodasLasPasswords() async {
    try {
      final empleados = await _db.collection('EMPLEADOS').get();

      final nuevaPasswordHash = _hashPassword('1234');

      for (final doc in empleados.docs) {
        await doc.reference.update({
          'CONTRASEÑA': nuevaPasswordHash,
        });

        debugPrint('✅ ${doc.id} actualizado');
      }

      debugPrint('🔥 Migración finalizada correctamente');
    } catch (e) {
      debugPrint('🚨 Error en migración: $e');
    }
  }
}
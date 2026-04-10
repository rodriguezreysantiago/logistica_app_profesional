import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MigrationService {
  /// Ejecuta la migración masiva y limpieza de campos en EMPLEADOS.
  static Future<void> ejecutarMigracionEmpleados() async {
    final collection = FirebaseFirestore.instance.collection('EMPLEADOS');
    
    try {
      debugPrint("🚀 Iniciando limpieza y migración en EMPLEADOS...");
      final snapshot = await collection.get();

      if (snapshot.docs.isEmpty) {
        debugPrint("⚠️ No hay documentos para procesar.");
        return;
      }

      WriteBatch batch = FirebaseFirestore.instance.batch();
      int contadorCambios = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        Map<String, dynamic> updates = {};

        // 1. ELIMINAR NRO_TRAMITE_DNI (Directamente)
        // Agregué ambas variantes por si acaso se llamó distinto en algún doc
        if (data.containsKey('NRO_TRAMITE_DNI')) {
          updates['NRO_TRAMITE_DNI'] = FieldValue.delete();
        }
        if (data.containsKey('N_TRAMITE_DNI')) {
          updates['N_TRAMITE_DNI'] = FieldValue.delete();
        }

        // 2. Renombrar FOTO_PERFIL a ARCHIVO_PERFIL
        if (data.containsKey('CLAVE')) {
          updates['CONTRASEÑA'] = data['CLAVE'];
          updates['CLAVE'] = FieldValue.delete();
        }

        // 3. Renombrar TRACTOR -> VEHICULO
        if (data.containsKey('TRACTOR')) {
          updates['VEHICULO'] = data['TRACTOR'];
          updates['TRACTOR'] = FieldValue.delete();
        }

        // 4. Renombrar BATEA_TOLVA -> ENGANCHE
        if (data.containsKey('BATEA_TOLVA')) {
          updates['ENGANCHE'] = data['BATEA_TOLVA'];
          updates['BATEA_TOLVA'] = FieldValue.delete();
        }

        if (updates.isNotEmpty) {
          batch.update(doc.reference, updates);
          contadorCambios++;
        }

        // Límite de batch
        if (contadorCambios >= 450) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          contadorCambios = 0;
        }
      }

      await batch.commit();
      debugPrint("✅ PROCESO COMPLETADO: Campos viejos eliminados y base de datos limpia.");
      
    } catch (e) {
      debugPrint("❌ ERROR EN MIGRACIÓN: $e");
    }
  }
}
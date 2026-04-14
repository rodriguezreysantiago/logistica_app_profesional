import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MigrationService {
  /// Ejecuta la migración masiva y limpieza de campos en VEHICULOS.
  /// Incluye la eliminación de RTO_NRO y POLIZA_NRO.
  static Future<void> ejecutarMigracionEmpleados() async {
    final collection = FirebaseFirestore.instance.collection('VEHICULOS');
    
    try {
      debugPrint("🚀 Iniciando limpieza profunda en VEHICULOS...");
      final snapshot = await collection.get();

      if (snapshot.docs.isEmpty) {
        debugPrint("⚠️ No hay documentos en VEHICULOS.");
        return;
      }

      WriteBatch batch = FirebaseFirestore.instance.batch();
      int contadorDocsEditados = 0;
      int operacionesEnBatch = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        Map<String, dynamic> updates = {};

        // 1. MIGRAR PÓLIZA -> SEGURO (Fecha y Archivo)
        if (data.containsKey('VENCIMIENTO_POLIZA')) {
          updates['VENCIMIENTO_SEGURO'] = data['VENCIMIENTO_POLIZA'];
          updates['VENCIMIENTO_POLIZA'] = FieldValue.delete();
        }
        if (data.containsKey('ARCHIVO_POLIZA')) {
          updates['ARCHIVO_SEGURO'] = data['ARCHIVO_POLIZA'];
          updates['ARCHIVO_POLIZA'] = FieldValue.delete();
        }

        // 2. ELIMINAR CAMPOS OBSOLETOS SOLICITADOS
        if (data.containsKey('FOTO')) {
          updates['FOTO'] = FieldValue.delete();
        }
        if (data.containsKey('FOTO_VENCIMIENTO_RTO')) {
          updates['FOTO_VENCIMIENTO_RTO'] = FieldValue.delete();
        }

        // --- NUEVAS ELIMINACIONES: RTO_NRO y POLIZA_NRO ---
        if (data.containsKey('RTO_NRO')) {
          updates['RTO_NRO'] = FieldValue.delete();
        }
        if (data.containsKey('POLIZA_NRO')) {
          updates['POLIZA_NRO'] = FieldValue.delete();
        }

        // 3. LIMPIEZA ADICIONAL DE TRÁMITES
        if (data.containsKey('NRO_TRAMITE_DNI')) updates['NRO_TRAMITE_DNI'] = FieldValue.delete();
        if (data.containsKey('N_TRAMITE_DNI')) updates['N_TRAMITE_DNI'] = FieldValue.delete();
        if (data.containsKey('FOTO_VENCIMIENTO_POLIZA')) updates['FOTO_VENCIMIENTO_POLIZA'] = FieldValue.delete();
        if (data.containsKey('ultima_revision_admin')) updates['ultima_revision_admin'] = FieldValue.delete();
        if (data.containsKey('ultima_revision')) updates['ultima_revision'] = FieldValue.delete(); 

        if (updates.isNotEmpty) {
          batch.update(doc.reference, updates);
          operacionesEnBatch++;
          contadorDocsEditados++;
        }

        // Límite de Batch (500 operaciones máximo de Firestore)
        if (operacionesEnBatch >= 450) {
          await batch.commit();
          debugPrint("📦 Bloque de 450 documentos procesado...");
          batch = FirebaseFirestore.instance.batch();
          operacionesEnBatch = 0;
        }
      }

      // Commit final de los documentos restantesx|
      if (operacionesEnBatch > 0) {
        await batch.commit();
      }

      debugPrint("✅ LIMPIEZA COMPLETADA.");
      debugPrint("📊 Se actualizaron/limpiaron $contadorDocsEditados documentos en VEHICULOS.");
      
    } catch (e) {
      debugPrint("❌ ERROR EN MIGRACIÓN: $e");
    }
  }
}
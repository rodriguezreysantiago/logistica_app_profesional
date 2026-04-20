import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MigrationService {
  /// MIGRACIÓN Y LIMPIEZA DE EMPLEADOS
  /// 1. Inicializa los 4 nuevos campos laborales (ART, 931, Seguro de Vida, Sindicato).
  /// 2. Elimina campos obsoletos de fotos y URLs viejas.
  static Future<void> ejecutarMigracionCamposEmpleados() async {
    final collection = FirebaseFirestore.instance.collection('EMPLEADOS');
    
    try {
      debugPrint("🚀 Iniciando limpieza e inicialización en EMPLEADOS...");
      final snapshot = await collection.get();

      if (snapshot.docs.isEmpty) {
        debugPrint("⚠️ No hay documentos en EMPLEADOS.");
        return;
      }

      WriteBatch batch = FirebaseFirestore.instance.batch();
      int contadorDocsEditados = 0;
      int operacionesEnBatch = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        Map<String, dynamic> updates = {};

        // --- A. INICIALIZACIÓN DE CAMPOS NUEVOS (Si no existen) ---
        // Esto asegura que el admin y el usuario vean strings vacíos en lugar de nulls
        final nuevosCampos = [
          'VENCIMIENTO_ART', 'ARCHIVO_ART',
          'VENCIMIENTO_931', 'ARCHIVO_931',
          'VENCIMIENTO_SEGURO_DE_VIDA', 'ARCHIVO_SEGURO_DE_VIDA',
          'VENCIMIENTO_LIBRE_DE_DEUDA_SINDICAL', 'ARCHIVO_LIBRE_DE_DEUDA_SINDICAL'
        ];

        for (var campo in nuevosCampos) {
          if (!data.containsKey(campo)) {
            updates[campo] = ""; 
          }
        }

        // --- B. ELIMINACIÓN DE CAMPOS OBSOLETOS ---
        // Borramos físicamente los campos que ya no se usan en la nueva versión
        final camposAEliminar = [
          'ULTIMA_MODIFICACION', 
          'FOTO_CURSO_MANEJO', 
          'FOTO_EPAP', 
          'FOTO_LIC_COND', 
          'FOTO_URL'
        ];

        for (var campo in camposAEliminar) {
          if (data.containsKey(campo)) {
            updates[campo] = FieldValue.delete();
          }
        }

        // Si el documento necesitaba cambios, lo agregamos al batch
        if (updates.isNotEmpty) {
          batch.update(doc.reference, updates);
          operacionesEnBatch++;
          contadorDocsEditados++;
        }

        // Límite de Batch de Firestore (máximo 500 operaciones por commit)
        if (operacionesEnBatch >= 450) {
          await batch.commit();
          debugPrint("📦 Bloque de 450 empleados procesado...");
          batch = FirebaseFirestore.instance.batch();
          operacionesEnBatch = 0;
        }
      }

      // Procesar los documentos restantes
      if (operacionesEnBatch > 0) {
        await batch.commit();
      }

      debugPrint("✅ PROCESO COMPLETADO EXITOSAMENTE.");
      debugPrint("📊 Se actualizaron/limpiaron $contadorDocsEditados documentos de empleados.");
      
    } catch (e) {
      debugPrint("❌ ERROR DURANTE LA OPERACIÓN: $e");
    }
  }
}
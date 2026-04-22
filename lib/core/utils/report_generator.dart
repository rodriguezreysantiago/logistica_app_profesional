import 'dart:io';
import 'package:flutter/foundation.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ReportGenerator {
  static Future<void> generarYCompartirReporte(List<dynamic> cacheVolvo) async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('VEHICULOS').get();
      
      // Encabezados
      String csvData = "PATENTE,MARCA,MODELO,VIN,KM_ACTUAL,ESTADO,SINCRO_TIPO,ULTIMA_SINCRO\n";

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final patente = doc.id;
        final vin = (data['VIN'] ?? "").toString().trim().toUpperCase();
        
        bool esAutomatico = cacheVolvo.any((v) => 
            v['vin'].toString().toUpperCase() == vin && vin.isNotEmpty);

        final String fechaSincro = data['ULTIMA_SINCRO'] != null 
            ? (data['ULTIMA_SINCRO'] as Timestamp).toDate().toString().split('.')[0] 
            : "NUNCA";

        final List<String> fila = [
          patente,
          "${data['MARCA'] ?? "S/M"}",
          "${data['MODELO'] ?? "S/M"}",
          vin,
          "${data['KM_ACTUAL'] ?? "0"}",
          "${data['ESTADO'] ?? "S/E"}",
          esAutomatico ? "AUTOMATICO" : "MANUAL",
          fechaSincro,
        ];

        csvData = "$csvData${fila.join(",")}\n";
      }

      // 📂 CAMBIO CLAVE: Usamos getExternalStorageDirectory para que sea accesible
      // Si estamos en Android, esto busca una carpeta que el sistema permite compartir mejor
      Directory? directory;
      if (Platform.isAndroid) {
        directory = await getExternalStorageDirectory();
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
      
      final String fechaHoy = DateTime.now().toString().split(' ')[0].replaceAll("-", "_");
      final String filePath = '${directory!.path}/Reporte_Flota_$fechaHoy.csv';
      
      final file = File(filePath);
      await file.writeAsString(csvData);

      // ✅ Usamos shareXFiles pero con SUBJECT y NAME para forzar la descarga
      await Share.shareXFiles(
        [XFile(file.path, name: 'Reporte_FleteMB_$fechaHoy.csv', mimeType: 'text/csv')],
        subject: 'Reporte de Flota Flete MB',
      );

      debugPrint("✅ Reporte listo para descarga: $filePath");

    } catch (e) {
      debugPrint("🚨 Error en ReportGenerator: $e");
    }
  }
}
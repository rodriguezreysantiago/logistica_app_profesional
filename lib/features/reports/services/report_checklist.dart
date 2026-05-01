import 'dart:io';
import 'dart:async';
import 'package:excel/excel.dart' as ex;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_constants.dart'; // ✅ Para AppCollections
import '../../../shared/utils/app_feedback.dart';

class ReportChecklistService {

  ReportChecklistService._(); // Constructor privado

  static Future<void> mostrarOpcionesYGenerar(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    // Web no soporta dart:io.File ni Process.run. Cortamos limpio aquí
    // para evitar crash al guardar el .xlsx en disco.
    if (kIsWeb) {
      AppFeedback.warningOn(messenger, 'Los reportes Excel solo están disponibles en Windows y Android.');
      return;
    }
    
    // Definición de columnas disponibles
    final Map<String, bool> opciones = {
      "FECHA": true,
      "DOMINIO": true,
      "TIPO": true,
      "CHOFER": true,
      "ITEM": true,
      "ESTADO": true,
      "OBSERVACIÓN": true,
    };

    bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withAlpha(20))
          ),
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Reporte de Novedades", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              Text("Se exportarán solo estados REG y MAL", style: TextStyle(color: Colors.orangeAccent, fontSize: 11)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: opciones.keys.map((key) {
                return CheckboxListTile(
                  dense: true,
                  title: Text(key, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  value: opciones[key],
                  activeColor: Colors.greenAccent,
                  onChanged: (val) => setState(() => opciones[key] = val ?? false),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false), 
              child: const Text("CANCELAR", style: TextStyle(color: Colors.white54))
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("GENERAR EXCEL"),
            ),
          ],
        ),
      ),
    );

    if (confirmar == true && context.mounted) {
      _showLoadingSnackBar(messenger);
      await _ejecutarGeneracion(opciones, messenger);
    }
  }

  static void _showLoadingSnackBar(ScaffoldMessengerState messenger) {
    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            SizedBox(width: 15),
            Text("Procesando datos de mantenimiento..."),
          ],
        ),
        backgroundColor: Colors.blueGrey,
      )
    );
  }

  static Future<void> _ejecutarGeneracion(Map<String, bool> filtros, ScaffoldMessengerState messenger) async {
    try {
      // ✅ MEJORA PRO: Filtro por fecha (Freno de mano de costos)
      // Solo traemos los checklists de los últimos 45 días para evitar descargar miles de docs inútiles
      final DateTime limiteCarga = DateTime.now().subtract(const Duration(days: 45));

      final snapshot = await FirebaseFirestore.instance
          .collection(AppCollections.checklists)
          .where('FECHA', isGreaterThan: Timestamp.fromDate(limiteCarga))
          .orderBy('FECHA', descending: true)
          .get();

      var excel = ex.Excel.createExcel(); 
      String sheetName = "NOVEDADES_MANTENIMIENTO";
      excel.rename('Sheet1', sheetName);
      ex.Sheet sheetObject = excel[sheetName];

      // Estilos
      var headerStyle = ex.CellStyle(
        bold: true, 
        backgroundColorHex: ex.ExcelColor.fromHexString("#1A3A5A"),
        fontColorHex: ex.ExcelColor.fromHexString("#FFFFFF"),
        horizontalAlign: ex.HorizontalAlign.Center,
      );

      // 1. Crear Encabezados dinámicos
      List<String> columnasActivas = [];
      filtros.forEach((key, val) { if (val) columnasActivas.add(key); });

      for (var i = 0; i < columnasActivas.length; i++) {
        var cell = sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = ex.TextCellValue(columnasActivas[i]);
        cell.cellStyle = headerStyle;
      }

      // 2. Cargar Datos
      int currentRow = 1;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final Map respuestas = data['RESPUESTAS'] ?? {};
        final Map observaciones = data['OBSERVACIONES'] ?? {};
        
        String fechaStr = "-";
        if (data['FECHA'] != null) {
          fechaStr = DateFormat('dd/MM/yyyy').format((data['FECHA'] as Timestamp).toDate());
        }

        respuestas.forEach((item, estado) {
          // Solo exportamos lo que requiere atención
          if (estado == "REG" || estado == "MAL") {
            for (var i = 0; i < columnasActivas.length; i++) {
              var cell = sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: currentRow));
              
              // Mapeo dinámico de datos según la columna activa
              cell.value = ex.TextCellValue(_obtenerValorCelda(columnasActivas[i], data, item, estado, observaciones, fechaStr));
            }
            currentRow++; 
          }
        });
      }

      // ✅ MEJORA PRO: UX de Excel (Auto-filtros y columnas anchas)
      for (var i = 0; i < columnasActivas.length; i++) {
        sheetObject.setColumnWidth(i, 25.0); 
      }

      // 3. Guardado y apertura nativa
      final String fileName = "Novedades_${DateFormat('yyyy_MM_dd').format(DateTime.now())}.xlsx";
      final directory = await getTemporaryDirectory(); // Mejor usar temp para reportes volátiles
      final path = "${directory.path}/$fileName";

      final fileBytes = excel.save();
      if (fileBytes != null) {
        File(path).writeAsBytesSync(fileBytes);

        // Mismo patrón que report_flota: en Windows abrimos el archivo
        // directamente con la app por defecto (Excel). En mobile no hay
        // "abrir con", así que caemos al sheet de compartir nativo.
        if (Platform.isWindows) {
          await Process.run('cmd', ['/c', 'start', '', path]);
        } else {
          await Share.shareXFiles(
            [XFile(path)],
            text: '📋 Reporte de Novedades - Flete MB\n'
                'Generado el ${DateFormat('dd/MM HH:mm').format(DateTime.now())}',
          );
        }
      }
    } catch (e) {
      debugPrint("❌ Error Excel: $e");
      AppFeedback.errorOn(messenger, "Error al generar reporte: $e");
    }
  }

  // Helper para mapear los datos a las celdas
  static String _obtenerValorCelda(String columna, Map data, String item, dynamic estado, Map obs, String fecha) {
    switch (columna) {
      case "FECHA": return fecha;
      case "DOMINIO": return data['DOMINIO'] ?? "";
      case "TIPO": return data['TIPO'] ?? "";
      case "CHOFER": return data['NOMBRE'] ?? "";
      case "ITEM": return item;
      case "ESTADO": return estado.toString();
      case "OBSERVACIÓN": return obs[item] ?? "";
      default: return "";
    }
  }
}
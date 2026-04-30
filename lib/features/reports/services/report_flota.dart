import 'dart:io';
import 'package:excel/excel.dart' as ex;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import '../../../shared/utils/app_feedback.dart';
import '../../../shared/utils/formatters.dart';
import '../../../core/constants/app_constants.dart';

class ReportGenerator {
  ReportGenerator._();

  static Future<void> mostrarOpcionesYGenerar(BuildContext context, List<dynamic> cacheVolvo) async {
    final messenger = ScaffoldMessenger.of(context);

    // Web no soporta dart:io.File ni Process.run; los reportes Excel
    // generan archivo en filesystem y lo abren con Excel/Share.
    // Degradación elegante: avisamos y salimos sin tocar Firestore.
    if (kIsWeb) {
      AppFeedback.warningOn(messenger, 'Los reportes Excel solo están disponibles en Windows y Android.');
      return;
    }
    
    final Map<String, bool> opciones = {
      "TIPO": true,
      "MARCA": true,
      "MODELO": true,
      "EMPRESA": true,
      "VIN": true,
      "KM ACTUAL": true,
      "CONSUMO (L)": true,
      "PROMEDIO KM/L": true,
      "VENCIMIENTO RTO": true,
      "VENCIMIENTO SEGURO": true,
      "VENCIMIENTO EXT. CABINA": true,
      "VENCIMIENTO EXT. EXTERIOR": true,
      "ESTADO CONEXION": true,
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
          title: const Text("Configurar Reporte de Flota", 
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
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
      _notificarProgreso(messenger);
      await _ejecutarGeneracion(opciones, cacheVolvo, messenger);
    }
  }

  static void _notificarProgreso(ScaffoldMessengerState messenger) {
    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            SizedBox(width: 15),
            Text("Cruzando datos de flota y telemetría..."),
          ],
        ),
        backgroundColor: Colors.blueGrey,
      )
    );
  }

  static Future<void> _ejecutarGeneracion(
    Map<String, bool> filtros, 
    List<dynamic> cacheVolvo, 
    ScaffoldMessengerState messenger
  ) async {
    try {
      // 1. Convertir caché de Volvo a Map para búsqueda instantánea O(1)
      final Map<String, dynamic> volvoMap = {
        for (var v in cacheVolvo) v['vin']?.toString().toUpperCase() ?? '' : v
      };

      final snapshot = await FirebaseFirestore.instance.collection(AppCollections.vehiculos).get();
      
      var excel = ex.Excel.createExcel(); 
      String sheetName = "ESTADO_DE_FLOTA";
      excel.rename('Sheet1', sheetName);
      ex.Sheet sheetObject = excel[sheetName];

      // Estilos Pro
      var headerStyle = ex.CellStyle(
        bold: true, 
        backgroundColorHex: ex.ExcelColor.fromHexString("#1A3A5A"),
        fontColorHex: ex.ExcelColor.fromHexString("#FFFFFF"),
        horizontalAlign: ex.HorizontalAlign.Center,
      );
      var numStyle = ex.CellStyle(numberFormat: ex.NumFormat.standard_4); 

      // 2. Preparar Cabecera
      List<String> titulos = ["PATENTE"];
      filtros.forEach((key, val) { if (val) titulos.add(key); });

      for (var i = 0; i < titulos.length; i++) {
        var cell = sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = ex.TextCellValue(titulos[i]);
        cell.cellStyle = headerStyle;
      }

      // 3. Procesar Filas
      int currentRow = 1;
      for (var doc in snapshot.docs) {
        final Map<String, dynamic> data = doc.data();
        final String patente = doc.id;
        final String vin = (data['VIN'] ?? '').toString().trim().toUpperCase();
        
        // Búsqueda instantánea en el Map
        final volvoData = volvoMap[vin];

        int currentCol = 0;
        
        // Columna fija: Patente
        sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: currentCol++, rowIndex: currentRow)).value = ex.TextCellValue(patente);

        // Columnas dinámicas
        if (filtros["TIPO"]!) {
          sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: currentCol++, rowIndex: currentRow)).value = ex.TextCellValue(data['TIPO'] ?? '');
        }
        if (filtros["MARCA"]!) {
          sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: currentCol++, rowIndex: currentRow)).value = ex.TextCellValue(data['MARCA'] ?? '');
        }
        if (filtros["MODELO"]!) {
          sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: currentCol++, rowIndex: currentRow)).value = ex.TextCellValue(data['MODELO'] ?? '');
        }
        if (filtros["EMPRESA"]!) {
          sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: currentCol++, rowIndex: currentRow)).value = ex.TextCellValue(data['EMPRESA'] ?? '');
        }
        if (filtros["VIN"]!) {
          sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: currentCol++, rowIndex: currentRow)).value = ex.TextCellValue(vin.isEmpty ? "-" : vin);
        }
        if (filtros["KM ACTUAL"]!) {
          double km = (data['KM_ACTUAL'] ?? 0.0).toDouble();
          var cell = sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: currentCol++, rowIndex: currentRow));
          cell.value = ex.DoubleCellValue(km);
          cell.cellStyle = numStyle;
        }

        // Datos de Telemetría Volvo
        double litros = 0.0;
        if (volvoData != null && volvoData['accumulatedData'] != null) {
          litros = (volvoData['accumulatedData']['totalFuelConsumption'] ?? 0.0).toDouble();
        }

        if (filtros["CONSUMO (L)"]!) {
          var cell = sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: currentCol++, rowIndex: currentRow));
          cell.value = ex.DoubleCellValue(litros);
          cell.cellStyle = numStyle;
        }
        
        if (filtros["PROMEDIO KM/L"]!) {
          double km = (data['KM_ACTUAL'] ?? 0.0).toDouble();
          double promedio = (litros > 0) ? (km / litros) : 0.0;
          var cell = sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: currentCol++, rowIndex: currentRow));
          cell.value = ex.DoubleCellValue(double.parse(promedio.toStringAsFixed(2)));
          cell.cellStyle = numStyle;
        }

        if (filtros["VENCIMIENTO RTO"]!) {
          sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: currentCol++, rowIndex: currentRow)).value =
              ex.TextCellValue(AppFormatters.formatearFecha(data['VENCIMIENTO_RTO']));
        }
        if (filtros["VENCIMIENTO SEGURO"]!) {
          sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: currentCol++, rowIndex: currentRow)).value =
              ex.TextCellValue(AppFormatters.formatearFecha(data['VENCIMIENTO_SEGURO']));
        }
        if (filtros["VENCIMIENTO EXT. CABINA"]!) {
          sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: currentCol++, rowIndex: currentRow)).value =
              ex.TextCellValue(AppFormatters.formatearFecha(data['VENCIMIENTO_EXTINTOR_CABINA']));
        }
        if (filtros["VENCIMIENTO EXT. EXTERIOR"]!) {
          sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: currentCol++, rowIndex: currentRow)).value =
              ex.TextCellValue(AppFormatters.formatearFecha(data['VENCIMIENTO_EXTINTOR_EXTERIOR']));
        }
        
        if (filtros["ESTADO CONEXION"]!) {
          sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: currentCol++, rowIndex: currentRow)).value = 
              ex.TextCellValue(volvoData != null ? "CONECTADO" : "OFFLINE");
        }

        currentRow++;
      }

      // 4. Formato de Hoja (Ancho de columnas y congelado)
      for (var i = 0; i < titulos.length; i++) {
        sheetObject.setColumnWidth(i, 22.0); 
      }

      // 5. Guardado y Compartir NATIVO
      final String fileName = "Flota_SmartLogistica_${DateTime.now().millisecondsSinceEpoch}.xlsx";
      final directory = await getTemporaryDirectory();
      final path = "${directory.path}/$fileName";
      
      final fileBytes = excel.save();
      if (fileBytes != null) {
        File(path).writeAsBytesSync(fileBytes);
        
        if (Platform.isWindows) {
          await Process.run('cmd', ['/c', 'start', '', path]);
        } else {
          await Share.shareXFiles(
            [XFile(path)], 
            text: '📊 Reporte de Flota y Telemetría Volvo - Flete MB'
          );
        }
      }
    } catch (e) {
      debugPrint("❌ Error Reporte Flota: $e");
      messenger.showSnackBar(
        SnackBar(content: Text("Error al generar el reporte: $e"), backgroundColor: Colors.redAccent)
      );
    }
  }
}
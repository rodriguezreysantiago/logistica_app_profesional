import 'dart:io';
import 'package:excel/excel.dart' as ex; // ✅ Prefijo para evitar conflictos con Flutter
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ReportGenerator {
  static Future<void> mostrarOpcionesYGenerar(BuildContext context, List<dynamic> cacheVolvo) async {
    // ✅ MENTOR: Capturamos el messenger ANTES del await para seguridad asíncrona
    final messenger = ScaffoldMessenger.of(context);
    
    Map<String, bool> opciones = {
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
      "ESTADO CONEXION": true,
    };

    bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface, // ✅ MENTOR: Tema global
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withAlpha(20))
          ),
          title: const Text("Configurar Reporte", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxHeight: 400),
            child: Scrollbar(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: opciones.keys.map((key) {
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(key, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                      value: opciones[key],
                      activeColor: Colors.greenAccent,
                      checkColor: Colors.black,
                      side: const BorderSide(color: Colors.white54),
                      onChanged: (val) => setState(() => opciones[key] = val ?? false),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(15, 0, 15, 15),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false), 
              child: const Text("CANCELAR", style: TextStyle(color: Colors.white54))
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, 
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
              ),
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text("GENERAR EXCEL", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (confirmar == true) {
      messenger.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
              SizedBox(width: 15),
              Text("Procesando datos y generando Excel..."),
            ],
          ),
          backgroundColor: Colors.orangeAccent,
          duration: Duration(seconds: 2),
        )
      );
      // ✅ MENTOR: Le pasamos el messenger para que pueda avisar cuando termine
      await _ejecutarGeneracion(opciones, cacheVolvo, messenger);
    }
  }

  static Future<void> _ejecutarGeneracion(Map<String, bool> filtros, List<dynamic> cacheVolvo, ScaffoldMessengerState messenger) async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('VEHICULOS').get();
      var excel = ex.Excel.createExcel(); 
      String sheetName = "REPORTE_FLOTA";
      excel.rename('Sheet1', sheetName);
      ex.Sheet sheetObject = excel[sheetName];

      var borderThin = ex.Border(borderStyle: ex.BorderStyle.Thin);
      var borderMedium = ex.Border(borderStyle: ex.BorderStyle.Medium);

      var headerStyle = ex.CellStyle(
        bold: true, 
        backgroundColorHex: ex.ExcelColor.fromHexString("#1A3A5A"), // Azul corporativo para la cabecera del Excel
        fontColorHex: ex.ExcelColor.fromHexString("#FFFFFF"),
        horizontalAlign: ex.HorizontalAlign.Center,
        bottomBorder: borderMedium,
        topBorder: borderThin,
        leftBorder: borderThin,
        rightBorder: borderThin,
      );

      var numStyle = ex.CellStyle(numberFormat: ex.NumFormat.standard_4); 
      
      String formatearFecha(dynamic fecha) {
        if (fecha == null || fecha.toString().isEmpty || fecha == '-') return '-';
        try {
          DateTime dt = DateTime.parse(fecha.toString());
          return DateFormat('dd/MM/yyyy').format(dt);
        } catch (e) {
          return fecha.toString();
        }
      }

      List<String> titulos = ["PATENTE"];
      filtros.forEach((key, val) { if (val) titulos.add(key); });

      // Escribir Cabecera
      for (var i = 0; i < titulos.length; i++) {
        var cell = sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = ex.TextCellValue(titulos[i]);
        cell.cellStyle = headerStyle;
      }

      int row = 1;
      for (var doc in snapshot.docs) {
        final Map<String, dynamic> data = doc.data();
        final String patente = doc.id;
        final String vin = (data['VIN'] ?? '').toString().trim().toUpperCase();
        
        final volvoData = cacheVolvo.firstWhere(
          (v) => v['vin']?.toString().toUpperCase() == vin && vin.isNotEmpty,
          orElse: () => null,
        );

        int col = 0;
        String limpiar(dynamic val) => val?.toString().replaceAll(',', '').replaceAll(':', '') ?? '';

        // Patente
        sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = ex.TextCellValue(patente);

        if (filtros["TIPO"]!) { sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = ex.TextCellValue(limpiar(data['TIPO'])); }
        if (filtros["MARCA"]!) { sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = ex.TextCellValue(limpiar(data['MARCA'])); }
        if (filtros["MODELO"]!) { sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = ex.TextCellValue(limpiar(data['MODELO'])); }
        if (filtros["EMPRESA"]!) { sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = ex.TextCellValue(limpiar(data['EMPRESA'])); }
        if (filtros["VIN"]!) { sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = ex.TextCellValue(vin.isEmpty ? "-" : vin); }

        if (filtros["KM ACTUAL"]!) {
          double kmValue = (data['KM_ACTUAL'] is num) ? (data['KM_ACTUAL']).toDouble() : 0.0;
          var cell = sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row));
          cell.value = ex.DoubleCellValue(kmValue);
          cell.cellStyle = numStyle;
        }

        double litros = 0.0;
        if (volvoData != null && volvoData['accumulatedData'] != null) {
          litros = (volvoData['accumulatedData']['totalFuelConsumption'] ?? 0.0).toDouble();
        }

        if (filtros["CONSUMO (L)"]!) {
          var cell = sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row));
          cell.value = ex.DoubleCellValue(litros);
          cell.cellStyle = numStyle;
        }
        
        if (filtros["PROMEDIO KM/L"]!) {
          double kmValue = (data['KM_ACTUAL'] is num) ? (data['KM_ACTUAL']).toDouble() : 0.0;
          double promedio = (litros > 0) ? (kmValue / litros) : 0.0;
          var cell = sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row));
          cell.value = ex.DoubleCellValue(double.parse(promedio.toStringAsFixed(2)));
          cell.cellStyle = numStyle;
        }

        if (filtros["VENCIMIENTO RTO"]!) {
          sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = ex.TextCellValue(formatearFecha(data['VENCIMIENTO_RTO']));
        }
        if (filtros["VENCIMIENTO SEGURO"]!) {
          sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = ex.TextCellValue(formatearFecha(data['VENCIMIENTO_SEGURO']));
        }
        
        if (filtros["ESTADO CONEXION"]!) {
          sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = ex.TextCellValue(volvoData != null ? "CONECTADO" : "OFFLINE");
        }

        row++;
      }

      for (var i = 0; i < titulos.length; i++) {
        sheetObject.setColumnWidth(i, 22.0); 
      }

      final now = DateTime.now();
      final String timestamp = "${now.day}_${now.month}_${now.hour}${now.minute}";
      final directory = await getApplicationDocumentsDirectory();
      final path = "${directory.path}/Reporte_Flota_$timestamp.xlsx";
      
      final fileBytes = excel.save();
      if (fileBytes != null) {
        File(path)
          ..createSync(recursive: true)
          ..writeAsBytesSync(fileBytes);
        
        if (Platform.isWindows) {
          await Process.run('cmd', ['/c', 'start', '', path]);
        } else {
          // ✅ MENTOR: Feedback vital para móviles
          messenger.showSnackBar(
            SnackBar(
              content: Text("✅ Excel generado con éxito en:\n$path", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5), // Más tiempo para que el usuario pueda leer la ruta
              action: SnackBarAction(
                label: 'OK',
                textColor: Colors.white,
                onPressed: () {},
              ),
            )
          );
        }
      }
    } catch (e) {
      debugPrint("❌ Error Reporte: $e");
      messenger.showSnackBar(
        SnackBar(content: Text("❌ Error al generar el Excel: $e"), backgroundColor: Colors.redAccent)
      );
    }
  }
}
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ReportGenerator {
  static Future<void> mostrarOpcionesYGenerar(BuildContext context, List<dynamic> cacheVolvo) async {
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
          backgroundColor: const Color(0xFF1A3A5A),
          title: const Text("Configurar Reporte Diario", style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: opciones.keys.map((key) {
                return CheckboxListTile(
                  title: Text(key, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  value: opciones[key],
                  activeColor: Colors.orangeAccent,
                  checkColor: Colors.black,
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("GENERAR EXCEL", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (confirmar == true) {
      await _ejecutarGeneracion(opciones, cacheVolvo);
    }
  }

  static Future<void> _ejecutarGeneracion(Map<String, bool> filtros, List<dynamic> cacheVolvo) async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('VEHICULOS').get();
      var excel = Excel.createExcel();
      String sheetName = "REPORTE";
      excel.rename('Sheet1', sheetName);
      Sheet sheetObject = excel[sheetName];

      // Formato para números (Miles y Decimales)
      var numStyle = CellStyle(numberFormat: NumFormat.standard_4); 
      
      // Función para convertir YYYY-MM-DD a DD/MM/AAAA
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

      // Cabecera
      for (var i = 0; i < titulos.length; i++) {
        var cell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(titulos[i]);
        cell.cellStyle = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString("#D3D3D3"));
      }

      int row = 1;
      for (var doc in snapshot.docs) {
        // ✅ CORRECCIÓN: Definimos data una sola vez para evitar el unnecessary_cast
        final Map<String, dynamic> data = doc.data();
        final String patente = doc.id;
        final String vin = (data['VIN'] ?? '').toString().trim().toUpperCase();
        
        final volvoData = cacheVolvo.firstWhere(
          (v) => v['vin']?.toString().toUpperCase() == vin && vin.isNotEmpty,
          orElse: () => null,
        );

        int col = 0;
        String limpiar(dynamic val) => val?.toString().replaceAll(',', '').replaceAll(':', '') ?? '';

        // Escribir Patente (Columna fija 0)
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = TextCellValue(patente);

        if (filtros["TIPO"]!) { sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = TextCellValue(limpiar(data['TIPO'])); }
        if (filtros["MARCA"]!) { sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = TextCellValue(limpiar(data['MARCA'])); }
        if (filtros["MODELO"]!) { sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = TextCellValue(limpiar(data['MODELO'])); }
        if (filtros["EMPRESA"]!) { sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = TextCellValue(limpiar(data['EMPRESA'])); }
        if (filtros["VIN"]!) { sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = TextCellValue(vin.isEmpty ? "-" : vin); }

        // KM ACTUAL con formato de miles y decimal
        if (filtros["KM ACTUAL"]!) {
          double kmValue = 0.0;
          if (data['KM_ACTUAL'] is num) {
            kmValue = (data['KM_ACTUAL']).toDouble();
          }
          var cell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row));
          cell.value = DoubleCellValue(kmValue);
          cell.cellStyle = numStyle;
        }

        double litros = 0.0;
        if (volvoData != null && volvoData['accumulatedData'] != null) {
          litros = (volvoData['accumulatedData']['totalFuelConsumption'] ?? 0.0).toDouble();
        }

        if (filtros["CONSUMO (L)"]!) {
          var cell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row));
          cell.value = DoubleCellValue(litros);
          cell.cellStyle = numStyle;
        }
        
        if (filtros["PROMEDIO KM/L"]!) {
          double kmValue = (data['KM_ACTUAL'] is num) ? (data['KM_ACTUAL']).toDouble() : 0.0;
          double promedio = (litros > 0 && kmValue > 0) ? double.parse((kmValue / litros).toStringAsFixed(2)) : 0.0;
          var cell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row));
          cell.value = DoubleCellValue(promedio);
          cell.cellStyle = numStyle;
        }

        if (filtros["VENCIMIENTO RTO"]!) {
          sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = TextCellValue(formatearFecha(data['VENCIMIENTO_RTO']));
        }
        if (filtros["VENCIMIENTO SEGURO"]!) {
          sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = TextCellValue(formatearFecha(data['VENCIMIENTO_SEGURO']));
        }
        
        if (filtros["ESTADO CONEXION"]!) {
          sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = TextCellValue(volvoData != null ? "CONECTADO" : "OFFLINE");
        }

        row++;
      }

      for (var i = 0; i < titulos.length; i++) {
        sheetObject.setColumnWidth(i, 32.0);
      }

      final now = DateTime.now();
      final path = "${(await getApplicationDocumentsDirectory()).path}/REPORTE_${now.day}_${now.hour}${now.minute}.xlsx";
      final fileBytes = excel.save();
      if (fileBytes != null) {
        File(path)..createSync(recursive: true)..writeAsBytesSync(fileBytes);
      }
      if (Platform.isWindows) {
        await Process.run('explorer.exe', [path]);
      }
    } catch (e) {
      debugPrint("❌ Error Reporte: $e");
    }
  }
}
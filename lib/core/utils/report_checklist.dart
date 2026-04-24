import 'dart:io';
import 'package:excel/excel.dart' as ex; // ✅ Mismo prefijo para evitar conflictos
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart'; // Para compartir en móvil

class ReportChecklistService {
  
  static Future<void> mostrarOpcionesYGenerar(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    
    // ✅ Opciones para que Ariel elija qué columnas quiere ver
    Map<String, bool> opciones = {
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
          backgroundColor: const Color(0xFF1A3A5A),
          title: const Text("Configurar Reporte Novedades", style: TextStyle(color: Colors.white, fontSize: 18)),
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
      messenger.showSnackBar(const SnackBar(content: Text("Procesando novedades...")));
      await _ejecutarGeneracion(opciones);
    }
  }

  static Future<void> _ejecutarGeneracion(Map<String, bool> filtros) async {
    try {
      // Traemos los checklists ordenados por fecha
      final snapshot = await FirebaseFirestore.instance
          .collection('CHECKLISTS')
          .orderBy('FECHA', descending: true)
          .get();

      var excel = ex.Excel.createExcel(); 
      String sheetName = "NOVEDADES";
      excel.rename('Sheet1', sheetName);
      ex.Sheet sheetObject = excel[sheetName];

      // ✅ Mismo sistema de bordes y estilos que el de Flota
      var borderThin = ex.Border(borderStyle: ex.BorderStyle.Thin);
      var borderMedium = ex.Border(borderStyle: ex.BorderStyle.Medium);

      var headerStyle = ex.CellStyle(
        bold: true, 
        backgroundColorHex: ex.ExcelColor.fromHexString("#D3D3D3"),
        horizontalAlign: ex.HorizontalAlign.Center,
        bottomBorder: borderMedium,
        topBorder: borderThin,
        leftBorder: borderThin,
        rightBorder: borderThin,
      );

      // Cabeceras dinámicas basadas en la selección
      List<String> titulos = [];
      filtros.forEach((key, val) { if (val) titulos.add(key); });

      for (var i = 0; i < titulos.length; i++) {
        var cell = sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = ex.TextCellValue(titulos[i]);
        cell.cellStyle = headerStyle;
      }

      int row = 1;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final Map respuestas = data['RESPUESTAS'] ?? {};
        final Map observaciones = data['OBSERVACIONES'] ?? {};
        
        // Formatear fecha
        String fechaStr = "-";
        if (data['FECHA'] != null) {
          DateTime dt = (data['FECHA'] as Timestamp).toDate();
          fechaStr = DateFormat('dd/MM/yyyy').format(dt);
        }

        // Recorremos las respuestas para encontrar solo REG o MAL
        respuestas.forEach((item, estado) {
          if (estado == "REG" || estado == "MAL") {
            int col = 0;

            if (filtros["FECHA"]!) { 
              sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = ex.TextCellValue(fechaStr);
            }
            if (filtros["DOMINIO"]!) { 
              sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = ex.TextCellValue(data['DOMINIO'] ?? "");
            }
            if (filtros["TIPO"]!) { 
              sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = ex.TextCellValue(data['TIPO'] ?? "");
            }
            if (filtros["CHOFER"]!) { 
              sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = ex.TextCellValue(data['NOMBRE'] ?? "");
            }
            if (filtros["ITEM"]!) { 
              sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = ex.TextCellValue(item);
            }
            if (filtros["ESTADO"]!) { 
              sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = ex.TextCellValue(estado);
            }
            if (filtros["OBSERVACIÓN"]!) { 
              sheetObject.cell(ex.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row)).value = ex.TextCellValue(observaciones[item] ?? "");
            }
            
            row++; // Siguiente fila para la siguiente novedad
          }
        });
      }

      // Ajuste de ancho de columnas
      for (var i = 0; i < titulos.length; i++) {
        sheetObject.setColumnWidth(i, 20.0); 
      }

      // Guardar archivo
      final String fileName = "Reporte_Novedades_${DateTime.now().millisecondsSinceEpoch}.xlsx";
      final directory = await getApplicationDocumentsDirectory();
      final path = "${directory.path}/$fileName";
      
      final fileBytes = excel.save();
      if (fileBytes != null) {
        File(path)
          ..createSync(recursive: true)
          ..writeAsBytesSync(fileBytes);
        
        // Compatibilidad Windows / Móvil
        if (Platform.isWindows) {
          await Process.run('cmd', ['/c', 'start', '', path]);
        } else {
          await Share.shareXFiles([XFile(path)], text: 'Reporte de Novedades');
        }
      }
    } catch (e) {
      debugPrint("❌ Error Reporte Checklist: $e");
    }
  }
}
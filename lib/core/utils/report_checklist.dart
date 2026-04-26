import 'dart:io';
import 'package:excel/excel.dart' as ex; 
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart'; 

class ReportChecklistService {
  
  static Future<void> mostrarOpcionesYGenerar(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    
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
          backgroundColor: Theme.of(context).colorScheme.surface, // ✅ MENTOR: Tema global
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withAlpha(20))
          ),
          title: const Text("Reporte de Novedades", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxHeight: 400),
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
              Text("Procesando novedades del mes..."),
            ],
          ),
          backgroundColor: Colors.orangeAccent,
          duration: Duration(seconds: 2),
        )
      );
      // ✅ MENTOR: Pasamos el messenger a la función asíncrona
      await _ejecutarGeneracion(opciones, messenger);
    }
  }

  static Future<void> _ejecutarGeneracion(Map<String, bool> filtros, ScaffoldMessengerState messenger) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('CHECKLISTS')
          .orderBy('FECHA', descending: true)
          .get();

      var excel = ex.Excel.createExcel(); 
      String sheetName = "NOVEDADES";
      excel.rename('Sheet1', sheetName);
      ex.Sheet sheetObject = excel[sheetName];

      var borderThin = ex.Border(borderStyle: ex.BorderStyle.Thin);
      var borderMedium = ex.Border(borderStyle: ex.BorderStyle.Medium);

      var headerStyle = ex.CellStyle(
        bold: true, 
        backgroundColorHex: ex.ExcelColor.fromHexString("#1A3A5A"), // ✅ MENTOR: Azul corporativo
        fontColorHex: ex.ExcelColor.fromHexString("#FFFFFF"),
        horizontalAlign: ex.HorizontalAlign.Center,
        bottomBorder: borderMedium,
        topBorder: borderThin,
        leftBorder: borderThin,
        rightBorder: borderThin,
      );

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
        
        String fechaStr = "-";
        if (data['FECHA'] != null) {
          DateTime dt = (data['FECHA'] as Timestamp).toDate();
          fechaStr = DateFormat('dd/MM/yyyy').format(dt);
        }

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
            
            row++; 
          }
        });
      }

      for (var i = 0; i < titulos.length; i++) {
        sheetObject.setColumnWidth(i, 20.0); 
      }

      final String fileName = "Reporte_Novedades_${DateTime.now().millisecondsSinceEpoch}.xlsx";
      final directory = await getApplicationDocumentsDirectory();
      final path = "${directory.path}/$fileName";
      
      final fileBytes = excel.save();
      if (fileBytes != null) {
        File(path)
          ..createSync(recursive: true)
          ..writeAsBytesSync(fileBytes);
        
        if (Platform.isWindows) {
          await Process.run('cmd', ['/c', 'start', '', path]);
        } else {
          // ✅ MENTOR: Disparo automático del menú de compartir nativo
          await Share.shareXFiles([XFile(path)], text: 'Reporte de Novedades (Mantenimiento)');
        }
      }
    } catch (e) {
      debugPrint("❌ Error Reporte Checklist: $e");
      // ✅ MENTOR: Feedback seguro para el usuario si algo falla
      messenger.showSnackBar(
        SnackBar(content: Text("❌ Error al generar el Excel: $e"), backgroundColor: Colors.redAccent)
      );
    }
  }
}
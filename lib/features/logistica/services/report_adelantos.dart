import 'package:excel/excel.dart' as ex;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../shared/utils/app_feedback.dart';
import '../../../shared/utils/formatters.dart';
import '../../reports/services/excel_utils.dart' as xu;
import '../../reports/services/report_save_helper.dart';
import '../models/adelanto_chofer.dart';

/// Reporte Excel de adelantos. Lo dispara `LogisticaAdelantosScreen`
/// con los adelantos que el operador **seleccionó** en la lista
/// (checkbox por adelanto) y el rango de fechas activo si lo hay.
///
/// Output: hoja única `ADELANTOS` con columnas pedidas por Santiago
/// (2026-05-13):
///   #  ·  FECHA  ·  CHOFER  ·  DESCRIPCIÓN  ·  IMPORTE  ·  N° RECIBO
///
/// Última fila: TOTAL con la suma de importes (en bold, columna
/// IMPORTE).
class ReportAdelantosService {
  ReportAdelantosService._();

  static Future<void> generar({
    required BuildContext context,
    required List<AdelantoChofer> adelantos,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  }) async {
    final messenger = ScaffoldMessenger.of(context);

    if (kIsWeb) {
      AppFeedback.warningOn(messenger,
          'Los reportes Excel solo están disponibles en Windows, Android e iOS.');
      return;
    }
    if (adelantos.isEmpty) {
      AppFeedback.warningOn(
          messenger, 'No hay adelantos seleccionados para exportar.');
      return;
    }

    _notificarProgreso(messenger);
    try {
      final excel = ex.Excel.createExcel();
      excel.rename('Sheet1', 'ADELANTOS');
      final hoja = excel['ADELANTOS'];

      // Ordenar por fecha ascendente para que el correlativo del
      // reporte (columna #) tenga sentido cronológico — el stream de
      // la pantalla viene ordenado descendente.
      final ordenados = [...adelantos]
        ..sort((a, b) => a.fecha.compareTo(b.fecha));

      final headers = [
        '#',
        'FECHA',
        'CHOFER',
        'DESCRIPCIÓN',
        'IMPORTE',
        'N° RECIBO',
      ];
      for (var i = 0; i < headers.length; i++) {
        final cell = hoja.cell(
            ex.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = ex.TextCellValue(headers[i]);
        cell.cellStyle = ex.CellStyle(
          bold: true,
          backgroundColorHex: ex.ExcelColor.fromHexString('#2E7D32'),
          fontColorHex: ex.ExcelColor.fromHexString('#FFFFFF'),
        );
      }

      var total = 0.0;
      for (var i = 0; i < ordenados.length; i++) {
        final a = ordenados[i];
        final row = i + 1;
        final nombre = a.choferNombre?.trim().isNotEmpty == true
            ? a.choferNombre!.trim()
            : 'DNI ${a.choferDni}';
        final desc = a.observacion?.trim().isNotEmpty == true
            ? a.observacion!.trim()
            : '';
        final recibo = a.numeroRecibo == null
            ? ''
            : a.numeroRecibo.toString().padLeft(6, '0');

        _setInt(hoja, 0, row, i + 1);
        _setText(hoja, 1, row, AppFormatters.formatearFecha(a.fecha));
        _setText(hoja, 2, row, nombre);
        _setText(hoja, 3, row, desc);
        _setMonto(hoja, 4, row, a.monto);
        _setText(hoja, 5, row, recibo);

        total += a.monto;
      }

      // Fila TOTAL — al final, columna IMPORTE en bold con la suma.
      final totalRow = ordenados.length + 1;
      _setText(hoja, 3, totalRow, 'TOTAL');
      hoja
              .cell(ex.CellIndex.indexByColumnRow(
                  columnIndex: 3, rowIndex: totalRow))
              .cellStyle =
          ex.CellStyle(bold: true);
      _setMonto(hoja, 4, totalRow, total, bold: true);

      xu.autoFitColumnas(hoja, headers.length, totalRow + 1);

      final bytesRaw = excel.save();
      if (bytesRaw == null || bytesRaw.isEmpty) {
        throw StateError('El archivo Excel se generó vacío.');
      }
      final bytes = xu.aplicarAutoFilterAlXlsx(bytesRaw);

      // Nombre del archivo: si hay rango de fechas, lo metemos para
      // que dos exports distintos no se pisen. Ej:
      //   Adelantos_2026_05_13_HHmmss.xlsx
      //   Adelantos_2026_05_13_HHmmss_01-05-2026_al_13-05-2026.xlsx
      String? sufijo;
      if (fechaDesde != null && fechaHasta != null) {
        sufijo =
            '${_slugFecha(fechaDesde)}_al_${_slugFecha(fechaHasta)}';
      } else if (fechaDesde != null) {
        sufijo = 'desde_${_slugFecha(fechaDesde)}';
      } else if (fechaHasta != null) {
        sufijo = 'hasta_${_slugFecha(fechaHasta)}';
      }
      final nombreArchivo = ReportSaveHelper.nombreUnico(
        'Adelantos',
        sufijoExtra: sufijo,
      );

      await ReportSaveHelper.guardarYAbrir(
        bytes: bytes,
        nombreDefault: nombreArchivo,
        messenger: messenger,
        textoCompartir:
            'Adelantos a choferes — Coopertrans Móvil (${ordenados.length} items)',
      );
    } catch (e) {
      AppFeedback.errorOn(messenger, 'Error generando reporte: $e');
    }
  }

  // ===========================================================================
  // HELPERS DE CELDA
  // ===========================================================================

  static void _setText(ex.Sheet hoja, int col, int row, String v) {
    hoja
            .cell(ex.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
            .value =
        ex.TextCellValue(v);
  }

  static void _setInt(ex.Sheet hoja, int col, int row, int v) {
    final cell = hoja.cell(
        ex.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    cell.value = ex.IntCellValue(v);
    cell.cellStyle = ex.CellStyle(numberFormat: xu.formatoARSinDecimales);
  }

  static void _setMonto(
    ex.Sheet hoja,
    int col,
    int row,
    double v, {
    bool bold = false,
  }) {
    final cell = hoja.cell(
        ex.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    cell.value = ex.DoubleCellValue(v);
    cell.cellStyle = ex.CellStyle(
      numberFormat: xu.formatoAR,
      bold: bold,
    );
  }

  static String _slugFecha(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    return '$dd-$mm-$yyyy';
  }

  static void _notificarProgreso(ScaffoldMessengerState messenger) {
    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2),
            ),
            SizedBox(width: 15),
            Text('Generando resumen de adelantos...'),
          ],
        ),
        backgroundColor: Colors.blueGrey,
      ),
    );
  }
}

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
/// (checkbox por adelanto).
///
/// Diseño basado en la planilla que Santiago compartió 2026-05-13
/// (`2026-05-13 - VIAJES DARIOS.xlsx`). Estructura:
///
///   ┌────────────────────────────────────────────────────────┐
///   │  TRANSPORTE SERVI-TOLVA                                │   ← banner
///   │  Resumen de adelantos                                  │
///   │  FECHA: 13-05-2026             (o FECHAS si > 1 día)   │
///   ├────────────────────────────────────────────────────────┤
///   │  # │ CHOFER │ DETALLE │ ADELANTO $ │ N° RECIBO          │
///   │  1 │ ...    │ ...     │      ...   │ ...                │
///   │  ...                                                    │
///   │            │         │      TOTAL │ $ XXX.XXX           │
///   └────────────────────────────────────────────────────────┘
///
/// Cambios vs versión anterior pedidos por Santiago:
///   - Columna FECHA del cuerpo → SACADA (ahora está en el encabezado).
///   - Columna OBSERVACIÓN → renombrada a DETALLE.
///   - Sin columna firma (era columna nominal en la planilla de
///     referencia, pero acá la firma física vive en el recibo
///     impreso de cada adelanto).
///   - Encabezado dinámico: muestra "FECHA: dd-mm-aaaa" si todos los
///     adelantos son del mismo día; sino "FECHAS: dd-mm · dd-mm · …".
class ReportAdelantosService {
  ReportAdelantosService._();

  /// Número de columnas de la tabla — usado para mergear el banner
  /// superior. Si cambian las columnas, ajustar acá.
  static const int _cols = 5;

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

      // Orden cronológico ASC para que el correlativo del reporte
      // (columna #) tenga sentido (más antiguos arriba). El stream de
      // la pantalla viene desc.
      final ordenados = [...adelantos]
        ..sort((a, b) => a.fecha.compareTo(b.fecha));

      // ─── ENCABEZADO ──────────────────────────────────────────────
      // Fila 0: razón social en bold grande.
      _setMergedHeader(
        hoja,
        row: 0,
        text: 'TRANSPORTE SERVI-TOLVA',
        backgroundHex: '#1B5E20',
        fontHex: '#FFFFFF',
        fontSize: 16,
        bold: true,
        align: ex.HorizontalAlign.Center,
      );
      // Fila 1: subtítulo.
      _setMergedHeader(
        hoja,
        row: 1,
        text: 'Resumen de adelantos',
        backgroundHex: '#2E7D32',
        fontHex: '#FFFFFF',
        fontSize: 11,
        bold: true,
        align: ex.HorizontalAlign.Center,
      );
      // Fila 2: FECHA o FECHAS según cuántos días distintos.
      _setMergedHeader(
        hoja,
        row: 2,
        text: _renderEtiquetaFechas(ordenados),
        backgroundHex: '#E8F5E9',
        fontHex: '#1B5E20',
        fontSize: 11,
        bold: true,
        align: ex.HorizontalAlign.Center,
      );
      // Fila 3: separador en blanco.

      // ─── HEADERS DE TABLA (fila 4) ───────────────────────────────
      const headerRow = 4;
      final headers = [
        '#',
        'CHOFER',
        'DETALLE',
        'ADELANTO \$',
        'N° RECIBO',
      ];
      for (var i = 0; i < headers.length; i++) {
        final cell = hoja.cell(
            ex.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: headerRow));
        cell.value = ex.TextCellValue(headers[i]);
        cell.cellStyle = ex.CellStyle(
          bold: true,
          backgroundColorHex: ex.ExcelColor.fromHexString('#2E7D32'),
          fontColorHex: ex.ExcelColor.fromHexString('#FFFFFF'),
          horizontalAlign: ex.HorizontalAlign.Center,
          verticalAlign: ex.VerticalAlign.Center,
        );
      }
      // Header un poco más alto que las filas de datos.
      hoja.setRowHeight(headerRow, 24);

      // ─── FILAS DE DATOS + FILAS VACÍAS NUMERADAS ─────────────────
      // Replicamos el formato de la planilla manual de Santiago: 20
      // filas (o más, si los seleccionados ya las superan) pre-
      // numeradas, con las primeras N llenas y el resto en blanco
      // para que pueda escribir a mano más adelantos si los carga
      // físicamente y los entra después al sistema.
      const filasMin = 20;
      final totalFilas =
          ordenados.length > filasMin ? ordenados.length : filasMin;
      for (var i = 0; i < totalFilas; i++) {
        final row = headerRow + 1 + i;

        // Numeración (siempre, esté la fila llena o vacía).
        _setInt(hoja, 0, row, i + 1);

        if (i < ordenados.length) {
          final a = ordenados[i];
          final nombre = a.choferNombre?.trim().isNotEmpty == true
              ? a.choferNombre!.trim()
              : 'DNI ${a.choferDni}';
          final detalle = a.observacion?.trim().isNotEmpty == true
              ? a.observacion!.trim()
              : '';
          final recibo = a.numeroRecibo == null
              ? ''
              : a.numeroRecibo.toString().padLeft(6, '0');
          _setText(hoja, 1, row, nombre);
          _setText(hoja, 2, row, detalle);
          _setMonto(hoja, 3, row, a.monto);
          _setText(hoja, 4, row, recibo);
        }

        // Altura cómoda en TODAS las filas (llenas y vacías) para
        // que el reporte luzca espacioso, no comprimido. Es lo que
        // pidió Santiago al pasar el ejemplo de planilla manual.
        hoja.setRowHeight(row, 22);
      }

      final ultimaRow = headerRow + totalFilas;
      xu.autoFitColumnas(hoja, _cols, ultimaRow + 1);
      // Forzar ancho mínimo de la columna "DETALLE" para que las
      // observaciones largas no se compriman demasiado al exportar.
      // `getColumnWidth` no expone API confiable en excel ^4.0.6, así
      // que aplicamos un ancho fijo cómodo (28) que cubre la mayoría
      // de observaciones; si el autoFit calculó más, queda el mayor.
      hoja.setColumnWidth(2, 28);
      // Columnas Chofer y Recibo un toque más anchas también.
      hoja.setColumnWidth(1, 22);
      hoja.setColumnWidth(3, 16);
      hoja.setColumnWidth(4, 14);

      final bytesRaw = excel.save();
      if (bytesRaw == null || bytesRaw.isEmpty) {
        throw StateError('El archivo Excel se generó vacío.');
      }
      // No aplicamos AutoFilter al xlsx porque el encabezado merged
      // de filas 0-2 confunde al filtro (lo coloca sobre el banner en
      // lugar de la tabla). El operador puede activarlo manual con
      // Ctrl+Shift+L si lo necesita.
      final bytes = bytesRaw;

      // Nombre: si hay rango activo en la UI, lo metemos para que
      // dos exports del mismo período no se pisen.
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

  /// Devuelve "FECHA: dd-mm-aaaa" si todos los adelantos son del mismo
  /// día, o "FECHAS: dd-mm · dd-mm · ..." si son varios. Las fechas se
  /// listan ordenadas ascendente. Si hay más de 5 fechas distintas
  /// muestra el rango "FECHAS: dd-mm-aaaa AL dd-mm-aaaa" para no
  /// inflar el encabezado.
  static String _renderEtiquetaFechas(List<AdelantoChofer> adelantos) {
    // Set para deduplicar por día (ignoramos hora — todos los
    // adelantos suelen estar a las 00:00 pero por las dudas).
    final dias = <DateTime>{};
    for (final a in adelantos) {
      dias.add(DateTime(a.fecha.year, a.fecha.month, a.fecha.day));
    }
    final ordenados = dias.toList()..sort();
    if (ordenados.length == 1) {
      return 'FECHA: ${AppFormatters.formatearFecha(ordenados.first)}';
    }
    if (ordenados.length > 5) {
      return 'FECHAS: ${AppFormatters.formatearFecha(ordenados.first)} '
          'AL ${AppFormatters.formatearFecha(ordenados.last)}';
    }
    return 'FECHAS: ${ordenados.map(AppFormatters.formatearFecha).join(" · ")}';
  }

  // ===========================================================================
  // HELPERS DE CELDA
  // ===========================================================================

  /// Crea una fila "banner" merged a través de todas las columnas de
  /// la tabla, con el estilo dado. La lib `excel` no acepta merge
  /// vacío — escribimos el texto en la primera celda y mergeamos.
  static void _setMergedHeader(
    ex.Sheet hoja, {
    required int row,
    required String text,
    required String backgroundHex,
    required String fontHex,
    required double fontSize,
    bool bold = false,
    required ex.HorizontalAlign align,
  }) {
    final first = ex.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row);
    final last =
        ex.CellIndex.indexByColumnRow(columnIndex: _cols - 1, rowIndex: row);
    final cell = hoja.cell(first);
    cell.value = ex.TextCellValue(text);
    cell.cellStyle = ex.CellStyle(
      bold: bold,
      fontSize: fontSize.toInt(),
      backgroundColorHex: ex.ExcelColor.fromHexString(backgroundHex),
      fontColorHex: ex.ExcelColor.fromHexString(fontHex),
      horizontalAlign: align,
      verticalAlign: ex.VerticalAlign.Center,
    );
    // Aplicar el mismo background a las celdas mergeadas para que
    // visualmente quede uniforme — sin esto, el resto de la fila
    // queda blanca y se ve el corte.
    for (var c = 1; c < _cols; c++) {
      hoja
          .cell(
              ex.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row))
          .cellStyle = ex.CellStyle(
        backgroundColorHex: ex.ExcelColor.fromHexString(backgroundHex),
      );
    }
    hoja.merge(first, last);
    hoja.setRowHeight(row, fontSize + 12);
  }

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
    cell.cellStyle = ex.CellStyle(
      numberFormat: xu.formatoARSinDecimales,
      horizontalAlign: ex.HorizontalAlign.Center,
    );
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
      horizontalAlign: ex.HorizontalAlign.Right,
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

// Helpers compartidos por todos los reportes Excel.
//
// Centralizamos acá todo lo que repetiríamos en cada report_*.dart:
// el parche de AutoFilter sobre el XML del .xlsx (la lib `excel` no
// expone API), el cálculo manual de auto-fit (porque setColumnAutoFit
// solo flagea sin calcular), y el format code argentino para números.
//
// Si en el futuro migramos a otra librería de Excel (syncfusion, etc.),
// estos helpers desaparecen — pero la API expuesta es genérica y los
// callers no necesitan cambiar.

import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as ex;

/// Formato numérico argentino: 1.234.567,89 (punto miles, coma
/// decimal). El prefijo `[$-2C0A]` fuerza el locale es-AR
/// independiente de la configuración regional de la PC del lector.
const formatoAR = ex.CustomNumericNumFormat(
  formatCode: r'[$-2C0A]#,##0.00',
);

/// Formato numérico argentino sin decimales (1.234.567). Para
/// columnas tipo "KM" donde no aporta el .89 final.
const formatoARSinDecimales = ex.CustomNumericNumFormat(
  formatCode: r'[$-2C0A]#,##0',
);

/// Decodifica el .xlsx (ZIP), inyecta `<autoFilter ref="A1:Z10000"/>`
/// en cada worksheet después de `</sheetData>`, y re-empaqueta. El
/// resultado: Excel activa los filtros automáticamente al abrir el
/// archivo (sin tener que hacer Ctrl+Shift+L manual).
///
/// La librería `excel` 4.0.6 no expone API para AutoFilter (issue
/// abierto en su repo hace 20+ meses). Migrar a syncfusion_flutter_xlsio
/// requiere licencia comercial — Vecchi no califica para Community
/// License (>10 empleados típicos en transporte). Solución: parche
/// directo al XML.
List<int> aplicarAutoFilterAlXlsx(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final patron = RegExp(r'^xl/worksheets/sheet\d+\.xml$');

  final out = Archive();
  for (final file in archive.files) {
    if (file.isFile && patron.hasMatch(file.name)) {
      final content = utf8.decode(file.content as List<int>);
      final modified = _inyectarAutoFilter(content);
      final newBytes = utf8.encode(modified);
      out.addFile(ArchiveFile(file.name, newBytes.length, newBytes));
    } else {
      out.addFile(file);
    }
  }
  final encoded = ZipEncoder().encode(out);
  // Defensa: si por algún motivo encode devuelve null (no debería con
  // un Archive válido), devolvemos los bytes originales — el archivo
  // se abre sin AutoFilter pero al menos no se rompe.
  return encoded ?? bytes;
}

/// Inyecta `<autoFilter ref="A1:Z10000"/>` en el XML de un worksheet.
/// El elemento debe ir DESPUÉS de `</sheetData>` (orden requerido por
/// el spec OOXML — sino Excel rechaza el archivo como corrupto).
///
/// Rango "A1:Z10000": amplio para cubrir cualquier reporte razonable
/// (Excel ignora celdas vacías al filtrar). Si el reporte tiene > 26
/// columnas o > 10000 filas, ampliar.
String _inyectarAutoFilter(String xml) {
  if (xml.contains('<autoFilter ')) return xml;
  return xml.replaceFirst(
    '</sheetData>',
    '</sheetData><autoFilter ref="A1:Z10000"/>',
  );
}

/// Auto-fit de columnas calculado manual: para cada columna, ancho =
/// max(largo_título, max_largo_celda) + 2 chars de padding.
///
/// Por qué no usar `setColumnAutoFit` de la lib: ese solo marca un
/// flag y delega el cálculo a Excel al abrir. Excel suele truncar
/// headers largos. Calculando acá garantizamos que tanto el título
/// como cualquier celda entran sin truncado.
///
/// Para celdas DoubleCellValue/IntCellValue, simulamos el formato AR
/// (1.234.567,89) para estimar el ancho visual real, no solo los
/// dígitos crudos.
void autoFitColumnas(ex.Sheet hoja, int numCols, int numRows) {
  for (var col = 0; col < numCols; col++) {
    var maxLen = 0;
    for (var row = 0; row < numRows; row++) {
      final cell = hoja.cell(ex.CellIndex.indexByColumnRow(
          columnIndex: col, rowIndex: row));
      final len = _anchoCelda(cell);
      if (len > maxLen) maxLen = len;
    }
    final ancho = (maxLen < 6 ? 6 : maxLen) + 2;
    hoja.setColumnWidth(col, ancho.toDouble());
  }
}

int _anchoCelda(ex.Data cell) {
  final value = cell.value;
  if (value == null) return 0;
  if (value is ex.TextCellValue) {
    return value.value.toString().length;
  }
  if (value is ex.DoubleCellValue) {
    return _renderArgFormatLength(value.value);
  }
  if (value is ex.IntCellValue) {
    return _renderArgFormatLength(value.value.toDouble());
  }
  return value.toString().length;
}

int _renderArgFormatLength(double value) {
  final fixed = value.toStringAsFixed(2); // "1234567.89"
  final partes = fixed.split('.');
  final entera = partes[0].replaceAll('-', '');
  final puntos = ((entera.length - 1) ~/ 3); // separadores de miles
  final signo = value < 0 ? 1 : 0;
  return entera.length + puntos + 1 /* coma */ + 2 /* decimales */ + signo;
}

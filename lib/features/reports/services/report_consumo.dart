import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as ex;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/utils/app_feedback.dart';

/// Reporte de Consumo de Combustible (admin).
///
/// Cruza la flota de Firestore con dos fuentes de telemetría:
///
/// - **`TELEMETRIA_HISTORICO`** (Firestore): snapshots diarios que el
///   AutoSync guarda al final de cada ciclo, con `litros_acumulados`
///   y `km` por unidad por día. Si el rango pedido cae dentro de los
///   días que ya tienen snapshot, el reporte calcula litros y KM
///   reales del **período** restando los snapshots de inicio y fin.
///
/// - **Cache Volvo en memoria** (`accumulatedData.totalFuelConsumption`):
///   fallback cuando para una unidad no hay snapshots todavía (recién
///   se trackea, o el día elegido es anterior al inicio del histórico).
///   En ese caso el reporte muestra el acumulado total del vehículo y
///   marca la fila con "S/D (acum.)" para que el admin sepa que ese
///   dato no es del período.
///
/// El Excel sale con dos hojas:
///
/// - **DETALLE**: tabla con todas las unidades, una columna por opción
///   marcada en el dialog.
/// - **RANKING**: top 10 unidades más consumidoras del período (filtra
///   las que no tienen datos del período válidos), con barra Unicode
///   proporcional al máximo. El package `excel` no soporta charts
///   nativos, así que el barra se renderiza con caracteres `█`.
class ReportConsumoService {
  ReportConsumoService._();

  static Future<void> mostrarOpcionesYGenerar(
    BuildContext context,
    List<dynamic> cacheVolvo,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    if (kIsWeb) {
      AppFeedback.warningOn(messenger,
          'Los reportes Excel solo están disponibles en Windows y Android.');
      return;
    }

    // ============= 1) Rango de fechas (default: mes en curso) =============
    final hoy = DateTime.now();
    DateTime desde = DateTime(hoy.year, hoy.month, 1);
    DateTime hasta = hoy;

    // ============= 2) Columnas a incluir =============
    final Map<String, bool> opciones = {
      "PATENTE": true,
      "TIPO": true,
      "MARCA": true,
      "MODELO": true,
      "VIN": true,
      "EMPRESA": true,
      "KM ACTUAL": true,
      "LITROS TOTALES": true,
      "PROMEDIO L/100KM": true,
      "ULTIMA SINCRONIZACION": true,
      "ESTADO CONEXION": true,
    };

    final confirmar = await _mostrarDialogoOpciones(
      context: context,
      desde: desde,
      hasta: hasta,
      opciones: opciones,
      onRangoCambiado: (d, h) {
        desde = d;
        hasta = h;
      },
    );

    if (confirmar != true || !context.mounted) return;

    _notificarProgreso(messenger);
    await _ejecutarGeneracion(
      desde: desde,
      hasta: hasta,
      filtros: opciones,
      cacheVolvo: cacheVolvo,
      messenger: messenger,
    );
  }

  /// Muestra el dialog de opciones (rango + columnas). Devuelve `true`
  /// si el admin confirmó "GENERAR".
  ///
  /// El dialog se mantiene como `StatefulBuilder` porque las dos fechas
  /// y los checkboxes se actualizan in-place — no queremos cerrar y
  /// reabrir el dialog para cambiar una fecha.
  static Future<bool?> _mostrarDialogoOpciones({
    required BuildContext context,
    required DateTime desde,
    required DateTime hasta,
    required Map<String, bool> opciones,
    required void Function(DateTime, DateTime) onRangoCambiado,
  }) {
    DateTime localDesde = desde;
    DateTime localHasta = hasta;

    return showDialog<bool>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(ctx).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withAlpha(20)),
          ),
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Reporte de Consumo",
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                "Litros y promedio L/100km por unidad",
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _LabelSeccion('Rango de referencia'),
                  // Presets rápidos para los rangos más usados. Tocás
                  // un chip y se setea desde/hasta sin tener que abrir
                  // el calendario. El "Personalizado" se usa abriendo
                  // el botón de abajo directamente.
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final preset in _presetsRangos())
                        _ChipPreset(
                          label: preset.label,
                          activo: _esPresetActivo(
                              preset, localDesde, localHasta),
                          onTap: () {
                            setDialogState(() {
                              localDesde = preset.desde;
                              localHasta = preset.hasta;
                            });
                            onRangoCambiado(localDesde, localHasta);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8, left: 4),
                    child: Text(
                      'O tocá el botón para abrir el calendario y elegir '
                      'un rango personalizado (primero la fecha de inicio, '
                      'después la de fin).',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  _BotonRangoFecha(
                    desde: localDesde,
                    hasta: localHasta,
                    onPick: (d, h) {
                      setDialogState(() {
                        localDesde = d;
                        localHasta = h;
                      });
                      onRangoCambiado(localDesde, localHasta);
                    },
                  ),
                  const SizedBox(height: 4),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Los litros y km del período se calculan a partir de '
                      'los snapshots diarios que guarda el AutoSync. Si '
                      'una unidad todavía no tiene snapshots dentro del '
                      'rango, se reporta el acumulado total y se marca '
                      'como "S/D (acum.)".',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _LabelSeccion('Columnas'),
                  ...opciones.keys.map((key) {
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(key,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                      value: opciones[key],
                      activeColor: Colors.greenAccent,
                      onChanged: (val) =>
                          setDialogState(() => opciones[key] = val ?? false),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text("CANCELAR",
                  style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dCtx, true),
              child: const Text("GENERAR EXCEL"),
            ),
          ],
        ),
      ),
    );
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
            Text("Generando reporte de consumo..."),
          ],
        ),
        backgroundColor: Colors.blueGrey,
      ),
    );
  }

  // ===========================================================================
  // GENERACIÓN DEL EXCEL
  // ===========================================================================

  static Future<void> _ejecutarGeneracion({
    required DateTime desde,
    required DateTime hasta,
    required Map<String, bool> filtros,
    required List<dynamic> cacheVolvo,
    required ScaffoldMessengerState messenger,
  }) async {
    try {
      // Index Volvo por VIN para búsqueda O(1) por unidad de Firestore.
      final volvoMap = <String, dynamic>{
        for (final v in cacheVolvo)
          (v['vin']?.toString().toUpperCase() ?? ''): v,
      };

      final db = FirebaseFirestore.instance;

      // Snapshots históricos del rango ampliado.
      // Pedimos desde 30 días antes de `desde` para tener un buen
      // candidato como "inicio" (el AutoSync se ejecuta cada minuto
      // pero a veces hay días sin sync por feriados o caídas de Volvo).
      final desdeAmpliado = desde.subtract(const Duration(days: 30));
      final hastaAmpliado = hasta.add(const Duration(days: 1));
      final snapshotsHistoricos = await db
          .collection('TELEMETRIA_HISTORICO')
          .where('fecha',
              isGreaterThanOrEqualTo: Timestamp.fromDate(desdeAmpliado))
          .where('fecha',
              isLessThanOrEqualTo: Timestamp.fromDate(hastaAmpliado))
          .get();

      // Agrupamos los snapshots por patente, ordenados por fecha
      // ascendente. Después por cada unidad sacamos:
      //   - inicio = último snapshot con fecha <= desde
      //   - fin    = último snapshot con fecha <= hasta
      // Si solo hay uno, no podemos calcular diferencia (la unidad
      // arrancó tracking dentro del rango).
      final porPatente = <String, List<_Snapshot>>{};
      for (final doc in snapshotsHistoricos.docs) {
        final data = doc.data();
        final patente = (data['patente'] ?? '').toString();
        if (patente.isEmpty) continue;
        final ts = data['fecha'];
        if (ts is! Timestamp) continue;
        porPatente.putIfAbsent(patente, () => []).add(_Snapshot(
              fecha: ts.toDate(),
              litros: (data['litros_acumulados'] ?? 0).toDouble(),
              km: (data['km'] ?? 0).toDouble(),
            ));
      }
      for (final list in porPatente.values) {
        list.sort((a, b) => a.fecha.compareTo(b.fecha));
      }

      // Solo tractores: los enganches (BATEA, TOLVA, ACOPLADO, etc.)
      // no tienen motor, no tienen VIN cargado en la cuenta de Volvo
      // y siempre saldrían con "0 (acum.)" inflando el reporte con
      // ruido. El reporte de consumo es específico de unidades con
      // motor — los enganches se reportan en su propio reporte de
      // flota.
      final snapshot = await db
          .collection(AppCollections.vehiculos)
          .where('TIPO', isEqualTo: AppTiposVehiculo.tractor)
          .get();

      final excel = ex.Excel.createExcel();
      excel.rename('Sheet1', 'DETALLE');
      final hojaDetalle = excel['DETALLE'];

      final headerStyle = ex.CellStyle(
        bold: true,
        backgroundColorHex: ex.ExcelColor.fromHexString("#1A3A5A"),
        fontColorHex: ex.ExcelColor.fromHexString("#FFFFFF"),
        horizontalAlign: ex.HorizontalAlign.Center,
      );
      final numStyle = ex.CellStyle(numberFormat: ex.NumFormat.standard_4);

      // Sin header informativo arriba — el admin aplica AutoFilter
      // (Ctrl+Shift+L) directamente sobre la fila 0 y filtra/ordena
      // como cualquier tabla. El rango se ve en el nombre del archivo.
      final fmt = DateFormat('dd/MM/yyyy');

      // Cabeceras dinámicas en fila 0 — datos desde fila 1.
      final titulos = <String>[];
      filtros.forEach((key, val) {
        if (val) titulos.add(key);
      });

      const filaCabecera = 0;
      const filaInicioDatos = 1;

      for (var i = 0; i < titulos.length; i++) {
        final cell = hojaDetalle.cell(ex.CellIndex.indexByColumnRow(
            columnIndex: i, rowIndex: filaCabecera));
        cell.value = ex.TextCellValue(titulos[i]);
        cell.cellStyle = headerStyle;
      }

      // ============= Filas de datos =============
      // Acumulamos también una lista intermedia para construir el Ranking
      // sin recorrer Firestore dos veces.
      final filas = <_FilaConsumo>[];
      var currentRow = filaInicioDatos;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final patente = doc.id;
        final vin = (data['VIN'] ?? '').toString().trim().toUpperCase();
        final volvoData = volvoMap[vin];
        final fila = _FilaConsumo.from(
          patente: patente,
          data: data,
          volvoData: volvoData,
          historicos: porPatente[patente] ?? const [],
          desde: desde,
          hasta: hasta,
        );
        filas.add(fila);

        var col = 0;
        for (final titulo in titulos) {
          final cell = hojaDetalle.cell(ex.CellIndex.indexByColumnRow(
              columnIndex: col++, rowIndex: currentRow));
          _writeColumna(cell, titulo, fila, numStyle);
        }
        currentRow++;
      }

      for (var i = 0; i < titulos.length; i++) {
        hojaDetalle.setColumnWidth(i, 22.0);
      }

      // ============= Hoja RANKING (top 10 más consumidores) =============
      _construirHojaRanking(excel, filas);

      // ============= Guardar y abrir =============
      final fileName =
          "Consumo_${DateFormat('yyyy_MM_dd').format(DateTime.now())}.xlsx";
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/$fileName';
      final fileBytes = excel.save();
      if (fileBytes != null) {
        // Post-procesar: inyectar AutoFilter a todas las hojas para
        // que Excel active filtros automáticamente al abrir el archivo.
        // La librería `excel` 4.x no expone esa API, así que parcheamos
        // el XML del .xlsx directamente.
        final patched = _aplicarAutoFilterAlXlsx(fileBytes);
        File(path).writeAsBytesSync(patched);
        if (Platform.isWindows) {
          await Process.run('cmd', ['/c', 'start', '', path]);
        } else {
          await Share.shareXFiles(
            [XFile(path)],
            text: '⛽ Reporte de consumo de combustible — '
                '${fmt.format(desde)} a ${fmt.format(hasta)}',
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error reporte consumo: $e');
      AppFeedback.errorOn(messenger, 'Error al generar reporte: $e');
    }
  }

  // ===========================================================================
  // POST-PROCESAMIENTO: AutoFilter inyectado en el XML
  // ===========================================================================
  //
  // La librería `excel: ^4.0.6` no expone API para AutoFilter (pendiente
  // en su roadmap hace 20+ meses). Como upgrade a syncfusion_flutter_xlsio
  // (la única alternativa Dart pure que sí lo soporta) requiere licencia
  // comercial para Vecchi (no califica para Community), parcheamos el
  // XML del .xlsx generado: abrimos el ZIP, inyectamos
  // `<autoFilter ref="A1:Z10000"/>` en cada hoja después de
  // `</sheetData>`, y re-empaquetamos.
  //
  // Resultado: al abrir el archivo, Excel muestra las flechas de
  // filtro automáticamente en la fila de cabecera (sin tener que
  // hacer Ctrl+Shift+L manual).

  /// Decodifica el .xlsx (ZIP), inyecta AutoFilter en cada worksheet,
  /// y re-empaqueta. Devuelve los bytes modificados.
  static List<int> _aplicarAutoFilterAlXlsx(List<int> bytes) {
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
  /// (Excel ignora celdas vacías al filtrar). Si en el futuro tenemos
  /// reportes con más de 26 columnas o 10000 filas, ampliar.
  ///
  /// Si el XML ya tiene un `<autoFilter>` previo (caso raro), no
  /// duplicamos — devolvemos sin cambios.
  static String _inyectarAutoFilter(String xml) {
    if (xml.contains('<autoFilter ')) return xml;
    return xml.replaceFirst(
      '</sheetData>',
      '</sheetData><autoFilter ref="A1:Z10000"/>',
    );
  }

  /// Escribe el valor de una columna específica en la celda según el
  /// título lógico. Mantenemos esto en un switch separado para que sumar
  /// columnas nuevas sea agregar una rama y un key en `filtros`.
  static void _writeColumna(
    ex.Data cell,
    String titulo,
    _FilaConsumo f,
    ex.CellStyle numStyle,
  ) {
    switch (titulo) {
      case 'PATENTE':
        cell.value = ex.TextCellValue(f.patente);
        break;
      case 'TIPO':
        cell.value = ex.TextCellValue(f.tipo);
        break;
      case 'MARCA':
        cell.value = ex.TextCellValue(f.marca);
        break;
      case 'MODELO':
        cell.value = ex.TextCellValue(f.modelo);
        break;
      case 'VIN':
        cell.value = ex.TextCellValue(f.vin.isEmpty ? '-' : f.vin);
        break;
      case 'EMPRESA':
        cell.value = ex.TextCellValue(f.empresa);
        break;
      case 'KM ACTUAL':
        if (f.esPeriodo) {
          cell.value = ex.DoubleCellValue(f.km);
          cell.cellStyle = numStyle;
        } else {
          // Sin histórico no podemos saber km del período. Mostramos
          // el odómetro actual marcado para que el admin no lo cuente
          // como "km recorridos".
          cell.value = ex.TextCellValue('${f.km.round()} (acum.)');
        }
        break;
      case 'LITROS TOTALES':
        if (f.esPeriodo) {
          cell.value = ex.DoubleCellValue(f.litros);
          cell.cellStyle = numStyle;
        } else {
          cell.value =
              ex.TextCellValue('${f.litros.round()} (acum.)');
        }
        break;
      case 'PROMEDIO L/100KM':
        cell.value = ex.DoubleCellValue(
            double.parse(f.consumoLPor100Km.toStringAsFixed(2)));
        cell.cellStyle = numStyle;
        break;
      case 'ULTIMA SINCRONIZACION':
        cell.value = ex.TextCellValue(f.ultimaSync);
        break;
      case 'ESTADO CONEXION':
        cell.value = ex.TextCellValue(f.conectado ? 'CONECTADO' : 'OFFLINE');
        break;
    }
  }

  /// Construye la hoja "RANKING" con TODA la flota ordenada por
  /// consumo L/100km (de peor a mejor — los más altos consumen más
  /// combustible cada 100 km, son los que conviene revisar primero).
  ///
  /// Para visualizar la magnitud sin un chart nativo, agregamos una
  /// columna "BARRA" con caracteres `█` proporcionales al peor caso
  /// (la unidad más ineficiente). Es el truco clásico de "in-cell bar
  /// chart" — funciona en cualquier Excel y en LibreOffice sin macros.
  static void _construirHojaRanking(
      ex.Excel excel, List<_FilaConsumo> filas) {
    final hoja = excel['RANKING'];

    final headerStyle = ex.CellStyle(
      bold: true,
      backgroundColorHex: ex.ExcelColor.fromHexString("#5A1A1A"),
      fontColorHex: ex.ExcelColor.fromHexString("#FFFFFF"),
      horizontalAlign: ex.HorizontalAlign.Center,
    );

    // Solo unidades con datos REALES del período (esPeriodo && km > 0).
    // Sin km no se puede calcular L/100km. Las que tienen solo
    // acumulado no compiten porque la métrica del período no aplica.
    // Ordenamos descendente por L/100km — los peores arriba.
    final ranking = filas
        .where((f) => f.esPeriodo && f.km > 0 && f.consumoLPor100Km > 0)
        .toList()
      ..sort((a, b) => b.consumoLPor100Km.compareTo(a.consumoLPor100Km));

    // Cabeceras en fila 0 (sin título de hoja arriba — más limpio
    // para aplicar AutoFilter directo).
    const titulos = [
      '#',
      'PATENTE',
      'MARCA / MODELO',
      'L/100KM',
      'LITROS',
      'KM',
      'BARRA'
    ];
    for (var i = 0; i < titulos.length; i++) {
      final cell = hoja
          .cell(ex.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = ex.TextCellValue(titulos[i]);
      cell.cellStyle = headerStyle;
    }

    if (ranking.isEmpty) {
      hoja
          .cell(ex.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
          .value = ex.TextCellValue(
              'Sin snapshots históricos en el rango (todavía). El ranking '
              'aparece después de unos días de tracking activo.');
      return;
    }

    final maxConsumo = ranking.first.consumoLPor100Km;
    final numStyle = ex.CellStyle(numberFormat: ex.NumFormat.standard_4);

    for (var i = 0; i < ranking.length; i++) {
      final f = ranking[i];
      final fila = i + 1;

      hoja
          .cell(ex.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: fila))
          .value = ex.IntCellValue(i + 1);
      hoja
          .cell(ex.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: fila))
          .value = ex.TextCellValue(f.patente);
      hoja
          .cell(ex.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: fila))
          .value = ex.TextCellValue('${f.marca} ${f.modelo}'.trim());

      final consumoCell = hoja
          .cell(ex.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: fila));
      consumoCell.value = ex.DoubleCellValue(
          double.parse(f.consumoLPor100Km.toStringAsFixed(2)));
      consumoCell.cellStyle = numStyle;

      final litrosCell = hoja
          .cell(ex.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: fila));
      litrosCell.value = ex.DoubleCellValue(f.litros);
      litrosCell.cellStyle = numStyle;

      final kmCell = hoja
          .cell(ex.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: fila));
      kmCell.value = ex.DoubleCellValue(f.km);
      kmCell.cellStyle = numStyle;

      // Barra unicode: ancho proporcional al peor consumo (más L/100km
      // = barra más larga). Hasta 30 caracteres.
      final ratio = maxConsumo == 0 ? 0.0 : f.consumoLPor100Km / maxConsumo;
      final ancho = (ratio * 30).round();
      final barra = '█' * ancho;
      hoja
          .cell(ex.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: fila))
          .value = ex.TextCellValue(barra);
    }

    // Anchos cómodos para lectura
    hoja.setColumnWidth(0, 6);   // #
    hoja.setColumnWidth(1, 14);  // PATENTE
    hoja.setColumnWidth(2, 28);  // MARCA / MODELO
    hoja.setColumnWidth(3, 14);  // L/100KM
    hoja.setColumnWidth(4, 14);  // LITROS
    hoja.setColumnWidth(5, 14);  // KM
    hoja.setColumnWidth(6, 36);  // BARRA
  }
}

// =============================================================================
// MODELO INTERNO DE FILA
// =============================================================================

/// Snapshot histórico mínimo para los cálculos de período.
class _Snapshot {
  final DateTime fecha;
  final double litros;
  final double km;

  const _Snapshot({
    required this.fecha,
    required this.litros,
    required this.km,
  });
}

/// Tira en una sola estructura los datos de un vehículo + Volvo + el
/// período calculado desde los snapshots históricos.
class _FilaConsumo {
  final String patente;
  final String tipo;
  final String marca;
  final String modelo;
  final String vin;
  final String empresa;
  final double km;
  final double litros;

  /// Si `true`, los `litros` y `km` corresponden al período pedido
  /// (calculados como diferencia de snapshots). Si `false`, son el
  /// total acumulado del vehículo y el reporte los marca con
  /// "S/D (acum.)" para que el admin lo distinga.
  final bool esPeriodo;

  final String ultimaSync;
  final bool conectado;

  const _FilaConsumo({
    required this.patente,
    required this.tipo,
    required this.marca,
    required this.modelo,
    required this.vin,
    required this.empresa,
    required this.km,
    required this.litros,
    required this.esPeriodo,
    required this.ultimaSync,
    required this.conectado,
  });

  /// Consumo en L/100km — métrica estándar de flotas (cuántos litros
  /// se gastan cada 100 km). Cuanto más bajo, más eficiente. Tractores
  /// cargados típicamente caen en 30-40 L/100km.
  ///
  /// Devuelve 0 si km == 0 (vehículo parado, evita división por cero).
  double get consumoLPor100Km => km > 0 ? (litros / km) * 100.0 : 0.0;

  factory _FilaConsumo.from({
    required String patente,
    required Map<String, dynamic> data,
    required dynamic volvoData,
    required List<_Snapshot> historicos,
    required DateTime desde,
    required DateTime hasta,
  }) {
    // Default = acumulado (fallback). Si después detectamos que hay
    // suficiente histórico para calcular período real, lo reemplazamos.
    var km = (data['KM_ACTUAL'] ?? 0.0).toDouble();
    var litros = 0.0;
    var esPeriodo = false;

    if (volvoData != null && volvoData['accumulatedData'] != null) {
      litros = (volvoData['accumulatedData']['totalFuelConsumption'] ?? 0.0)
          .toDouble();
    }

    // Si hay al menos 2 snapshots (uno antes/igual a `desde` y otro
    // antes/igual a `hasta`), podemos calcular consumo del período.
    // Si solo hay uno, la unidad recién arrancó tracking y queda como
    // acumulado.
    if (historicos.isNotEmpty) {
      _Snapshot? inicio;
      _Snapshot? fin;
      for (final s in historicos) {
        if (!s.fecha.isAfter(desde)) inicio = s; // ≤ desde
        if (!s.fecha.isAfter(hasta)) fin = s; // ≤ hasta
      }
      // Si no hay snapshot anterior a `desde`, tomamos el primero
      // disponible como inicio (la unidad arrancó dentro del rango).
      // Eso da un consumo "casi del período" pero conviene marcarlo.
      inicio ??= historicos.first;
      if (fin != null && fin.fecha.isAfter(inicio.fecha)) {
        final litrosPeriodo = (fin.litros - inicio.litros)
            .clamp(0.0, double.infinity)
            .toDouble();
        final kmPeriodo =
            (fin.km - inicio.km).clamp(0.0, double.infinity).toDouble();
        // Aceptamos el período aunque la diferencia sea 0: "vehículo
        // parado" en el rango (sábado/domingo/feriado/taller) es info
        // válida y debe reportarse como 0 km / 0 L. Antes caíamos al
        // fallback acumulado que mostraba el total histórico del
        // vehículo desde su fabricación — info misleading para un
        // reporte de período.
        litros = litrosPeriodo;
        km = kmPeriodo;
        esPeriodo = true;
      }
    }

    var ultimaSync = '-';
    if (volvoData != null) {
      final ts = (volvoData['triggerTimestamp'] ??
              volvoData['samplingTime'] ??
              '')
          .toString();
      if (ts.isNotEmpty) {
        final dt = DateTime.tryParse(ts);
        if (dt != null) {
          ultimaSync = DateFormat('dd/MM HH:mm').format(dt.toLocal());
        }
      }
    }

    return _FilaConsumo(
      patente: patente,
      tipo: (data['TIPO'] ?? '').toString(),
      marca: (data['MARCA'] ?? '').toString(),
      modelo: (data['MODELO'] ?? '').toString(),
      vin: (data['VIN'] ?? '').toString().toUpperCase(),
      empresa: (data['EMPRESA'] ?? '').toString(),
      km: km,
      litros: litros,
      esPeriodo: esPeriodo,
      ultimaSync: ultimaSync,
      conectado: volvoData != null,
    );
  }
}

// =============================================================================
// COMPONENTES DEL DIALOG
// =============================================================================

class _LabelSeccion extends StatelessWidget {
  final String texto;
  const _LabelSeccion(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        texto.toUpperCase(),
        style: const TextStyle(
          color: Colors.greenAccent,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.3,
        ),
      ),
    );
  }
}

// =============================================================================
// PRESETS RÁPIDOS DE RANGO
// =============================================================================
//
// Los rangos más comunes que pide un admin sin tener que navegar el
// calendario. Si la fecha actual cae dentro del preset y `desde`/`hasta`
// matchean, mostramos el chip resaltado para que el admin sepa qué
// preset está activo.

class _PresetRango {
  final String label;
  final DateTime desde;
  final DateTime hasta;
  const _PresetRango(this.label, this.desde, this.hasta);
}

List<_PresetRango> _presetsRangos() {
  final hoy = DateTime.now();
  final inicioHoy = DateTime(hoy.year, hoy.month, hoy.day);
  final inicioSemana =
      inicioHoy.subtract(Duration(days: inicioHoy.weekday - 1));
  final inicioMesActual = DateTime(hoy.year, hoy.month, 1);
  final inicioMesPasado = DateTime(hoy.year, hoy.month - 1, 1);
  final finMesPasado = DateTime(hoy.year, hoy.month, 1)
      .subtract(const Duration(days: 1));
  return [
    _PresetRango('Hoy', inicioHoy, inicioHoy),
    _PresetRango('Esta semana', inicioSemana, inicioHoy),
    _PresetRango('Mes actual', inicioMesActual, inicioHoy),
    _PresetRango('Mes pasado', inicioMesPasado, finMesPasado),
    _PresetRango(
        'Últimos 7 días', inicioHoy.subtract(const Duration(days: 6)), inicioHoy),
    _PresetRango(
        'Últimos 30 días', inicioHoy.subtract(const Duration(days: 29)), inicioHoy),
  ];
}

bool _esPresetActivo(_PresetRango p, DateTime desde, DateTime hasta) {
  bool eq(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  return eq(p.desde, desde) && eq(p.hasta, hasta);
}

class _ChipPreset extends StatelessWidget {
  final String label;
  final bool activo;
  final VoidCallback onTap;
  const _ChipPreset({
    required this.label,
    required this.activo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = activo ? Colors.greenAccent : Colors.white54;
    final bg = activo
        ? Colors.greenAccent.withAlpha(40)
        : Colors.white.withAlpha(15);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withAlpha(120), width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: activo ? FontWeight.bold : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

/// Un solo botón que abre `showDateRangePicker` de Material —
/// calendario unificado donde el admin marca primero la fecha de
/// inicio y después la de fin en el mismo flow. UX mejor que dos
/// pickers separados porque ve los dos extremos del rango en el
/// mismo calendario.
class _BotonRangoFecha extends StatelessWidget {
  final DateTime desde;
  final DateTime hasta;
  final void Function(DateTime desde, DateTime hasta) onPick;

  const _BotonRangoFecha({
    required this.desde,
    required this.hasta,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy');
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final hoy = DateTime.now();
        final firstDate = DateTime(hoy.year - 2, 1, 1);
        final lastDate = hoy.add(const Duration(days: 1));

        // Usamos DOS showDatePicker en secuencia (no showDateRangePicker)
        // porque este último en Windows abre con scroll vertical de
        // meses sin flechas ◀ ▶ visibles. showDatePicker con modo
        // `calendar` SIEMPRE tiene flechas para navegar mes a mes,
        // que es lo que el admin espera.
        //
        // Flow: 1) elegís fecha de inicio → 2) elegís fecha de fin
        // (con firstDate = inicio para evitar rangos invertidos).

        // Paso 1: fecha de inicio.
        final desdePicked = await showDatePicker(
          context: context,
          initialDate: desde,
          firstDate: firstDate,
          lastDate: lastDate,
          locale: const Locale('es', 'AR'),
          initialEntryMode: DatePickerEntryMode.calendar,
          helpText: 'Fecha DESDE (inicio del rango)',
          confirmText: 'SIGUIENTE',
          cancelText: 'CANCELAR',
        );
        if (desdePicked == null) return;
        if (!context.mounted) return;

        // Paso 2: fecha de fin. firstDate = desdePicked para evitar
        // que el admin elija un fin anterior al inicio (rango inválido).
        final hastaInicial =
            hasta.isBefore(desdePicked) ? desdePicked : hasta;
        final hastaPicked = await showDatePicker(
          context: context,
          initialDate: hastaInicial,
          firstDate: desdePicked,
          lastDate: lastDate,
          locale: const Locale('es', 'AR'),
          initialEntryMode: DatePickerEntryMode.calendar,
          helpText: 'Fecha HASTA (fin del rango)',
          confirmText: 'CONFIRMAR',
          cancelText: 'CANCELAR',
        );
        if (hastaPicked == null) return;

        onPick(desdePicked, hastaPicked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: Colors.greenAccent.withAlpha(120), width: 1.5),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.date_range,
              color: Colors.greenAccent,
              size: 26,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'RANGO DE FECHAS',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${fmt.format(desde)}  a  ${fmt.format(hasta)}',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.edit_calendar,
              color: Colors.white54,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

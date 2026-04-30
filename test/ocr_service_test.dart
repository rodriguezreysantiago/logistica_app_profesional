import 'package:flutter_test/flutter_test.dart';
import 'package:logistica_app_profesional/shared/utils/ocr_service.dart';

void main() {
  group('OcrService.extraerFechaMasLejana', () {
    test('devuelve null para texto vacío', () {
      expect(OcrService.extraerFechaMasLejana(''), isNull);
    });

    test('devuelve null para texto sin fechas', () {
      expect(
        OcrService.extraerFechaMasLejana('Esto es un carnet sin fechas'),
        isNull,
      );
    });

    test('extrae una fecha en formato DD/MM/YYYY', () {
      final fecha = OcrService.extraerFechaMasLejana(
        'Vencimiento: 15/12/2027',
      );
      expect(fecha, isNotNull);
      expect(fecha!.year, 2027);
      expect(fecha.month, 12);
      expect(fecha.day, 15);
    });

    test('extrae una fecha en formato DD-MM-YYYY', () {
      final fecha = OcrService.extraerFechaMasLejana(
        'Válido hasta 03-08-2026',
      );
      expect(fecha, isNotNull);
      expect(fecha!.day, 3);
      expect(fecha.month, 8);
      expect(fecha.year, 2026);
    });

    test('extrae una fecha en formato DD.MM.YYYY', () {
      final fecha = OcrService.extraerFechaMasLejana('Expira: 30.06.2026');
      expect(fecha, isNotNull);
      expect(fecha!.day, 30);
      expect(fecha.month, 6);
      expect(fecha.year, 2026);
    });

    test('cuando hay varias fechas, devuelve la más lejana', () {
      // En un comprobante típico hay fecha de emisión Y fecha de
      // vencimiento — queremos la del vencimiento (la más futura).
      final fecha = OcrService.extraerFechaMasLejana(
        'Emitido: 01/01/2026\nVence: 31/12/2030',
      );
      expect(fecha, isNotNull);
      expect(fecha!.year, 2030);
      expect(fecha.month, 12);
      expect(fecha.day, 31);
    });

    test('rechaza fechas con mes inválido (>12)', () {
      expect(
        OcrService.extraerFechaMasLejana('15/13/2027'),
        isNull,
      );
    });

    test('rechaza fechas con día inválido (>31)', () {
      expect(
        OcrService.extraerFechaMasLejana('32/05/2027'),
        isNull,
      );
    });

    test('rechaza fechas inexistentes (31 de febrero)', () {
      // Catch al rollover de DateTime — 31/02 no es válido aunque los
      // números individuales lo sean.
      expect(
        OcrService.extraerFechaMasLejana('31/02/2027'),
        isNull,
      );
    });

    test('rechaza años < 2020', () {
      // Un comprobante de trámite no tiene años tan viejos — si los
      // detecta es probablemente un código de control mal interpretado.
      expect(
        OcrService.extraerFechaMasLejana('Reg N° 15/06/1985'),
        isNull,
      );
    });

    test('rechaza años > 2050', () {
      expect(
        OcrService.extraerFechaMasLejana('15/06/2080'),
        isNull,
      );
    });

    test('ignora fechas con año de 2 dígitos', () {
      // Para evitar confusión con códigos / fracciones.
      expect(
        OcrService.extraerFechaMasLejana('15/06/27'),
        isNull,
      );
    });

    test('mezcla formatos y elige la más futura', () {
      final fecha = OcrService.extraerFechaMasLejana(
        'Emisión 01-01-2026 / Caduca 15.07.2029 / Otra: 20/12/2027',
      );
      expect(fecha, isNotNull);
      expect(fecha!.year, 2029);
      expect(fecha.month, 7);
      expect(fecha.day, 15);
    });

    test('tolera fechas sin separador limpio alrededor', () {
      final fecha = OcrService.extraerFechaMasLejana(
        'Texto15/12/2027más texto',
      );
      // El \b al inicio del regex impide matchear en medio de palabras
      // — esto debería NO matchear.
      expect(fecha, isNull);
    });

    test('tolera fechas con día/mes en 1 dígito', () {
      final fecha = OcrService.extraerFechaMasLejana('Vence 5/6/2027');
      expect(fecha, isNotNull);
      expect(fecha!.day, 5);
      expect(fecha.month, 6);
      expect(fecha.year, 2027);
    });
  });
}

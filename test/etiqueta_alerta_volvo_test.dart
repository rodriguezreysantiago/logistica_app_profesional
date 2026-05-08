// Tests del helper de etiquetas de alertas Volvo.
//
// Foco: que `etiquetaAlertaVolvoFromDoc` resuelva el subtipo cuando el
// tipo principal es GENERIC. Reportado 2026-05-07 que la pantalla de
// admin mostraba todas las alertas como "Evento genérico" sin info.

import 'package:flutter_test/flutter_test.dart';
import 'package:coopertrans_movil/features/eco_driving/utils/etiquetas_alerta_volvo.dart';

void main() {
  group('etiquetaAlertaVolvo (versión simple)', () {
    test('tipo conocido devuelve etiqueta legible', () {
      expect(etiquetaAlertaVolvo('OVERSPEED'), 'Exceso de velocidad');
      expect(etiquetaAlertaVolvo('IDLING'), 'Motor en ralentí');
      expect(etiquetaAlertaVolvo('DAS'), 'Alerta de cansancio');
    });

    test('SEATBELT está mapeado (regresión 2026-05-07)', () {
      expect(etiquetaAlertaVolvo('SEATBELT'), contains('Cinturón'));
    });

    test('tipo desconocido cae al código crudo (no rompe)', () {
      expect(etiquetaAlertaVolvo('TIPO_DE_VOLVO_QUE_NO_EXISTE'),
          'TIPO_DE_VOLVO_QUE_NO_EXISTE');
    });
  });

  group('etiquetaAlertaVolvoFromDoc (resuelve subtipo)', () {
    test('GENERIC + detalle_generic.triggerType=SEATBELT → "Cinturón..."', () {
      final data = {
        'tipo': 'GENERIC',
        'detalle_generic': {'triggerType': 'SEATBELT'},
      };
      expect(etiquetaAlertaVolvoFromDoc(data), contains('Cinturón'));
    });

    test('GENERIC + detalle_generic.type=TELL_TALE → "Luz de tablero..."', () {
      final data = {
        'tipo': 'GENERIC',
        'detalle_generic': {'type': 'TELL_TALE'},
      };
      expect(etiquetaAlertaVolvoFromDoc(data), contains('Luz de tablero'));
    });

    test('priorita triggerType sobre type cuando ambos están', () {
      final data = {
        'tipo': 'GENERIC',
        'detalle_generic': {'triggerType': 'SEATBELT', 'type': 'TELL_TALE'},
      };
      expect(etiquetaAlertaVolvoFromDoc(data), contains('Cinturón'));
    });

    test('GENERIC sin detalle → "Evento genérico" (fallback)', () {
      final data = {'tipo': 'GENERIC'};
      expect(etiquetaAlertaVolvoFromDoc(data), 'Evento genérico');
    });

    test('GENERIC con detalle vacío → "Evento genérico"', () {
      final data = {
        'tipo': 'GENERIC',
        'detalle_generic': {'triggerType': '', 'type': null},
      };
      expect(etiquetaAlertaVolvoFromDoc(data), 'Evento genérico');
    });

    test('subtipo desconocido cae al código crudo del subtipo', () {
      final data = {
        'tipo': 'GENERIC',
        'detalle_generic': {'triggerType': 'NUEVO_DE_VOLVO'},
      };
      expect(etiquetaAlertaVolvoFromDoc(data), 'NUEVO_DE_VOLVO');
    });

    test('tipo no-GENERIC ignora detalle_generic y usa tipo directo', () {
      final data = {
        'tipo': 'OVERSPEED',
        'detalle_generic': {'triggerType': 'SEATBELT'},
      };
      expect(etiquetaAlertaVolvoFromDoc(data), 'Exceso de velocidad');
    });

    test('tipo en minúsculas se normaliza a mayúsculas', () {
      final data = {
        'tipo': 'generic',
        'detalle_generic': {'triggerType': 'seatbelt'},
      };
      expect(etiquetaAlertaVolvoFromDoc(data), contains('Cinturón'));
    });

    test('data sin tipo cae al código crudo vacío', () {
      final data = <String, dynamic>{};
      expect(etiquetaAlertaVolvoFromDoc(data), '');
    });
  });
}

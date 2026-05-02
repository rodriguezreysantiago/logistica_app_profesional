import 'package:flutter_test/flutter_test.dart';
import 'package:logistica_app_profesional/shared/widgets/vencimiento_badge.dart';

void main() {
  group('calcularEstadoVencimiento', () {
    test('sin fecha cargada → sinFecha (gris, neutro)', () {
      expect(
        calcularEstadoVencimiento(null, tieneFecha: false),
        VencimientoEstado.sinFecha,
      );
    });

    test(
      'fecha cargada pero no parseable → invalida (rojo, llamativo)',
      () {
        // Regression test del bug crítico: una fecha tipeada mal en
        // Firestore Console (ej. "30/13/2026") devolvía dias=999 desde
        // calcularDiasRestantes y el badge la pintaba "OK" verde.
        // Ahora dias=null Y tieneFecha=true → invalida → badge rojo.
        expect(
          calcularEstadoVencimiento(null, tieneFecha: true),
          VencimientoEstado.invalida,
        );
      },
    );

    test('días negativos → vencido', () {
      expect(
        calcularEstadoVencimiento(-1, tieneFecha: true),
        VencimientoEstado.vencido,
      );
      expect(
        calcularEstadoVencimiento(-100, tieneFecha: true),
        VencimientoEstado.vencido,
      );
    });

    test('vence hoy (0 días) → critico', () {
      expect(
        calcularEstadoVencimiento(0, tieneFecha: true),
        VencimientoEstado.critico,
      );
    });

    test('vence en ≤14 días → critico', () {
      expect(
        calcularEstadoVencimiento(1, tieneFecha: true),
        VencimientoEstado.critico,
      );
      expect(
        calcularEstadoVencimiento(14, tieneFecha: true),
        VencimientoEstado.critico,
      );
    });

    test('vence en 15-30 días → proximo', () {
      expect(
        calcularEstadoVencimiento(15, tieneFecha: true),
        VencimientoEstado.proximo,
      );
      expect(
        calcularEstadoVencimiento(30, tieneFecha: true),
        VencimientoEstado.proximo,
      );
    });

    test('vence en >30 días → ok', () {
      expect(
        calcularEstadoVencimiento(31, tieneFecha: true),
        VencimientoEstado.ok,
      );
      expect(
        calcularEstadoVencimiento(365, tieneFecha: true),
        VencimientoEstado.ok,
      );
    });

    test(
      'tieneFecha=false prevalece sobre dias != null (defensivo)',
      () {
        // Si por alguna razón un caller pasa dias != null Y tieneFecha=false
        // (mensaje contradictorio), gana sinFecha. Es la opción menos
        // sorprendente: si el caller dice "no hay fecha", confiamos.
        expect(
          calcularEstadoVencimiento(10, tieneFecha: false),
          VencimientoEstado.sinFecha,
        );
      },
    );
  });

  group('VencimientoEstado.color', () {
    test('vencido e invalida comparten rojo (ambos requieren acción)', () {
      // Decisión de diseño: invalida visualmente debe gritar fuerte.
      // No queremos un naranja tibio que el admin pase de largo.
      expect(
        VencimientoEstado.invalida.color,
        VencimientoEstado.vencido.color,
      );
    });

    test('sinFecha es neutro (no rojo, no naranja)', () {
      expect(
        VencimientoEstado.sinFecha.color,
        isNot(VencimientoEstado.vencido.color),
      );
      expect(
        VencimientoEstado.sinFecha.color,
        isNot(VencimientoEstado.critico.color),
      );
    });
  });
}

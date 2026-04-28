import 'package:flutter_test/flutter_test.dart';
import 'package:logistica_app_profesional/features/expirations/services/aviso_vencimiento_builder.dart';
import 'package:logistica_app_profesional/features/expirations/widgets/vencimiento_item.dart';

VencimientoItem _itemEmpleado({
  required int dias,
  String tipoDoc = 'Licencia',
  String fecha = '2026-12-31',
}) {
  return VencimientoItem(
    docId: '12345678',
    coleccion: 'EMPLEADOS',
    titulo: 'PEREZ JUAN',
    tipoDoc: tipoDoc,
    campoBase: 'LICENCIA_DE_CONDUCIR',
    fecha: fecha,
    dias: dias,
    urlArchivo: null,
    storagePath: 'EMPLEADOS_DOCS',
  );
}

VencimientoItem _itemVehiculo({
  required int dias,
  String tipoDoc = 'RTO',
  String fecha = '2026-12-31',
  String titulo = 'TRACTOR - AB123CD',
}) {
  return VencimientoItem(
    docId: 'AB123CD',
    coleccion: 'VEHICULOS',
    titulo: titulo,
    tipoDoc: tipoDoc,
    campoBase: 'RTO',
    fecha: fecha,
    dias: dias,
    urlArchivo: null,
    storagePath: 'VEHICULOS_DOCS',
  );
}

void main() {
  group('AvisoVencimientoBuilder.build', () {
    test('todos los mensajes terminan con la firma automática', () {
      // La firma es contractual — los avisos automáticos deben quedar
      // diferenciados de un mensaje individual del admin.
      const firma =
          '_Mensaje automático del sistema de gestión S.M.A.R.T. Logística._\n'
          '_Para responder o gestionar el trámite, comunicate con la oficina._';

      for (final dias in [-30, -1, 0, 5, 10, 20, 45]) {
        final msg = AvisoVencimientoBuilder.build(
          item: _itemEmpleado(dias: dias),
          destinatarioNombre: 'Juan',
        );
        expect(msg, endsWith(firma),
            reason: 'Sin firma cuando dias=$dias');
      }
    });

    test('saluda con primer nombre cuando se provee', () {
      final msg = AvisoVencimientoBuilder.build(
        item: _itemEmpleado(dias: 5),
        destinatarioNombre: 'Juan',
      );
      expect(msg, startsWith('Hola Juan'));
    });

    test('saluda con "Hola" genérico si no hay nombre', () {
      final msg = AvisoVencimientoBuilder.build(
        item: _itemEmpleado(dias: 5),
        destinatarioNombre: null,
      );
      expect(msg, startsWith('Hola.'));
      expect(msg, isNot(contains('null')));
    });

    test('mensaje de >30 días es preventivo', () {
      final msg = AvisoVencimientoBuilder.build(
        item: _itemEmpleado(dias: 45),
        destinatarioNombre: 'Juan',
      );
      expect(msg.toLowerCase(), contains('preventivo'));
    });

    test('mensaje de 8-15 días sugiere empezar el trámite', () {
      final msg = AvisoVencimientoBuilder.build(
        item: _itemEmpleado(dias: 12),
      );
      expect(msg.toLowerCase(), contains('renovación'));
    });

    test('mensaje de ≤7 días lo marca como urgente', () {
      final msg = AvisoVencimientoBuilder.build(
        item: _itemEmpleado(dias: 3),
      );
      expect(msg.toLowerCase(), contains('importante'));
      expect(msg, contains('3 días'));
    });

    test('mensaje de 1 día usa singular "día" sin "s"', () {
      final msg = AvisoVencimientoBuilder.build(
        item: _itemEmpleado(dias: 1),
      );
      expect(msg, contains('1 día'));
      expect(msg, isNot(contains('1 días')));
    });

    test('mensaje del día 0 dice HOY', () {
      final msg = AvisoVencimientoBuilder.build(
        item: _itemEmpleado(dias: 0),
      );
      expect(msg, contains('HOY'));
    });

    test('mensaje vencido de 1 día dice "ayer"', () {
      final msg = AvisoVencimientoBuilder.build(
        item: _itemEmpleado(dias: -1),
      );
      expect(msg.toLowerCase(), contains('ayer'));
    });

    test('mensaje vencido de >1 día dice "hace N días"', () {
      final msg = AvisoVencimientoBuilder.build(
        item: _itemEmpleado(dias: -10),
      );
      expect(msg, contains('hace 10 días'));
    });

    test('para vehículo, extrae patente del titulo', () {
      final msg = AvisoVencimientoBuilder.build(
        item: _itemVehiculo(
          dias: 5,
          titulo: 'TRACTOR - AB123CD',
        ),
        destinatarioNombre: 'Juan',
      );
      expect(msg, contains('AB123CD'));
    });

    test('para vehículo sin patrón "TIPO - patente", usa docId', () {
      final msg = AvisoVencimientoBuilder.build(
        item: _itemVehiculo(
          dias: 5,
          titulo: 'Sin patrón estándar',
        ),
      );
      // Si el regex no matchea, debería caer al docId
      expect(msg, contains('AB123CD'));
    });

    test('para chofer, menciona el tipo de documento en minúsculas', () {
      final msg = AvisoVencimientoBuilder.build(
        item: _itemEmpleado(dias: 10, tipoDoc: 'Licencia'),
      );
      expect(msg, contains('tu licencia'));
    });
  });
}

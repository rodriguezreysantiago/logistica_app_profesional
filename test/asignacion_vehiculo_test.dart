import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logistica_app_profesional/features/asignaciones/models/asignacion_vehiculo.dart';

// Helper local: el test trabaja con maps + id en vez de un fake de
// `DocumentSnapshot` (que es sealed en versiones nuevas de Firestore
// y emite warning si se implementa).
AsignacionVehiculo _parsear(String id, Map<String, dynamic>? data) =>
    AsignacionVehiculo.fromMap(id, data);

/// Tests del modelo `AsignacionVehiculo`. NO cubren la lógica de la
/// transaction ni del lookup por fecha en `AsignacionVehiculoService`
/// — eso requiere emulador o `fake_cloud_firestore`. Si algún día se
/// agrega esa dep, sumar acá los tests del servicio. Por ahora, el
/// servicio se valida en runtime contra el proyecto de test.
void main() {
  group('AsignacionVehiculo.esActiva', () {
    test('hasta == null → activa', () {
      final a = AsignacionVehiculo(
        id: 'x',
        vehiculoId: 'ABC123',
        choferDni: '111',
        choferNombre: 'Juan',
        desde: DateTime(2026, 5, 1),
        hasta: null,
        asignadoPorDni: '222',
        asignadoPorNombre: 'Admin',
        motivo: null,
      );
      expect(a.esActiva, isTrue);
    });

    test('hasta != null → cerrada', () {
      final a = AsignacionVehiculo(
        id: 'x',
        vehiculoId: 'ABC123',
        choferDni: '111',
        choferNombre: 'Juan',
        desde: DateTime(2026, 5, 1),
        hasta: DateTime(2026, 5, 10),
        asignadoPorDni: '222',
        asignadoPorNombre: 'Admin',
        motivo: null,
      );
      expect(a.esActiva, isFalse);
    });
  });

  group('AsignacionVehiculo.diasDuracion', () {
    test('asignación activa cuenta hasta hoy', () {
      final hace5dias = DateTime.now().subtract(const Duration(days: 5));
      final a = AsignacionVehiculo(
        id: 'x',
        vehiculoId: 'ABC123',
        choferDni: '111',
        choferNombre: null,
        desde: hace5dias,
        hasta: null,
        asignadoPorDni: '222',
        asignadoPorNombre: null,
        motivo: null,
      );
      // Permitimos +/-1 día por la diferencia de horas en el mismo día.
      expect(a.diasDuracion(), inInclusiveRange(4, 5));
    });

    test('asignación cerrada cuenta entre desde y hasta', () {
      final a = AsignacionVehiculo(
        id: 'x',
        vehiculoId: 'ABC123',
        choferDni: '111',
        choferNombre: null,
        desde: DateTime(2026, 5, 1),
        hasta: DateTime(2026, 5, 11),
        asignadoPorDni: '222',
        asignadoPorNombre: null,
        motivo: null,
      );
      expect(a.diasDuracion(), 10);
    });

    test('mismo día devuelve 0', () {
      final hoy = DateTime.now();
      final a = AsignacionVehiculo(
        id: 'x',
        vehiculoId: 'ABC123',
        choferDni: '111',
        choferNombre: null,
        desde: hoy,
        hasta: hoy.add(const Duration(hours: 2)),
        asignadoPorDni: '222',
        asignadoPorNombre: null,
        motivo: null,
      );
      expect(a.diasDuracion(), 0);
    });
  });

  group('AsignacionVehiculo.fromMap', () {
    test('parsea todos los campos del map', () {
      final desde = DateTime(2026, 5, 1, 10, 30);
      final hasta = DateTime(2026, 5, 5, 14, 0);
      final a = _parsear('asignacion-123', {
        'vehiculo_id': 'ABC123',
        'chofer_dni': '11111111',
        'chofer_nombre': 'Pérez Juan',
        'desde': Timestamp.fromDate(desde),
        'hasta': Timestamp.fromDate(hasta),
        'asignado_por_dni': '22222222',
        'asignado_por_nombre': 'Admin Vecchi',
        'motivo': 'rotación semanal',
      });

      expect(a.id, 'asignacion-123');
      expect(a.vehiculoId, 'ABC123');
      expect(a.choferDni, '11111111');
      expect(a.choferNombre, 'Pérez Juan');
      expect(a.desde, desde);
      expect(a.hasta, hasta);
      expect(a.asignadoPorDni, '22222222');
      expect(a.asignadoPorNombre, 'Admin Vecchi');
      expect(a.motivo, 'rotación semanal');
      expect(a.esActiva, isFalse);
    });

    test('hasta == null → asignación queda activa', () {
      final a = _parsear('x', {
        'vehiculo_id': 'XYZ999',
        'chofer_dni': '11111111',
        'desde': Timestamp.fromDate(DateTime(2026, 5, 1)),
        'hasta': null,
        'asignado_por_dni': '22222222',
      });
      expect(a.esActiva, isTrue);
      expect(a.hasta, isNull);
    });

    test('campos opcionales ausentes → null sin romper', () {
      final a = _parsear('x', {
        'vehiculo_id': 'XYZ999',
        'chofer_dni': '11111111',
        'desde': Timestamp.fromDate(DateTime(2026, 5, 1)),
        'hasta': null,
        'asignado_por_dni': '22222222',
        // chofer_nombre, asignado_por_nombre, motivo no presentes
      });
      expect(a.choferNombre, isNull);
      expect(a.asignadoPorNombre, isNull);
      expect(a.motivo, isNull);
    });

    test('data == null devuelve un objeto con defaults seguros', () {
      // Defensa contra docs corruptos: en lugar de crashear, queda con
      // strings vacíos. La UI los muestra como "DNI " o similar y el
      // admin puede investigar.
      final a = _parsear('x', null);
      expect(a.id, 'x');
      expect(a.vehiculoId, '');
      expect(a.choferDni, '');
    });
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logistica_app_profesional/features/asignaciones/models/asignacion_enganche.dart';

// Helper local: el test trabaja con maps + id en vez de un fake de
// `DocumentSnapshot` (que es sealed en versiones nuevas de Firestore
// y emite warning si se implementa).
AsignacionEnganche _parsear(String id, Map<String, dynamic>? data) =>
    AsignacionEnganche.fromMap(id, data);

/// Tests del modelo `AsignacionEnganche`. NO cubren la lógica de la
/// transaction ni del lookup por fecha en `AsignacionEngancheService`
/// — eso requiere emulador o `fake_cloud_firestore`. Espejo del patrón
/// de tests de `AsignacionVehiculo`.
void main() {
  group('AsignacionEnganche.esActiva', () {
    test('hasta == null → activa', () {
      final a = AsignacionEnganche(
        id: 'x',
        engancheId: 'BAT123',
        tractorId: 'TR456',
        tractorModelo: 'VOLVO FH 540',
        desde: DateTime(2026, 5, 1),
        hasta: null,
        asignadoPorDni: '222',
        asignadoPorNombre: 'Admin',
        motivo: null,
      );
      expect(a.esActiva, isTrue);
    });

    test('hasta != null → cerrada', () {
      final a = AsignacionEnganche(
        id: 'x',
        engancheId: 'BAT123',
        tractorId: 'TR456',
        tractorModelo: null,
        desde: DateTime(2026, 5, 1),
        hasta: DateTime(2026, 5, 10),
        asignadoPorDni: '222',
        asignadoPorNombre: 'Admin',
        motivo: null,
      );
      expect(a.esActiva, isFalse);
    });
  });

  group('AsignacionEnganche.diasDuracion', () {
    test('asignación activa cuenta hasta ahora', () {
      final hace5dias = DateTime.now().subtract(const Duration(days: 5));
      final a = AsignacionEnganche(
        id: 'x',
        engancheId: 'BAT123',
        tractorId: 'TR456',
        tractorModelo: null,
        desde: hace5dias,
        hasta: null,
        asignadoPorDni: '222',
        asignadoPorNombre: null,
        motivo: null,
      );
      expect(a.diasDuracion(), greaterThanOrEqualTo(4));
      expect(a.diasDuracion(), lessThanOrEqualTo(5));
    });

    test('asignación cerrada usa hasta', () {
      final a = AsignacionEnganche(
        id: 'x',
        engancheId: 'BAT123',
        tractorId: 'TR456',
        tractorModelo: null,
        desde: DateTime(2026, 5, 1),
        hasta: DateTime(2026, 5, 8),
        asignadoPorDni: '222',
        asignadoPorNombre: null,
        motivo: null,
      );
      expect(a.diasDuracion(), 7);
    });
  });

  group('AsignacionEnganche.fromMap — campos completos', () {
    test('parsea todos los campos', () {
      final a = _parsear('docId123', {
        'enganche_id': 'BAT123',
        'tractor_id': 'TR456',
        'tractor_modelo': 'VOLVO FH 540',
        'desde': Timestamp.fromDate(DateTime(2026, 5, 1, 10, 0)),
        'hasta': Timestamp.fromDate(DateTime(2026, 5, 8, 18, 0)),
        'asignado_por_dni': 'admin1',
        'asignado_por_nombre': 'Santiago',
        'motivo': 'rotación de carga',
      });
      expect(a.id, 'docId123');
      expect(a.engancheId, 'BAT123');
      expect(a.tractorId, 'TR456');
      expect(a.tractorModelo, 'VOLVO FH 540');
      expect(a.desde, DateTime(2026, 5, 1, 10, 0));
      expect(a.hasta, DateTime(2026, 5, 8, 18, 0));
      expect(a.asignadoPorDni, 'admin1');
      expect(a.asignadoPorNombre, 'Santiago');
      expect(a.motivo, 'rotación de carga');
    });
  });

  group('AsignacionEnganche.fromMap — defensas', () {
    test('data null → defaults sin romper', () {
      final a = _parsear('docId', null);
      expect(a.id, 'docId');
      expect(a.engancheId, '');
      expect(a.tractorId, '');
      expect(a.tractorModelo, isNull);
      expect(a.hasta, isNull);
    });

    test('campos faltantes → defaults sin romper', () {
      final a = _parsear('docId', {
        'enganche_id': 'BAT123',
        // sin tractor_id, sin desde, etc.
      });
      expect(a.engancheId, 'BAT123');
      expect(a.tractorId, '');
      expect(a.tractorModelo, isNull);
    });

    test('hasta como null explícito → null', () {
      final a = _parsear('docId', {
        'enganche_id': 'BAT123',
        'tractor_id': 'TR456',
        'desde': Timestamp.fromDate(DateTime(2026, 5, 1)),
        'hasta': null,
      });
      expect(a.hasta, isNull);
      expect(a.esActiva, isTrue);
    });

    test('campos numéricos como string (corrupción) → toString graceful', () {
      final a = _parsear('docId', {
        'enganche_id': 12345, // integer en lugar de string
        'tractor_id': 67890,
        'desde': Timestamp.fromDate(DateTime(2026, 5, 1)),
      });
      expect(a.engancheId, '12345');
      expect(a.tractorId, '67890');
    });
  });
}

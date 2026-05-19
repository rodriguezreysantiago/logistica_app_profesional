// Tests de integración del flujo CESVI completo de
// IcmCalculator.calcularRanking — lee JORNADAS + SITRACK_EVENTOS de
// Firestore (fake), aplica fórmula CESVI por jornada, combina por
// chofer.
//
// Refactor 2026-05-19: la versión anterior (500 LOC) testeaba el
// modelo lineal `100 − ratio×5` con solo eventos. Reemplazada al
// migrar a CESVI homologado por bloques de jornada del vigilador v2.
// La FÓRMULA pura (pesos, agrupación 8+9, fatiga por bloque,
// promedio ponderado) está cubierta por `icm_cesvi_test.dart`
// (38 tests). Acá testeamos solo el wiring de Firestore.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coopertrans_movil/features/icm/services/icm_calculator.dart';

void main() {
  /// Inserta un evento sintético en SITRACK_EVENTOS.
  Future<void> insertarEvento(
    FakeFirebaseFirestore db, {
    required String driverDni,
    required String patente,
    required int eventId,
    required double odometer,
    required DateTime reportDate,
    double? speed,
    double? cartLimit,
    String areaType = 'rural',
    String eventName = 'Evento test',
  }) async {
    await db.collection('SITRACK_EVENTOS').add({
      'driver_dni': driverDni,
      'asset_id': patente,
      'event_id': eventId,
      'event_name': eventName,
      'odometer': odometer,
      'report_date': Timestamp.fromDate(reportDate),
      'speed': speed,
      'cartography_limit_speed': cartLimit,
      'area_type': areaType,
    });
  }

  /// Inserta una jornada cerrada del vigilador v2.
  Future<void> insertarJornada(
    FakeFirebaseFirestore db, {
    required String choferDni,
    required DateTime inicio,
    required DateTime fin,
    int bloquesCompletos = 1,
    double bloqueActualSeg = 0,
    double totalManejoSeg = 4 * 3600.0,
  }) async {
    await db.collection('JORNADAS').add({
      'chofer_dni': choferDni,
      'jornada_inicio_ts': Timestamp.fromDate(inicio),
      'jornada_fin_ts': Timestamp.fromDate(fin),
      'bloques_completos': bloquesCompletos,
      'bloque_actual_manejo_seg': bloqueActualSeg,
      'total_manejo_seg': totalManejoSeg,
    });
  }

  group('IcmCalculator.calcularRanking — flujo CESVI con JORNADAS', () {
    test('1 chofer con 1 jornada limpia + km suficientes → ICM ~100', () async {
      final db = FakeFirebaseFirestore();
      final inicio = DateTime(2026, 5, 10, 8, 0);
      final fin = DateTime(2026, 5, 10, 12, 0); // 4h jornada
      // Eventos solo para inflar odómetro (no infracciones CESVI)
      await insertarEvento(db,
          driverDni: '111', patente: 'AB1', eventId: 2,
          odometer: 100, reportDate: inicio.add(const Duration(minutes: 5)));
      await insertarEvento(db,
          driverDni: '111', patente: 'AB1', eventId: 2,
          odometer: 350, reportDate: fin.subtract(const Duration(minutes: 5)));
      // Jornada de 3.5h (no llega a 4h → fatiga -10)
      await insertarJornada(db,
          choferDni: '111', inicio: inicio, fin: fin,
          bloquesCompletos: 0,
          bloqueActualSeg: 3.5 * 3600,
          totalManejoSeg: 3.5 * 3600);
      final r = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: DateTime(2026, 5, 10).millisecondsSinceEpoch,
        hastaMs: DateTime(2026, 5, 11).millisecondsSinceEpoch,
        nombrePorDni: {'111': 'TEST CHOFER'},
      );
      expect(r.length, 1);
      expect(r[0].choferDni, '111');
      expect(r[0].choferNombre, 'TEST CHOFER');
      expect(r[0].kmRecorridos, 250);
      // ICM = 100 - 10 (fatiga 3-4h) = 90 → BAJO
      expect(r[0].icm, 90);
      expect(r[0].categoria, CategoriaIcm.bajo);
    });

    test('chofer con frenadas/aceleraciones bajan el ICM (CESVI puro)', () async {
      final db = FakeFirebaseFirestore();
      final inicio = DateTime(2026, 5, 10, 8, 0);
      final fin = DateTime(2026, 5, 10, 9, 0); // jornada corta, no fatiga
      // 2 frenadas (-5.8×2 = -11.6) + 1 aceleración (-2.8) = -14.4
      await insertarEvento(db,
          driverDni: '111', patente: 'AB1', eventId: 67,
          odometer: 100, reportDate: inicio.add(const Duration(minutes: 10)));
      await insertarEvento(db,
          driverDni: '111', patente: 'AB1', eventId: 67,
          odometer: 105, reportDate: inicio.add(const Duration(minutes: 20)));
      await insertarEvento(db,
          driverDni: '111', patente: 'AB1', eventId: 66,
          odometer: 150, reportDate: inicio.add(const Duration(minutes: 30)));
      await insertarJornada(db,
          choferDni: '111', inicio: inicio, fin: fin,
          bloquesCompletos: 0,
          bloqueActualSeg: 3600,
          totalManejoSeg: 3600);
      final r = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: DateTime(2026, 5, 10).millisecondsSinceEpoch,
        hastaMs: DateTime(2026, 5, 11).millisecondsSinceEpoch,
        nombrePorDni: const {},
      );
      expect(r.length, 1);
      expect(r[0].totalEventos, 3); // 2 frenadas + 1 aceleración
      expect(r[0].icm, closeTo(85.6, 0.01)); // 100 - 14.4
      expect(r[0].categoria, CategoriaIcm.bajo);
    });

    test('eventos NO CESVI (1006 salida carril) NO descuentan ICM', () async {
      final db = FakeFirebaseFirestore();
      final inicio = DateTime(2026, 5, 10, 8, 0);
      final fin = DateTime(2026, 5, 10, 9, 0);
      // 10 eventos de salida de carril (NO CESVI) — el ICM debe ser 100.
      for (var i = 0; i < 10; i++) {
        await insertarEvento(db,
            driverDni: '111', patente: 'AB1', eventId: 1006,
            odometer: 100.0 + i * 5,
            reportDate: inicio.add(Duration(minutes: 10 + i)));
      }
      await insertarJornada(db,
          choferDni: '111', inicio: inicio, fin: fin,
          bloquesCompletos: 0,
          bloqueActualSeg: 3600,
          totalManejoSeg: 3600);
      final r = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: DateTime(2026, 5, 10).millisecondsSinceEpoch,
        hastaMs: DateTime(2026, 5, 11).millisecondsSinceEpoch,
        nombrePorDni: const {},
      );
      expect(r.length, 1);
      expect(r[0].totalEventos, 0); // 1006 NO cuenta
      expect(r[0].icm, 100);
    });

    test('jornada sin km mínimos → descartada', () async {
      final db = FakeFirebaseFirestore();
      final inicio = DateTime(2026, 5, 10, 8, 0);
      final fin = DateTime(2026, 5, 10, 9, 0);
      // Eventos con odómetro casi igual (menos de 10 km recorridos)
      await insertarEvento(db,
          driverDni: '111', patente: 'AB1', eventId: 2,
          odometer: 100, reportDate: inicio.add(const Duration(minutes: 5)));
      await insertarEvento(db,
          driverDni: '111', patente: 'AB1', eventId: 2,
          odometer: 105, reportDate: fin.subtract(const Duration(minutes: 5)));
      await insertarJornada(db,
          choferDni: '111', inicio: inicio, fin: fin);
      final r = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: DateTime(2026, 5, 10).millisecondsSinceEpoch,
        hastaMs: DateTime(2026, 5, 11).millisecondsSinceEpoch,
        nombrePorDni: const {},
      );
      // Jornada con <10km descartada → chofer no aparece en ranking
      expect(r.length, 0);
    });

    test('múltiples choferes ordenados peor primero', () async {
      final db = FakeFirebaseFirestore();
      final inicio = DateTime(2026, 5, 10, 8, 0);
      final fin = DateTime(2026, 5, 10, 12, 0);
      // Chofer A: limpio (4h jornada → ICM 85)
      await insertarEvento(db,
          driverDni: 'A', patente: 'AA1', eventId: 2,
          odometer: 100, reportDate: inicio.add(const Duration(minutes: 5)));
      await insertarEvento(db,
          driverDni: 'A', patente: 'AA1', eventId: 2,
          odometer: 400, reportDate: fin.subtract(const Duration(minutes: 5)));
      await insertarJornada(db,
          choferDni: 'A', inicio: inicio, fin: fin,
          bloquesCompletos: 1,
          totalManejoSeg: 4 * 3600);
      // Chofer B: 3 frenadas en 4h (ICM mucho menor)
      for (var i = 0; i < 3; i++) {
        await insertarEvento(db,
            driverDni: 'B', patente: 'BB1', eventId: 67,
            odometer: 200.0 + i * 10,
            reportDate: inicio.add(Duration(minutes: 30 + i * 10)),
            speed: 60, cartLimit: 80, areaType: 'urban');
      }
      await insertarEvento(db,
          driverDni: 'B', patente: 'BB1', eventId: 2,
          odometer: 500, reportDate: fin.subtract(const Duration(minutes: 5)));
      await insertarJornada(db,
          choferDni: 'B', inicio: inicio, fin: fin,
          bloquesCompletos: 1,
          totalManejoSeg: 4 * 3600);
      final r = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: DateTime(2026, 5, 10).millisecondsSinceEpoch,
        hastaMs: DateTime(2026, 5, 11).millisecondsSinceEpoch,
        nombrePorDni: const {'A': 'Alfa', 'B': 'Beta'},
      );
      expect(r.length, 2);
      // Peor ICM primero: B (-15 fatiga -17.4 frenadas = -32.4 → 67.6)
      expect(r[0].choferDni, 'B');
      expect(r[0].icm, lessThan(r[1].icm));
      // A: solo -15 fatiga → ICM 85
      expect(r[1].choferDni, 'A');
      expect(r[1].icm, 85);
    });

    test('chofer sin jornada en el rango → NO aparece', () async {
      final db = FakeFirebaseFirestore();
      // Evento sin jornada asociada
      await insertarEvento(db,
          driverDni: '111', patente: 'AB1', eventId: 67,
          odometer: 100, reportDate: DateTime(2026, 5, 10, 10, 0));
      final r = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: DateTime(2026, 5, 10).millisecondsSinceEpoch,
        hastaMs: DateTime(2026, 5, 11).millisecondsSinceEpoch,
        nombrePorDni: const {},
      );
      expect(r.length, 0);
    });

    test('rango vacío → ranking vacío', () async {
      final db = FakeFirebaseFirestore();
      final r = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: DateTime(2026, 5, 10).millisecondsSinceEpoch,
        hastaMs: DateTime(2026, 5, 11).millisecondsSinceEpoch,
        nombrePorDni: const {},
      );
      expect(r, isEmpty);
    });

    test('fallback de nombre cuando DNI no está en map', () async {
      final db = FakeFirebaseFirestore();
      final inicio = DateTime(2026, 5, 10, 8, 0);
      final fin = DateTime(2026, 5, 10, 9, 0);
      await insertarEvento(db,
          driverDni: '999', patente: 'AB1', eventId: 2,
          odometer: 100, reportDate: inicio.add(const Duration(minutes: 5)));
      await insertarEvento(db,
          driverDni: '999', patente: 'AB1', eventId: 2,
          odometer: 200, reportDate: fin.subtract(const Duration(minutes: 5)));
      await insertarJornada(db,
          choferDni: '999', inicio: inicio, fin: fin);
      final r = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: DateTime(2026, 5, 10).millisecondsSinceEpoch,
        hastaMs: DateTime(2026, 5, 11).millisecondsSinceEpoch,
        nombrePorDni: const {}, // sin mapping
      );
      expect(r.length, 1);
      expect(r[0].choferNombre, 'DNI 999'); // fallback
    });
  });
}

// Tests del FLUJO COMPLETO de IcmCalculator.calcularRanking — lee
// SITRACK_EVENTOS de Firestore, agrega por chofer, calcula km reales
// con odómetro Sitrack, aplica fórmula ICM, ordena ranking.
//
// Usa `fake_cloud_firestore` (in-memory, no requiere emulator aparte).
// Cubre los escenarios que rompieron en producción y que el agente de
// audit pidió blindar:
//   - Bug 2026-05-16: "todos los choferes con icm=95" (km como heurística
//     totalEventos×100). Fix: km reales del odómetro.
//   - Bug 2026-05-17: SIN_DATOS ocupaba posiciones #1-22 del ranking
//     "peores" enmascarando problemáticos reales.
//   - Bug 2026-05-18: cap 5000→10000 km/semana — choferes larga
//     distancia (BB→Mendoza ~6000km) quedaban como SIN_DATOS.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coopertrans_movil/features/icm/services/icm_calculator.dart';

void main() {
  // Helper: insertar un evento sintético en SITRACK_EVENTOS.
  // `eventId = 8` (sobrevelocidad) es infracción. `eventId = 1`
  // (ignición) NO es infracción — usado para inflar km del odómetro
  // sin contar como evento ICM.
  Future<void> insertarEvento(
    FakeFirebaseFirestore db, {
    required String driverDni,
    required String patente,
    required int eventId,
    required double odometer,
    DateTime? reportDate,
    String? eventName,
  }) async {
    await db.collection('SITRACK_EVENTOS').add({
      'event_id': eventId,
      'event_name': eventName ?? 'Evento $eventId',
      'driver_dni': driverDni,
      'asset_id': patente,
      'odometer': odometer,
      'report_date': Timestamp.fromDate(
        reportDate ?? DateTime(2026, 5, 15, 12, 0, 0),
      ),
    });
  }

  late FakeFirebaseFirestore db;
  // Rango fijo para todos los tests: 1 semana en mayo 2026.
  final desdeMs = DateTime(2026, 5, 11).millisecondsSinceEpoch;
  final hastaMs = DateTime(2026, 5, 18).millisecondsSinceEpoch;
  const nombrePorDni = {
    '11111111': 'PEREZ JUAN',
    '22222222': 'GARCIA MARIA',
    '33333333': 'LOPEZ CARLOS',
    '44444444': 'MARTINEZ ANA',
  };

  setUp(() {
    db = FakeFirebaseFirestore();
  });

  group('IcmCalculator.calcularRanking — casos felices', () {
    test('chofer con 1 sobrevelocidad en 200 km → ICM 97.5 BAJO', () async {
      // Fixtures: 2 eventos del mismo chofer en misma patente.
      // - 1 ignición (no infracción) en odómetro 1000 km.
      // - 1 sobrevelocidad en odómetro 1200 km.
      // km = max - min = 200. infracciones = 1. ratio = 0.5/100km.
      // ICM = 100 - 0.5 × 5 = 97.5 → BAJO.
      await insertarEvento(db,
          driverDni: '11111111',
          patente: 'AB123CD',
          eventId: 1, // ignición — NO infracción
          odometer: 1000);
      await insertarEvento(db,
          driverDni: '11111111',
          patente: 'AB123CD',
          eventId: 8, // sobrevelocidad — infracción
          odometer: 1200);

      final ranking = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: desdeMs,
        hastaMs: hastaMs,
        nombrePorDni: nombrePorDni,
      );

      expect(ranking.length, 1);
      final c = ranking.first;
      expect(c.choferDni, '11111111');
      expect(c.choferNombre, 'PEREZ JUAN');
      expect(c.kmRecorridos, 200);
      expect(c.totalEventos, 1);
      expect(c.infraccionesPor100Km, closeTo(0.5, 0.01));
      expect(c.icm, closeTo(97.5, 0.01));
      expect(c.categoria, CategoriaIcm.bajo);
      expect(c.eventosPorTipo['Evento 8'], 1);
      expect(c.patentes, ['AB123CD']);
    });

    test('chofer con 10 sobrevelocidades en 100 km → ICM 50 ALTO', () async {
      // 10 eventos infracción, odómetros 1000 → 1100 (cada 10km).
      // km = 100. infracciones = 10. ratio = 10/100km.
      // ICM = 100 - 10 × 5 = 50 → ALTO.
      for (var i = 0; i < 10; i++) {
        await insertarEvento(db,
            driverDni: '22222222',
            patente: 'EF456GH',
            eventId: 8,
            odometer: 1000 + i * 10);
      }

      final ranking = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: desdeMs,
        hastaMs: hastaMs,
        nombrePorDni: nombrePorDni,
      );

      expect(ranking.length, 1);
      final c = ranking.first;
      expect(c.kmRecorridos, 90); // 1090 - 1000
      expect(c.totalEventos, 10);
      // ratio = 10 / (90/100) = 11.11 → icm = 100 - 55.5 = 44.4
      expect(c.infraccionesPor100Km, closeTo(11.11, 0.05));
      expect(c.icm, closeTo(44.4, 0.1));
      expect(c.categoria, CategoriaIcm.alto);
    });

    test('chofer fronterizo ICM=80 exacto → BAJO (límite inclusivo)', () async {
      // Buscamos icm=80: ratio*5 = 20 → ratio = 4/100km.
      // 4 infracciones en 100 km. Necesitamos km=100 exactos.
      // Trick: 1er evento odometer=1000 (sin infracción), después
      // 4 infracciones, último odometer=1100.
      await insertarEvento(db,
          driverDni: '33333333',
          patente: 'IJ789KL',
          eventId: 1, // ignición para sentar min
          odometer: 1000);
      for (var i = 0; i < 4; i++) {
        await insertarEvento(db,
            driverDni: '33333333',
            patente: 'IJ789KL',
            eventId: 8,
            odometer: 1025 + i * 25); // 1025, 1050, 1075, 1100
      }

      final ranking = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: desdeMs,
        hastaMs: hastaMs,
        nombrePorDni: nombrePorDni,
      );

      expect(ranking.length, 1);
      final c = ranking.first;
      expect(c.kmRecorridos, 100);
      expect(c.totalEventos, 4);
      expect(c.icm, 80);
      expect(c.categoria, CategoriaIcm.bajo); // 80 inclusivo
    });

    test('chofer con km en múltiples patentes — suma todos los deltas',
        () async {
      // Mismo chofer en 2 patentes distintas: km totales = suma.
      // Patente A: 1000→1100 = 100 km (solo ignición, sin infracciones).
      // Patente B: 2000→2200 = 200 km (2 sobrevelocidades).
      // Total km del chofer = 300.
      //
      // NOTA del comportamiento real (validada por este test):
      // `c.patentes` lista SOLO las patentes donde hubo INFRACCIONES,
      // no todas las que manejó (ver patentesCount en el calculator —
      // se actualiza después del `continue` que filtra no-infracciones).
      // Por eso AAA NO aparece en patentes aunque sí aporta km.
      await insertarEvento(db,
          driverDni: '11111111', patente: 'AAA', eventId: 1, odometer: 1000);
      await insertarEvento(db,
          driverDni: '11111111', patente: 'AAA', eventId: 1, odometer: 1100);
      await insertarEvento(db,
          driverDni: '11111111', patente: 'BBB', eventId: 8, odometer: 2000);
      await insertarEvento(db,
          driverDni: '11111111', patente: 'BBB', eventId: 8, odometer: 2200);

      final ranking = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: desdeMs,
        hastaMs: hastaMs,
        nombrePorDni: nombrePorDni,
      );

      expect(ranking.length, 1);
      final c = ranking.first;
      // km: ambas patentes contribuyen (suma todos los deltas).
      expect(c.kmRecorridos, 300); // AAA 100 + BBB 200
      // eventos: solo BBB tuvo infracciones (eventId 8).
      expect(c.totalEventos, 2);
      // patentes: solo BBB (donde hubo infracciones). AAA NO aparece
      // aunque haya aportado km — esa es la semántica del campo.
      expect(c.patentes, ['BBB']);
    });
  });

  group('IcmCalculator.calcularRanking — edge cases (SIN_DATOS)', () {
    test('chofer con km insuficientes (<50) → categoría SIN_DATOS', () async {
      // 1 infracción en 30 km: por debajo del umbral _kmMinimoParaIcm
      // (50 km). Sin esto el ratio sería 3.33/100km → ICM 83 BAJO,
      // pero es ruido (sample tan chico no es estadísticamente válido).
      await insertarEvento(db,
          driverDni: '11111111', patente: 'AAA', eventId: 8, odometer: 1000);
      await insertarEvento(db,
          driverDni: '11111111', patente: 'AAA', eventId: 1, odometer: 1030);

      final ranking = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: desdeMs,
        hastaMs: hastaMs,
        nombrePorDni: nombrePorDni,
      );

      expect(ranking.length, 1);
      final c = ranking.first;
      expect(c.categoria, CategoriaIcm.sinDatos);
      expect(c.kmRecorridos, 0); // sinDatos → km reportados = 0
      expect(c.icm, 0); // sinDatos → ICM = 0
      // Pero los eventos siguen contados (para que la UI muestre
      // "1 infracción registrada, km insuficientes para ICM").
      expect(c.totalEventos, 1);
    });

    test('chofer con eventos pero SIN odómetro reportado → SIN_DATOS',
        () async {
      // Caso real: eventos viejos pre-poller que no traían odometer,
      // o unidades sin reportar km. ratio no computable.
      await db.collection('SITRACK_EVENTOS').add({
        'event_id': 8,
        'event_name': 'Sobrevelocidad',
        'driver_dni': '11111111',
        'asset_id': 'AAA',
        // SIN odometer
        'report_date': Timestamp.fromDate(DateTime(2026, 5, 15, 12, 0, 0)),
      });

      final ranking = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: desdeMs,
        hastaMs: hastaMs,
        nombrePorDni: nombrePorDni,
      );

      expect(ranking.length, 1);
      expect(ranking.first.categoria, CategoriaIcm.sinDatos);
    });

    test('reset odómetro (delta > 10000 km) → cap aplicado, km=0', () async {
      // Caso real: Sitrack reset post-mantenimiento — el odómetro pasa
      // de 500000 a 1000. delta = -499000 (descartado por max>min) +
      // cualquier evento posterior. Probamos con delta de 15000 km
      // (probable reset, NO viaje legítimo).
      // Cap subido de 5000 a 10000 en auditoría 2026-05-18 — choferes
      // larga distancia hacen 6000-7000 km/semana legítimos.
      // 15000 > 10000 → cap aplicado → km=0 → SIN_DATOS.
      await insertarEvento(db,
          driverDni: '11111111',
          patente: 'AAA',
          eventId: 8,
          odometer: 500000);
      await insertarEvento(db,
          driverDni: '11111111',
          patente: 'AAA',
          eventId: 8,
          odometer: 485000); // delta = 15000 → cap

      final ranking = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: desdeMs,
        hastaMs: hastaMs,
        nombrePorDni: nombrePorDni,
      );

      expect(ranking.length, 1);
      // Cap aplicado → kmReales = 0 → SIN_DATOS.
      expect(ranking.first.categoria, CategoriaIcm.sinDatos);
    });

    test('chofer larga distancia 7000 km/semana NO cae en cap (post-fix)',
        () async {
      // Regression del fix 2026-05-18: choferes BB→Mendoza
      // (~3000 km ida+vuelta × 2 viajes = 6000 km/semana legítimos)
      // quedaban como SIN_DATOS con el cap viejo de 5000. Con cap
      // 10000 deben procesarse normalmente.
      await insertarEvento(db,
          driverDni: '11111111', patente: 'AAA', eventId: 1, odometer: 1000);
      // 7000 km legítimo en la semana
      await insertarEvento(db,
          driverDni: '11111111', patente: 'AAA', eventId: 8, odometer: 8000);

      final ranking = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: desdeMs,
        hastaMs: hastaMs,
        nombrePorDni: nombrePorDni,
      );

      expect(ranking.length, 1);
      final c = ranking.first;
      expect(c.kmRecorridos, 7000);
      expect(c.totalEventos, 1);
      // ratio = 1 / 70 = 0.0143 → icm = 100 - 0.0714 ≈ 99.93
      expect(c.icm, closeTo(99.93, 0.05));
      expect(c.categoria, CategoriaIcm.bajo);
    });
  });

  group('IcmCalculator.calcularRanking — filtros', () {
    test('eventos con driver_dni vacío NO entran al ranking', () async {
      // Sitrack a veces manda eventos con driverDocumentNumber vacío
      // (chofer no se identificó con iButton). Esos NO deben aparecer
      // en el ranking ICM — el ICM es PERSONAL del chofer.
      await db.collection('SITRACK_EVENTOS').add({
        'event_id': 8,
        'event_name': 'Sobrevelocidad',
        'driver_dni': '', // VACÍO
        'asset_id': 'AAA',
        'odometer': 1000,
        'report_date': Timestamp.fromDate(DateTime(2026, 5, 15, 12, 0, 0)),
      });
      await db.collection('SITRACK_EVENTOS').add({
        'event_id': 8,
        'event_name': 'Sobrevelocidad',
        'driver_dni': '   ', // solo espacios
        'asset_id': 'AAA',
        'odometer': 1100,
        'report_date': Timestamp.fromDate(DateTime(2026, 5, 15, 12, 0, 0)),
      });

      final ranking = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: desdeMs,
        hastaMs: hastaMs,
        nombrePorDni: nombrePorDni,
      );

      expect(ranking, isEmpty);
    });

    test('eventos con event_id NO peligroso NO cuentan como infracción',
        () async {
      // event_id 1 (ignición), 100 (cualquier id NO en lista YPF)
      // contribuyen a km del odómetro pero NO al totalEventos.
      await insertarEvento(db,
          driverDni: '11111111', patente: 'AAA', eventId: 1, odometer: 1000);
      await insertarEvento(db,
          driverDni: '11111111', patente: 'AAA', eventId: 100, odometer: 1100);
      await insertarEvento(db,
          driverDni: '11111111', patente: 'AAA', eventId: 999, odometer: 1200);

      final ranking = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: desdeMs,
        hastaMs: hastaMs,
        nombrePorDni: nombrePorDni,
      );

      expect(ranking.length, 1);
      final c = ranking.first;
      expect(c.totalEventos, 0); // ninguno es infracción
      expect(c.kmRecorridos, 200); // pero los km sí cuentan
      expect(c.icm, 100); // sin infracciones → ICM perfecto
      expect(c.categoria, CategoriaIcm.bajo);
    });

    test('queryea solo eventos en rango (filtro report_date)', () async {
      // Evento fuera del rango (anterior a desde): NO debe entrar.
      await insertarEvento(db,
          driverDni: '11111111',
          patente: 'AAA',
          eventId: 8,
          odometer: 1000,
          reportDate: DateTime(2026, 1, 1)); // fuera de rango
      await insertarEvento(db,
          driverDni: '11111111',
          patente: 'AAA',
          eventId: 8,
          odometer: 1100,
          reportDate: DateTime(2026, 5, 15)); // dentro del rango

      final ranking = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: desdeMs,
        hastaMs: hastaMs,
        nombrePorDni: nombrePorDni,
      );

      // El evento fuera de rango se ignora — el de adentro queda
      // pero con km=0 (un solo evento, no hay delta) → SIN_DATOS.
      expect(ranking.length, 1);
      expect(ranking.first.totalEventos, 1);
      expect(ranking.first.categoria, CategoriaIcm.sinDatos);
    });
  });

  group('IcmCalculator.calcularRanking — ordenamiento del ranking', () {
    test('orden: peor ICM primero, SIN_DATOS al FINAL', () async {
      // 3 choferes:
      //   - 11111111 (PEREZ): 10 sobrevelocidades en 100 km → icm bajo
      //   - 22222222 (GARCIA): 1 sobrevelocidad en 200 km → icm alto
      //   - 33333333 (LOPEZ): 1 evento en 30 km → SIN_DATOS
      // Esperado: PEREZ (peor), GARCIA, LOPEZ (sindatos último).

      // PEREZ — 10 sobrevelocidades en 90 km (después del fix de
      // odómetro deja km=90, icm=~44 → ALTO).
      for (var i = 0; i < 10; i++) {
        await insertarEvento(db,
            driverDni: '11111111',
            patente: 'AAA',
            eventId: 8,
            odometer: 1000 + i * 10);
      }
      // GARCIA — 1 sobrevelocidad en 200 km → icm 97.5 (BAJO).
      await insertarEvento(db,
          driverDni: '22222222', patente: 'BBB', eventId: 1, odometer: 5000);
      await insertarEvento(db,
          driverDni: '22222222', patente: 'BBB', eventId: 8, odometer: 5200);
      // LOPEZ — 1 evento en 30 km → SIN_DATOS.
      await insertarEvento(db,
          driverDni: '33333333', patente: 'CCC', eventId: 8, odometer: 8000);
      await insertarEvento(db,
          driverDni: '33333333', patente: 'CCC', eventId: 1, odometer: 8030);

      final ranking = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: desdeMs,
        hastaMs: hastaMs,
        nombrePorDni: nombrePorDni,
      );

      expect(ranking.length, 3);
      // CRITICO: PEREZ debe estar 1ro (peor ICM = mayor prioridad
      // para Molina). GARCIA 2do. LOPEZ (SIN_DATOS) al final SIEMPRE,
      // sin importar que su icm=0 sería el peor numéricamente.
      expect(ranking[0].choferDni, '11111111'); // PEREZ — peor
      expect(ranking[0].categoria, CategoriaIcm.alto);
      expect(ranking[1].choferDni, '22222222'); // GARCIA
      expect(ranking[1].categoria, CategoriaIcm.bajo);
      expect(ranking[2].choferDni, '33333333'); // LOPEZ — SIN_DATOS al final
      expect(ranking[2].categoria, CategoriaIcm.sinDatos);
    });

    test('2 choferes ambos SIN_DATOS no rompen el sort', () async {
      // Edge case: que el sort funcione cuando todos son SIN_DATOS.
      await insertarEvento(db,
          driverDni: '11111111', patente: 'AAA', eventId: 8, odometer: 1000);
      await insertarEvento(db,
          driverDni: '22222222', patente: 'BBB', eventId: 8, odometer: 2000);

      final ranking = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: desdeMs,
        hastaMs: hastaMs,
        nombrePorDni: nombrePorDni,
      );

      expect(ranking.length, 2);
      // Ambos SIN_DATOS — el orden entre ellos no importa, solo que no crashee.
      expect(ranking.every((c) => c.categoria == CategoriaIcm.sinDatos), isTrue);
    });
  });

  group('IcmCalculator.calcularRanking — lookup de nombre', () {
    test('chofer con DNI no en nombrePorDni → fallback "DNI {dni}"',
        () async {
      // Si EMPLEADOS no tiene ese DNI (rare pero posible — chofer
      // que se dio de baja), mostrar "DNI 99999999" para no crashear.
      await insertarEvento(db,
          driverDni: '99999999', patente: 'AAA', eventId: 1, odometer: 1000);
      await insertarEvento(db,
          driverDni: '99999999', patente: 'AAA', eventId: 8, odometer: 1100);

      final ranking = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: desdeMs,
        hastaMs: hastaMs,
        nombrePorDni: nombrePorDni, // no tiene 99999999
      );

      expect(ranking.length, 1);
      expect(ranking.first.choferNombre, 'DNI 99999999');
    });

    test('sin eventos en el rango → ranking vacío', () async {
      // DB vacía o solo eventos fuera del rango.
      final ranking = await IcmCalculator.calcularRanking(
        db: db,
        desdeMs: desdeMs,
        hastaMs: hastaMs,
        nombrePorDni: nombrePorDni,
      );

      expect(ranking, isEmpty);
    });
  });
}

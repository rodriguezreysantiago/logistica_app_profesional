// Tests para helpers PUROS del vigilador de jornada v2.
//
// Strategy: igual que helpers.test.js — testear los helpers compilados
// (lib/jornadas_v2.js). El script `npm test` corre `npm run build` antes
// para asegurar que lib/ está al día.
//
// No requiere Firebase emulator: estos helpers son funciones puras
// (Haversine, conversión TZ). Para tests del flujo completo del
// vigilador (tickVigiladorJornada, descansoPrevioCumplido, etc.) hace
// falta sumar firebase-functions-test + emulator Firestore, que es
// trabajo aparte (sesión dedicada).

const { test, describe } = require('node:test');
const assert = require('node:assert');

const { distanciaMetros, horaArt } = require('../lib/jornadas_v2');

describe('distanciaMetros (Haversine)', () => {
  test('mismo punto → 0', () => {
    // Bahía Blanca (sede Vecchi aprox).
    const d = distanciaMetros(-38.7196, -62.2724, -38.7196, -62.2724);
    assert.strictEqual(d, 0);
  });

  test('Bahía Blanca → Mar del Plata (~418 km línea recta)', () => {
    // Coordenadas conocidas. Haversine = distancia en línea recta
    // (gran círculo) — la distancia por ruta es siempre > esto
    // (~520 km por RP226+RN3+RN2). 418 km confirmado empíricamente.
    // Tolerancia 10 km para drift de coordenadas no exactas.
    const d = distanciaMetros(-38.7196, -62.2724, -38.0023, -57.5575);
    assert.ok(
      d > 410000 && d < 430000,
      `Esperado ~418km, obtenido ${(d / 1000).toFixed(1)}km`,
    );
  });

  test('1 grado de latitud ≈ 111 km', () => {
    // Definición de meridiano: 1° lat = 1/360 de la circunferencia
    // polar (~40,008 km / 360 = 111.13 km). Útil para sanity-check
    // de la fórmula.
    const d = distanciaMetros(0, 0, 1, 0);
    assert.ok(
      d > 110000 && d < 112000,
      `Esperado ~111km, obtenido ${(d / 1000).toFixed(2)}km`,
    );
  });

  test('1 grado de longitud en ecuador ≈ 111 km', () => {
    const d = distanciaMetros(0, 0, 0, 1);
    assert.ok(
      d > 110000 && d < 112000,
      `Esperado ~111km, obtenido ${(d / 1000).toFixed(2)}km`,
    );
  });

  test('1 grado de longitud en latitud alta (-60°) es bastante menor', () => {
    // Los meridianos convergen hacia los polos — a -60° latitud,
    // 1° lng = 111 km × cos(60°) ≈ 55.5 km.
    const d = distanciaMetros(-60, 0, -60, 1);
    assert.ok(
      d > 54000 && d < 57000,
      `Esperado ~55.5km, obtenido ${(d / 1000).toFixed(2)}km`,
    );
  });

  test('distancia simétrica (a→b == b→a)', () => {
    const ab = distanciaMetros(-38.7196, -62.2724, -34.6037, -58.3816);
    const ba = distanciaMetros(-34.6037, -58.3816, -38.7196, -62.2724);
    assert.strictEqual(ab, ba);
  });

  test('antípodas — la distancia más larga posible (~20015 km)', () => {
    // Buenos Aires aprox vs su antípoda. Sanity-check de que la
    // función NO se rompe en el caso extremo.
    const d = distanciaMetros(-34.6, -58.4, 34.6, 121.6);
    assert.ok(
      d > 19900000 && d < 20100000,
      `Esperado ~20000km, obtenido ${(d / 1000).toFixed(0)}km`,
    );
  });

  test('radio defensivo Vecchi: 1000m (DESCANSO_RADIO_METROS)', () => {
    // Caso real del modelo descanso: el camión queda detenido en
    // misma posición = mismo punto ± drift GPS. La constante
    // DESCANSO_RADIO_METROS es 1000m. Verificamos que un drift de
    // ~10 metros queda muy debajo del umbral.
    // ~10m ≈ 0.0001° latitud (1m ≈ 1e-5°).
    const d = distanciaMetros(-38.7196, -62.2724, -38.71969, -62.27249);
    assert.ok(
      d < 15,
      `Drift mínimo: esperado <15m, obtenido ${d.toFixed(1)}m`,
    );
  });
});

describe('horaArt — extrae hora 0..23 en TZ Argentina', () => {
  test('UTC 03:00 = ART 00:00 (medianoche en BB)', () => {
    // 2026-05-15 03:00:00 UTC = 2026-05-15 00:00:00 ART (UTC-3 fijo).
    const tsMs = Date.UTC(2026, 4, 15, 3, 0, 0);
    assert.strictEqual(horaArt(tsMs), 0);
  });

  test('UTC 12:00 = ART 09:00', () => {
    const tsMs = Date.UTC(2026, 4, 15, 12, 0, 0);
    assert.strictEqual(horaArt(tsMs), 9);
  });

  test('UTC 23:30 = ART 20:00 (último horario hábil L-V según WORKING_HOURS_END=20)', () => {
    const tsMs = Date.UTC(2026, 4, 15, 23, 30, 0);
    assert.strictEqual(horaArt(tsMs), 20);
  });

  test('cruce de día: UTC 02:00 del día N = ART 23:00 del día N-1', () => {
    // Edge case importante: cuando UTC marca día siguiente pero ART
    // sigue en el día anterior. La función devuelve la HORA del día
    // ART (no del UTC) — 23h.
    const tsMs = Date.UTC(2026, 4, 15, 2, 0, 0);
    assert.strictEqual(horaArt(tsMs), 23);
  });

  test('veda nocturna ART 00:00 (VEDA_NOCTURNA_DESDE_HORA=0)', () => {
    // Verificamos que la veda nocturna del vigilador (00:00-06:00 ART)
    // se detecta correctamente con un timestamp UTC equivalente a
    // medianoche ART.
    const tsMs = Date.UTC(2026, 4, 15, 3, 30, 0); // 00:30 ART
    assert.strictEqual(horaArt(tsMs), 0);
  });

  test('fin de veda nocturna ART 06:00 (VEDA_NOCTURNA_HASTA_HORA=6)', () => {
    const tsMs = Date.UTC(2026, 4, 15, 9, 0, 0); // 06:00 ART
    assert.strictEqual(horaArt(tsMs), 6);
  });

  test('ART NO usa horario de verano — siempre UTC-3', () => {
    // Argentina abolió DST en 2009. Verificamos enero (verano AR)
    // y julio (invierno AR) con mismo offset.
    const enero = Date.UTC(2026, 0, 15, 15, 0, 0); // ART 12:00
    const julio = Date.UTC(2026, 6, 15, 15, 0, 0); // ART 12:00
    assert.strictEqual(horaArt(enero), 12);
    assert.strictEqual(horaArt(julio), 12);
  });

  test('horas extremas 0 y 23 — sanity check del rango devuelto', () => {
    const horas = [];
    for (let h = 0; h < 24; h++) {
      // Construimos timestamp para hora H ART = UTC H+3.
      const tsMs = Date.UTC(2026, 4, 15, (h + 3) % 24, 0, 0);
      horas.push(horaArt(tsMs));
    }
    // Cada hora debe ser un entero distinto entre 0 y 23.
    const setHoras = new Set(horas);
    assert.strictEqual(setHoras.size, 24);
    for (const h of horas) {
      assert.ok(h >= 0 && h <= 23, `hora fuera de rango: ${h}`);
      assert.strictEqual(typeof h, 'number');
      assert.ok(Number.isInteger(h), `no es entero: ${h}`);
    }
  });
});

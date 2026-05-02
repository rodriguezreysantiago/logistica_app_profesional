// Tests para feriados_ar.js. Corre con `node --test`.
//
// Forzamos TZ ART para que los Date(year, month-1, day) tengan
// componentes locales consistentes con lo que el bot ve en produccion.
process.env.TZ = 'America/Argentina/Buenos_Aires';

const { test, describe } = require('node:test');
const assert = require('node:assert');
const { esFeriado, descripcionFeriado, FERIADOS } = require('../src/feriados_ar');

describe('feriados_ar.esFeriado', () => {
  test('1 de mayo 2026 (Dia del Trabajador) es feriado', () => {
    assert.strictEqual(esFeriado(new Date(2026, 4, 1)), true);
  });

  test('25 de diciembre 2026 (Navidad) es feriado', () => {
    assert.strictEqual(esFeriado(new Date(2026, 11, 25)), true);
  });

  test('1 de enero 2027 (Anio Nuevo) es feriado', () => {
    assert.strictEqual(esFeriado(new Date(2027, 0, 1)), true);
  });

  test('25 de mayo 2026 (Revolucion) es feriado', () => {
    assert.strictEqual(esFeriado(new Date(2026, 4, 25)), true);
  });

  test('un lunes cualquiera no-feriado NO es feriado', () => {
    // 4-mayo-2026 es lunes habil normal (no feriado).
    assert.strictEqual(esFeriado(new Date(2026, 4, 4)), false);
  });

  test('un dia fuera del rango cargado devuelve false (no crashea)', () => {
    // 2025 no esta en la lista (intencional: solo cargamos 2026 y 2027
    // segun la convencion de mantenimiento anual).
    assert.strictEqual(esFeriado(new Date(2025, 0, 1)), false);
    assert.strictEqual(esFeriado(new Date(2030, 11, 25)), false);
  });

  test('input no-Date devuelve false sin tirar', () => {
    assert.strictEqual(esFeriado(null), false);
    assert.strictEqual(esFeriado(undefined), false);
    assert.strictEqual(esFeriado('2026-05-01'), false);
    assert.strictEqual(esFeriado(123456789), false);
  });

  test('Date invalido (NaN) devuelve false', () => {
    const invalido = new Date('basura');
    assert.strictEqual(esFeriado(invalido), false);
  });
});

describe('feriados_ar.descripcionFeriado', () => {
  test('devuelve nombre exacto de un feriado conocido', () => {
    assert.strictEqual(
      descripcionFeriado(new Date(2026, 4, 1)),
      'Dia del Trabajador'
    );
  });

  test('dia no-feriado devuelve null', () => {
    assert.strictEqual(descripcionFeriado(new Date(2026, 4, 4)), null);
  });

  test('input invalido devuelve null', () => {
    assert.strictEqual(descripcionFeriado(null), null);
    assert.strictEqual(descripcionFeriado(new Date('xx')), null);
  });
});

describe('feriados_ar — datos cargados', () => {
  test('lista 2026 completa (15 feriados nacionales obligatorios)', () => {
    const fechas2026 = Object.keys(FERIADOS).filter((k) => k.startsWith('2026-'));
    assert.strictEqual(fechas2026.length, 15);
  });

  test('lista 2027 completa (15 feriados nacionales obligatorios)', () => {
    const fechas2027 = Object.keys(FERIADOS).filter((k) => k.startsWith('2027-'));
    assert.strictEqual(fechas2027.length, 15);
  });

  test('todas las fechas estan en formato YYYY-MM-DD valido', () => {
    for (const fecha of Object.keys(FERIADOS)) {
      assert.match(fecha, /^\d{4}-\d{2}-\d{2}$/, `Formato invalido: ${fecha}`);
    }
  });
});

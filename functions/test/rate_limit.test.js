// Tests para los helpers de rate limit de loginConDni:
// chequearBloqueoActivo y registrarIntentoFallido.
//
// Strategy: testear contra mocks manuales de DocumentReference y
// Firestore (con runTransaction). Sin Firebase Emulator. Cubre los
// paths de control de flujo del rate limit:
//   - Cuenta no bloqueada (caso normal).
//   - Cuenta bloqueada con tiempo restante.
//   - Bloqueo expirado se detecta.
//   - Cruce del umbral activa el bloqueo.
//   - Bloqueo durante transaction concurrent (fix Bug M1).
//   - Coerción tolerante a corrupción (intentos como string).
//
// Lo que NO cubre y sigue siendo deuda: integración E2E del handler
// loginConDni completo (custom token issuance, Firebase Auth, etc.)
// — para eso se necesita Firebase Functions Test SDK + emulador.

const { test, describe } = require('node:test');
const assert = require('node:assert');
const { Timestamp } = require('firebase-admin/firestore');

const {
  chequearBloqueoActivo,
  registrarIntentoFallido,
} = require('../lib/index');

// ============================================================================
// Helpers de mocking
// ============================================================================

/**
 * Crea un mock de DocumentReference con los métodos que usan los helpers.
 * El `initialData` simula el estado del doc (null = no existe).
 */
function fakeRef(initialData = null) {
  let data = initialData ? { ...initialData } : null;
  let exists = data !== null;

  return {
    get: async () => ({
      exists,
      data: () => data,
    }),
    update: async (changes) => {
      data = { ...(data ?? {}), ...changes };
      exists = true;
    },
    set: async (changes) => {
      data = { ...changes };
      exists = true;
    },
    // Método helper para que los tests puedan verificar el estado final.
    _peek: () => data,
  };
}

/**
 * Crea un mock de Firestore con runTransaction. La transaction recibe
 * un objeto `tx` con los mismos métodos que la ref pero con la firma
 * (ref, changes) en lugar de (changes).
 */
function fakeDb() {
  return {
    runTransaction: async (fn) => {
      const tx = {
        get: (ref) => ref.get(),
        update: (ref, changes) => {
          // En real es queue (no async), pero acá ejecutamos sync para
          // que el _peek post-test refleje el estado.
          ref.update(changes);
        },
        set: (ref, changes) => {
          ref.set(changes);
        },
      };
      return await fn(tx);
    },
  };
}

// ============================================================================
// chequearBloqueoActivo
// ============================================================================

describe('chequearBloqueoActivo', () => {
  test('doc no existe → 0 (no bloqueado, primer intento de la vida)', async () => {
    const ref = fakeRef(null);
    const result = await chequearBloqueoActivo(ref);
    assert.strictEqual(result, 0);
  });

  test('doc sin bloqueadoHasta → 0', async () => {
    const ref = fakeRef({ intentos: 2 });
    const result = await chequearBloqueoActivo(ref);
    assert.strictEqual(result, 0);
  });

  test('doc con bloqueadoHasta YA VENCIDO → 0 (puede reintentar)', async () => {
    // bloqueadoHasta hace 5 minutos en el pasado.
    const cincoMinAtras = Timestamp.fromMillis(Date.now() - 5 * 60 * 1000);
    const ref = fakeRef({ intentos: 5, bloqueadoHasta: cincoMinAtras });
    const result = await chequearBloqueoActivo(ref);
    assert.strictEqual(result, 0);
  });

  test('doc con bloqueadoHasta ACTIVO → minutos restantes (redondeo arriba)', async () => {
    // bloqueadoHasta dentro de 7.3 minutos → debería devolver 8.
    const futuroMs = Date.now() + 7.3 * 60 * 1000;
    const ref = fakeRef({
      intentos: 5,
      bloqueadoHasta: Timestamp.fromMillis(futuroMs),
    });
    const result = await chequearBloqueoActivo(ref);
    assert.strictEqual(result, 8);
  });

  test('doc con bloqueadoHasta exactamente al borde (Math.ceil)', async () => {
    // bloqueadoHasta dentro de 0.5 min → debería devolver 1 (no 0).
    const medioMin = Date.now() + 30 * 1000;
    const ref = fakeRef({
      bloqueadoHasta: Timestamp.fromMillis(medioMin),
    });
    const result = await chequearBloqueoActivo(ref);
    assert.strictEqual(result, 1);
  });
});

// ============================================================================
// registrarIntentoFallido
// ============================================================================

describe('registrarIntentoFallido', () => {
  test('primer intento (doc no existe) → intentos=1, no bloqueado', async () => {
    const ref = fakeRef(null);
    const db = fakeDb();
    const r = await registrarIntentoFallido(ref, db);
    assert.strictEqual(r.intentos, 1);
    assert.strictEqual(r.bloqueadoMinRestantes, 0);
    // Verificar que el doc se creó con intentos=1.
    assert.strictEqual(ref._peek().intentos, 1);
  });

  test('intento 4 (debajo del umbral 5) → no bloquea', async () => {
    const ref = fakeRef({ intentos: 3 });
    const db = fakeDb();
    const r = await registrarIntentoFallido(ref, db);
    assert.strictEqual(r.intentos, 4);
    assert.strictEqual(r.bloqueadoMinRestantes, 0);
    assert.strictEqual(
      ref._peek().bloqueadoHasta,
      undefined,
      'No debe setear bloqueadoHasta debajo del umbral'
    );
  });

  test('cruzar umbral (5to intento) → activa bloqueo', async () => {
    const ref = fakeRef({ intentos: 4 });
    const db = fakeDb();
    const r = await registrarIntentoFallido(ref, db);
    assert.strictEqual(r.intentos, 5);
    assert.ok(
      r.bloqueadoMinRestantes > 0,
      'Debe devolver minutos > 0'
    );
    assert.ok(
      r.bloqueadoMinRestantes <= 16,
      'No debe ser absurdo (15 min default + redondeo)'
    );
    // Debe haber seteado bloqueadoHasta en el doc.
    assert.ok(
      ref._peek().bloqueadoHasta,
      'bloqueadoHasta debe quedar seteado'
    );
  });

  test('REGRESSION Bug M1: doc YA bloqueado → NO incrementa, devuelve restante', async () => {
    // Caso de race condition: dos requests paralelas detectan el doc
    // como "no bloqueado" en chequearBloqueoActivo (sin tx) y entran
    // a registrarIntentoFallido. La que llega primero a la tx ve el
    // estado real ya bloqueado y NO debe incrementar.
    const futuro = Timestamp.fromMillis(Date.now() + 10 * 60 * 1000);
    const ref = fakeRef({ intentos: 5, bloqueadoHasta: futuro });
    const db = fakeDb();
    const r = await registrarIntentoFallido(ref, db);
    assert.strictEqual(r.intentos, 5, 'NO debe incrementar a 6');
    assert.ok(r.bloqueadoMinRestantes > 0);
    assert.ok(r.bloqueadoMinRestantes <= 11);
    // El doc no debe haber cambiado.
    assert.strictEqual(ref._peek().intentos, 5);
  });

  test('doc bloqueado pero ya expirado → trata como nuevo intento', async () => {
    // bloqueadoHasta en el pasado → la tx debe tratar como "no bloqueado"
    // e incrementar el contador.
    const pasado = Timestamp.fromMillis(Date.now() - 5 * 60 * 1000);
    const ref = fakeRef({ intentos: 5, bloqueadoHasta: pasado });
    const db = fakeDb();
    const r = await registrarIntentoFallido(ref, db);
    assert.strictEqual(
      r.intentos,
      6,
      'Si ya expiró el bloqueo, este intento es uno mas'
    );
  });

  test('REGRESSION Bug A2: intentos como STRING (corrupción) se coerce a number', async () => {
    // Documentado en el código: por corrupción/migración, `intentos`
    // podría venir como string. Coerción defensiva.
    const ref = fakeRef({ intentos: '3' });
    const db = fakeDb();
    const r = await registrarIntentoFallido(ref, db);
    assert.strictEqual(r.intentos, 4);
  });

  test('intentos como NaN/null se coerce a 0 inicial', async () => {
    const ref = fakeRef({ intentos: 'XYZ' });
    const db = fakeDb();
    const r = await registrarIntentoFallido(ref, db);
    // 'XYZ' → NaN → fallback a 0 → +1 = 1.
    assert.strictEqual(r.intentos, 1);
  });

  test('actualiza ultimoIntento con serverTimestamp sentinel', async () => {
    const ref = fakeRef({ intentos: 1 });
    const db = fakeDb();
    await registrarIntentoFallido(ref, db);
    // FieldValue.serverTimestamp() devuelve un sentinel especial; lo
    // único que verificamos es que se haya seteado el campo (no que
    // sea Date — eso lo resuelve Firestore real).
    assert.ok(
      ref._peek().ultimoIntento !== undefined,
      'Debe setear ultimoIntento'
    );
  });
});

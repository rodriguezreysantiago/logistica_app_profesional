// Script one-shot para migrar los adelantos embebidos en VIAJES_LOGISTICA
// a la colección nueva ADELANTOS_CHOFER.
//
// Refactor 2026-05-13: hasta esta fecha, cada viaje guardaba el adelanto
// como campos sueltos (`adelantoMonto`, `adelantoFecha`,
// `adelantoObservacion`, `numero_recibo`, `fecha_impresion`). Ahora el
// adelanto vive en su propio doc en ADELANTOS_CHOFER y puede existir
// SIN viaje (caso típico: adelanto de sueldo).
//
// QUÉ HACE:
//   Para cada viaje con `adelantoMonto > 0`, crea un doc nuevo en
//   ADELANTOS_CHOFER copiando:
//      - chofer_dni / chofer_nombre  ← del viaje
//      - fecha                        ← adelantoFecha del viaje (o fecha_carga si no había)
//      - monto                        ← adelantoMonto
//      - observacion                  ← adelantoObservacion
//      - viaje_id                     ← id del viaje (link reverso opcional)
//      - numero_recibo                ← numero_recibo (si ya se había impreso)
//      - impreso_en                   ← fecha_impresion (si ya se había impreso)
//      - creado_por_dni               ← "SISTEMA_MIGRACION_ADELANTOS"
//
//   Y CONSERVA los campos en el viaje, para que la pantalla LIQUIDACIÓN
//   pueda seguir mostrando el adelanto legacy hasta que el operador
//   confirme que la migración salió OK. Cuando todo esté consolidado,
//   se puede correr un cleanup que pone esos campos a null en los
//   viajes ya migrados — pero ESO es un paso aparte, no este script.
//
// IMPORTANTE: como el código cliente suma adelantos NUEVOS (colección)
// MÁS legacy (campos en viaje), correr este script SIN limpiar después
// produciría doble conteo en LIQUIDACIÓN. Por eso este script marca el
// viaje con `adelanto_migrado_a_id` (string con el ID del adelanto
// nuevo) — el cliente puede leerlo para evitar doble-contar.
//
// IDEMPOTENTE: si el viaje ya tiene `adelanto_migrado_a_id`, se saltea.
// Podés correrlo varias veces sin riesgo.
//
// USO:
//   cd whatsapp-bot   (necesitamos sus node_modules + serviceAccountKey)
//   node ../scripts/migrar_adelantos_de_viajes.js              (dry-run)
//   node ../scripts/migrar_adelantos_de_viajes.js --apply      (escribe)

const path = require('path');
const fsNode = require('fs');

// Reusamos los node_modules y .env del bot.
const botDir = path.resolve(__dirname, '..', 'whatsapp-bot');
const botNodeModules = path.join(botDir, 'node_modules');
if (!fsNode.existsSync(botNodeModules)) {
  console.error(
    `❌ No existe ${botNodeModules}. Corré 'npm install' en whatsapp-bot primero.`
  );
  process.exit(1);
}
module.paths.unshift(botNodeModules);
process.chdir(botDir);
require('dotenv').config({ quiet: true });

const admin = require('firebase-admin');

const credPath =
  process.env.FIREBASE_CREDENTIALS_PATH || '../serviceAccountKey.json';
const absPath = path.resolve(credPath);
if (!fsNode.existsSync(absPath)) {
  console.error(`❌ Credenciales no encontradas en: ${absPath}`);
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(absPath)),
  projectId: process.env.FIREBASE_PROJECT_ID || 'coopertrans-movil',
});

const db = admin.firestore();

const COL_VIAJES = 'VIAJES_LOGISTICA';
const COL_ADELANTOS = 'ADELANTOS_CHOFER';

const MIGRACION_PSEUDO_DNI = 'SISTEMA_MIGRACION_ADELANTOS';

const dryRun = !process.argv.includes('--apply');

function montoValido(raw) {
  if (raw == null) return false;
  const n = Number(raw);
  return Number.isFinite(n) && n > 0;
}

async function main() {
  console.log(
    `💰 Migración adelantos embebidos → ADELANTOS_CHOFER ${dryRun ? '(DRY-RUN)' : '(APPLY)'}`
  );
  console.log(`   Proyecto: ${admin.app().options.projectId}`);
  console.log('');

  // Traemos todos los viajes (incluso soft-deleted: si un viaje borrado
  // tenía adelanto y comprobante impreso, queremos preservar el rastro
  // para auditoría).
  const snap = await db.collection(COL_VIAJES).get();
  console.log(`📊 ${snap.size} viajes leídos.\n`);

  let conAdelanto = 0;
  let yaMigrados = 0;
  let aCrear = 0;
  let creados = 0;
  const errores = [];

  for (const doc of snap.docs) {
    const viajeId = doc.id;
    const data = doc.data();
    const monto = data.adelantoMonto;

    if (!montoValido(monto)) continue;
    conAdelanto++;

    if (data.adelanto_migrado_a_id) {
      yaMigrados++;
      continue;
    }

    // Reconstruimos el adelanto a partir de lo que tenemos en el viaje.
    // `fecha` cae a `fecha_carga` o `creado_en` si el operador no había
    // cargado fecha del adelanto explícitamente.
    const fechaAdelanto =
      data.adelantoFecha || data.fecha_carga || data.creado_en || null;
    const adelanto = {
      chofer_dni: String(data.chofer_dni || ''),
      chofer_nombre: data.chofer_nombre || null,
      fecha: fechaAdelanto,
      monto: Number(monto),
      observacion: data.adelantoObservacion || null,
      viaje_id: viajeId,
      // Si el comprobante ya estaba impreso, preservamos el correlativo
      // — NO se vuelve a usar la Cloud Function para no quemar otro
      // número.
      numero_recibo: data.numero_recibo || null,
      impreso_en: data.fecha_impresion || null,
      creado_en: admin.firestore.FieldValue.serverTimestamp(),
      creado_por_dni: MIGRACION_PSEUDO_DNI,
      creado_por_nombre: 'Migración 2026-05-13 (adelanto legacy del viaje)',
      actualizado_en: admin.firestore.FieldValue.serverTimestamp(),
      actualizado_por_dni: MIGRACION_PSEUDO_DNI,
    };

    aCrear++;
    const nombre = adelanto.chofer_nombre || `DNI ${adelanto.chofer_dni}`;
    const numStr = adelanto.numero_recibo
      ? `  recibo Nº ${String(adelanto.numero_recibo).padStart(6, '0')}`
      : '';
    console.log(
      `  • ${viajeId}  ${nombre}  $${adelanto.monto.toLocaleString('es-AR')}${numStr}`
    );

    if (dryRun) continue;

    try {
      const newRef = await db.collection(COL_ADELANTOS).add(adelanto);
      // Marcamos el viaje original con el ID del adelanto nuevo, para
      // que el cliente sepa que ese `adelantoMonto` legacy YA está
      // representado en ADELANTOS_CHOFER y no debe doble-contarlo.
      await db.collection(COL_VIAJES).doc(viajeId).update({
        adelanto_migrado_a_id: newRef.id,
      });
      creados++;
    } catch (e) {
      errores.push({ viajeId, error: e.message });
      console.error(`      ❌ Falló: ${e.message}`);
    }
  }

  console.log('');
  console.log('───────────────── RESUMEN ─────────────────');
  console.log(`  Viajes procesados        : ${snap.size}`);
  console.log(`  Con adelantoMonto > 0    : ${conAdelanto}`);
  console.log(`  Ya migrados (saltados)   : ${yaMigrados}`);
  console.log(`  A crear                  : ${aCrear}`);
  if (!dryRun) {
    console.log(`  Creados con éxito        : ${creados}`);
    console.log(`  Errores                  : ${errores.length}`);
  }
  console.log('');

  if (dryRun) {
    console.log('ℹ️  Esto fue un DRY-RUN — no se escribió nada.');
    console.log('   Si el listado de arriba es el esperado, corré con --apply:');
    console.log('   node ../scripts/migrar_adelantos_de_viajes.js --apply');
  } else {
    console.log('✓ Migración completa.');
    console.log('');
    console.log('IMPORTANTE: para que la pantalla LIQUIDACIÓN no duplique');
    console.log('los montos, hay que ajustar el cliente para que NO sume el');
    console.log('`adelantoMonto` legacy de los viajes con `adelanto_migrado_a_id`');
    console.log('seteado. (TODO post-migración).');
    if (errores.length > 0) {
      console.log('');
      console.log('⚠ Viajes que fallaron:');
      errores.forEach((e) =>
        console.log(`   - ${e.viajeId}: ${e.error}`)
      );
    }
  }

  process.exit(0);
}

main().catch((e) => {
  console.error('❌ Falló:', e.stack || e.message);
  process.exit(1);
});

// Script one-shot DESTRUCTIVO para empezar de cero el módulo Logística:
//   1. Borra TODOS los viajes (`VIAJES_LOGISTICA`) — hard-delete.
//   2. Limpia de Storage los remitos asociados a esos viajes.
//   3. Borra TODOS los adelantos (`ADELANTOS_CHOFER`) — hard-delete.
//   4. Resetea el counter de recibos de adelanto a `{ next: 1 }`.
//
// Pensado para el momento entre etapa testing y primera prueba real:
// Santiago decidió 2026-05-13 tirar todo lo cargado en testing (incluye
// los viajes con cálculo viejo sin 18%) y empezar de cero con la
// fórmula corregida.
//
// NO toca:
//   - Catálogos (EMPRESAS_LOGISTICA, UBICACIONES_LOGISTICA,
//     TARIFAS_LOGISTICA) — esos los queremos conservar.
//   - Otros counters (KMs, etc.) — solo el de recibos de adelanto.
//   - Foto-comprobantes de adelantos (no se persisten en Storage; el
//     PDF se genera on-the-fly al imprimir).
//
// SAFETY:
//   - Dry-run por default. Con --apply escribe.
//   - Imprime el resumen completo antes de cualquier acción
//     destructiva.
//   - Idempotente: si lo corrés dos veces, la segunda no hace nada.
//   - NO se puede deshacer una vez aplicado (es hard-delete).
//
// USO:
//   cd whatsapp-bot
//   node ../scripts/empezar_de_cero_logistica.js               # dry-run
//   node ../scripts/empezar_de_cero_logistica.js --apply       # ejecuta

const path = require('path');
const fsNode = require('fs');

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

const serviceAccount = require(absPath);
const projectId = process.env.FIREBASE_PROJECT_ID || serviceAccount.project_id;
const storageBucket =
  process.env.FIREBASE_STORAGE_BUCKET || `${projectId}.appspot.com`;
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId,
  storageBucket,
});

const db = admin.firestore();
const bucket = admin.storage().bucket();

const COL_VIAJES = 'VIAJES_LOGISTICA';
const COL_ADELANTOS = 'ADELANTOS_CHOFER';
const COL_COUNTERS = 'COUNTERS';
const COUNTER_RECIBOS_DOC = 'recibos_adelanto';

const BATCH_SIZE = 400;
const dryRun = !process.argv.includes('--apply');

/**
 * Junta todas las paths de Storage de los remitos asociados a un viaje.
 * Cada tramo puede tener su propio `remito_path_storage`. Single-tramo
 * legacy: la path está al nivel del doc.
 */
function pathsDeRemitos(viajeData) {
  const paths = new Set();
  const tramos = viajeData.tramos;
  if (Array.isArray(tramos)) {
    for (const t of tramos) {
      if (t && typeof t === 'object') {
        const p = t.remito_path_storage;
        if (typeof p === 'string' && p.length > 0) paths.add(p);
      }
    }
  }
  const legacy = viajeData.remito_path_storage;
  if (typeof legacy === 'string' && legacy.length > 0) paths.add(legacy);
  return [...paths];
}

async function borrarRemitosDeStorage(pathsRemitos) {
  if (pathsRemitos.length === 0) return { borrados: 0, errores: [] };
  let borrados = 0;
  const errores = [];
  for (const p of pathsRemitos) {
    try {
      await bucket.file(p).delete({ ignoreNotFound: true });
      borrados++;
    } catch (e) {
      errores.push({ path: p, error: e.message });
    }
  }
  return { borrados, errores };
}

async function borrarColeccionEnBatches(collectionName, snap) {
  if (snap.size === 0) return 0;
  let total = 0;
  let batch = db.batch();
  let pending = 0;
  for (const doc of snap.docs) {
    batch.delete(doc.ref);
    pending++;
    if (pending >= BATCH_SIZE) {
      await batch.commit();
      total += pending;
      batch = db.batch();
      pending = 0;
    }
  }
  if (pending > 0) {
    await batch.commit();
    total += pending;
  }
  return total;
}

async function main() {
  console.log(
    `🧹 EMPEZAR DE CERO Logística ${dryRun ? '(DRY-RUN)' : '(APPLY)'}`
  );
  console.log(`   Proyecto: ${admin.app().options.projectId}`);
  console.log(`   Bucket:   ${admin.app().options.storageBucket}`);
  console.log('');

  // ─── Inspección previa ───────────────────────────────────────────
  const [viajesSnap, adelantosSnap, counterSnap] = await Promise.all([
    db.collection(COL_VIAJES).get(),
    db.collection(COL_ADELANTOS).get(),
    db.collection(COL_COUNTERS).doc(COUNTER_RECIBOS_DOC).get(),
  ]);

  // Contar remitos a borrar.
  let totalRemitos = 0;
  for (const doc of viajesSnap.docs) {
    totalRemitos += pathsDeRemitos(doc.data() || {}).length;
  }

  const counterActual =
    counterSnap.exists && typeof counterSnap.data()?.next === 'number'
      ? counterSnap.data().next
      : '(no existe)';

  console.log('───────────────── INVENTARIO ─────────────────');
  console.log(`  Viajes a borrar              : ${viajesSnap.size}`);
  console.log(`  Remitos en Storage a limpiar : ${totalRemitos}`);
  console.log(`  Adelantos a borrar           : ${adelantosSnap.size}`);
  console.log(`  Counter recibos actual       : ${counterActual}`);
  console.log(`  Counter recibos → quedará en : 1`);
  console.log('');

  if (dryRun) {
    console.log('ℹ️  Esto fue un DRY-RUN — no se borró nada.');
    console.log('   Si el inventario es lo que esperás, corré con --apply:');
    console.log('   node ../scripts/empezar_de_cero_logistica.js --apply');
    console.log('');
    console.log('   ⚠ ATENCIÓN: --apply es DESTRUCTIVO e IRREVERSIBLE.');
    process.exit(0);
  }

  // ─── EJECUCIÓN destructiva ──────────────────────────────────────
  console.log('───────────────── EJECUTANDO ─────────────────');

  // 1. Storage: borrar remitos. En paralelo lote a lote para no saturar
  // demasiado a la vez. Best-effort — si alguno falla, lo loggeamos y
  // seguimos con el borrado de docs (el doc apunta a un path que ya no
  // existe → orphan benigno).
  console.log('  [1/4] Borrando remitos de Storage...');
  let totalBorradosStorage = 0;
  const erroresStorage = [];
  for (const doc of viajesSnap.docs) {
    const paths = pathsDeRemitos(doc.data() || {});
    if (paths.length === 0) continue;
    const r = await borrarRemitosDeStorage(paths);
    totalBorradosStorage += r.borrados;
    erroresStorage.push(...r.errores);
  }
  console.log(
    `        OK ${totalBorradosStorage} archivo(s) borrado(s) — ${erroresStorage.length} error(es).`
  );

  // 2. Viajes: hard-delete en batches.
  console.log('  [2/4] Borrando viajes de Firestore...');
  const viajesBorrados = await borrarColeccionEnBatches(COL_VIAJES, viajesSnap);
  console.log(`        OK ${viajesBorrados} viaje(s) borrado(s).`);

  // 3. Adelantos: hard-delete en batches.
  console.log('  [3/4] Borrando adelantos de Firestore...');
  const adelantosBorrados = await borrarColeccionEnBatches(
    COL_ADELANTOS,
    adelantosSnap
  );
  console.log(`        OK ${adelantosBorrados} adelanto(s) borrado(s).`);

  // 4. Counter: resetear a 1. NO usamos `update()` por si el doc no
  // existe; `set` con merge es seguro.
  console.log('  [4/4] Reseteando counter de recibos a 1...');
  await db
    .collection(COL_COUNTERS)
    .doc(COUNTER_RECIBOS_DOC)
    .set(
      {
        next: 1,
        actualizado_en: admin.firestore.FieldValue.serverTimestamp(),
        reset_por: 'script empezar_de_cero_logistica',
      },
      { merge: false }
    );
  console.log('        OK counter en 1.');

  console.log('');
  console.log('───────────────── RESUMEN ─────────────────');
  console.log(`  Viajes borrados              : ${viajesBorrados}`);
  console.log(`  Adelantos borrados           : ${adelantosBorrados}`);
  console.log(`  Remitos Storage borrados     : ${totalBorradosStorage}`);
  console.log(`  Errores Storage              : ${erroresStorage.length}`);
  console.log(`  Counter recibos              : 1`);
  console.log('');
  console.log('✓ Listo. Módulo Logística limpio para empezar las pruebas reales.');
  if (erroresStorage.length > 0) {
    console.log('');
    console.log('⚠ Remitos que no se pudieron borrar de Storage:');
    erroresStorage.slice(0, 10).forEach((e) =>
      console.log(`   - ${e.path}: ${e.error}`)
    );
    if (erroresStorage.length > 10) {
      console.log(`   ... y ${erroresStorage.length - 10} más.`);
    }
    console.log('  (No es fatal: los docs ya están borrados, los archivos');
    console.log('   huérfanos quedan en Storage. Se pueden limpiar a mano.)');
  }
  process.exit(0);
}

main().catch((e) => {
  console.error('❌ Falló:', e.stack || e.message);
  process.exit(1);
});

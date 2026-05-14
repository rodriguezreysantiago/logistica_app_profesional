// Script one-shot DESTRUCTIVO para limpiar adelantos y resetear el
// counter de recibos. Pensado para el momento "ya estamos en
// funcionamiento real, descartemos los de prueba y arranquemos de
// cero" (Santiago 2026-05-14).
//
// Hace:
//   1. Borra TODOS los docs de `ADELANTOS_CHOFER` — incluso los
//      soft-deleted (eliminado=true) — porque son de prueba.
//   2. Resetea `COUNTERS/recibos_adelanto` a `{ next: 1 }` para que
//      la próxima impresión de comprobante sea N° 000001.
//
// NO toca:
//   - Viajes (`VIAJES_LOGISTICA`).
//   - Catálogos (empresas, ubicaciones, tarifas).
//   - Otros counters.
//   - Borradores de viaje (`BORRADORES_VIAJE`).
//
// SAFETY:
//   - Dry-run por default. Pasar `--apply` para escribir.
//   - Imprime resumen completo antes de cualquier acción destructiva.
//   - Idempotente: si lo corrés dos veces, la segunda no hace nada
//     (no quedan docs por borrar y el counter ya está en 1).
//   - NO se puede deshacer una vez aplicado (es hard-delete).
//
// USO:
//   cd whatsapp-bot
//   node ../scripts/limpiar_adelantos_y_resetear_counter.js          # dry-run
//   node ../scripts/limpiar_adelantos_y_resetear_counter.js --apply  # ejecuta

const path = require('path');
const fsNode = require('fs');

// Reusar node_modules del bot — admin SDK ya está instalado allá.
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
  console.error(`❌ No encuentro serviceAccountKey en ${absPath}.`);
  process.exit(1);
}
admin.initializeApp({
  credential: admin.credential.cert(require(absPath)),
  projectId: process.env.FIREBASE_PROJECT_ID || 'coopertrans-movil',
});
const db = admin.firestore();

const APPLY = process.argv.includes('--apply');

(async () => {
  console.log('');
  console.log('═'.repeat(70));
  console.log('  LIMPIAR ADELANTOS + RESETEAR COUNTER');
  console.log(`  Modo: ${APPLY ? 'APPLY (escribe)' : 'DRY-RUN (no escribe)'}`);
  console.log('═'.repeat(70));

  // ─── 1. Inventario de adelantos ─────────────────────────────────
  const colAdelantos = db.collection('ADELANTOS_CHOFER');
  const snap = await colAdelantos.get();
  const total = snap.size;

  console.log('');
  console.log(`📊 Total docs en ADELANTOS_CHOFER: ${total}`);

  if (total > 0) {
    let activos = 0;
    let eliminados = 0;
    let conRecibo = 0;
    let montoTotal = 0;
    for (const d of snap.docs) {
      const data = d.data();
      if (data.eliminado === true) {
        eliminados++;
      } else {
        activos++;
      }
      if (typeof data.numero_recibo === 'number') conRecibo++;
      if (typeof data.monto === 'number') montoTotal += data.monto;
    }
    console.log(`   - Activos              : ${activos}`);
    console.log(`   - Soft-deleted         : ${eliminados}`);
    console.log(`   - Con recibo impreso   : ${conRecibo}`);
    console.log(`   - Monto total          : $${montoTotal.toLocaleString('es-AR')}`);
  }

  // ─── 2. Counter actual ─────────────────────────────────────────
  const counterRef = db.collection('COUNTERS').doc('recibos_adelanto');
  const counterSnap = await counterRef.get();
  const counterActual = counterSnap.exists
    ? (counterSnap.data().next || '(sin campo next)')
    : '(no existe)';
  console.log('');
  console.log(`📊 COUNTERS/recibos_adelanto.next actual: ${counterActual}`);
  console.log('');

  // ─── 3. Plan ───────────────────────────────────────────────────
  console.log('─'.repeat(70));
  console.log('  PLAN');
  console.log('─'.repeat(70));
  console.log(`  • Borrar ${total} docs de ADELANTOS_CHOFER (hard-delete).`);
  console.log('  • Resetear COUNTERS/recibos_adelanto a `{ next: 1 }`.');
  console.log('    → próximo comprobante impreso será N° 000001.');
  console.log('');

  if (!APPLY) {
    console.log('─'.repeat(70));
    console.log('  DRY-RUN — nada se escribió.');
    console.log('  Para ejecutar, volvé a correr con `--apply`.');
    console.log('─'.repeat(70));
    process.exit(0);
  }

  if (total === 0 && counterActual === 1) {
    console.log('─'.repeat(70));
    console.log('  Ya está limpio (0 adelantos + counter en 1). Nada que hacer.');
    console.log('─'.repeat(70));
    process.exit(0);
  }

  // ─── 4. Ejecutar ───────────────────────────────────────────────
  console.log('─'.repeat(70));
  console.log('  EJECUTANDO...');
  console.log('─'.repeat(70));

  // Borrar adelantos en batches de 500 (límite Firestore).
  let borrados = 0;
  if (total > 0) {
    const BATCH_SIZE = 500;
    let batch = db.batch();
    let opsEnBatch = 0;
    for (const d of snap.docs) {
      batch.delete(d.ref);
      opsEnBatch++;
      borrados++;
      if (opsEnBatch >= BATCH_SIZE) {
        await batch.commit();
        console.log(`   ${borrados}/${total} borrados...`);
        batch = db.batch();
        opsEnBatch = 0;
      }
    }
    if (opsEnBatch > 0) {
      await batch.commit();
    }
    console.log(`✓ ${borrados} adelantos borrados.`);
  } else {
    console.log('  (no había adelantos para borrar)');
  }

  // Resetear counter — set merge:false para sobrescribir cualquier
  // estado previo. Persistimos `actualizado_en` y `reseteado_en`
  // para tener auditoría de cuándo se hizo el reset.
  await counterRef.set({
    next: 1,
    actualizado_en: admin.firestore.FieldValue.serverTimestamp(),
    reseteado_en: admin.firestore.FieldValue.serverTimestamp(),
    reseteado_motivo: 'Limpieza pre-producción real (Santiago 2026-05-14)',
  });
  console.log('✓ COUNTERS/recibos_adelanto reseteado a { next: 1 }.');

  console.log('');
  console.log('═'.repeat(70));
  console.log('  ✅ LISTO. Próximo comprobante impreso será N° 000001.');
  console.log('═'.repeat(70));
  process.exit(0);
})().catch((e) => {
  console.error('❌ Falló:', e.stack || e.message);
  process.exit(1);
});

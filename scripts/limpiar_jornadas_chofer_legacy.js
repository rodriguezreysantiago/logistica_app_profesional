// Limpieza one-shot de la colección legacy `JORNADAS_CHOFER` luego del
// refactor 2026-05-15 del vigilador (v1 → v2).
//
// El vigilador v2 usa una colección NUEVA llamada `JORNADAS` con docId
// `{dni}_{ts_inicio_ms}` y schema distinto (modelo de bloques). La vieja
// `JORNADAS_CHOFER` con docId `{dni}_{fecha_art}` queda huérfana — los
// docs no se borran solos.
//
// Santiago 2026-05-15: "borra la info, porque si no es lo que pide YPF no
// nos sirve" → borrado total de los docs legacy.
//
// USO (PowerShell, desde la raíz del repo):
//
//   cd "C:\Users\Colo Logistica\coopertrans_movil"
//   node scripts/limpiar_jornadas_chofer_legacy.js --dry-run    # ver qué borraría
//   node scripts/limpiar_jornadas_chofer_legacy.js --apply      # ejecutar
//
// Requiere serviceAccountKey.json en la raíz del repo (mismo patrón que
// los otros scripts admin).

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

const credPath = process.env.FIREBASE_CREDENTIALS_PATH || '../serviceAccountKey.json';
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

const dryRun = process.argv.includes('--dry-run');
const apply = process.argv.includes('--apply');

if (!dryRun && !apply) {
  console.error('❌ Pasá --dry-run para ver qué borraría, o --apply para ejecutar.');
  process.exit(1);
}

(async () => {
  console.log('');
  console.log('═'.repeat(70));
  console.log('  LIMPIEZA JORNADAS_CHOFER (legacy)');
  console.log('═'.repeat(70));
  console.log('');
  console.log(`  Modo: ${apply ? 'APPLY (BORRA DOCS)' : 'DRY-RUN (preview)'}`);
  console.log('');

  const snap = await db.collection('JORNADAS_CHOFER').get();
  console.log(`  Docs encontrados: ${snap.size}`);

  if (snap.empty) {
    console.log('  Nada que borrar.');
    process.exit(0);
  }

  // Preview: mostrar 5 docs
  console.log('');
  console.log('  Muestra de los primeros 5 docs:');
  let preview = 0;
  for (const d of snap.docs) {
    if (preview >= 5) break;
    const data = d.data();
    console.log(
      `    ${d.id}  chofer=${data.chofer_dni}  fecha=${data.fecha_art}  ` +
      `total=${data.segundos_total_dia}s`
    );
    preview++;
  }
  console.log('');

  if (dryRun) {
    console.log(`  --dry-run: NO se borra nada. Para ejecutar: --apply`);
    process.exit(0);
  }

  // Apply: batches de 500
  console.log('  Borrando...');
  const BATCH_SIZE = 500;
  let borrados = 0;
  const docs = snap.docs;
  for (let i = 0; i < docs.length; i += BATCH_SIZE) {
    const chunk = docs.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const d of chunk) batch.delete(d.ref);
    await batch.commit();
    borrados += chunk.length;
    console.log(`    ${borrados}/${docs.length}...`);
  }

  console.log('');
  console.log(`  ✅ Borrados ${borrados} docs de JORNADAS_CHOFER.`);
  console.log('');
  console.log('  El vigilador v2 escribe a la colección nueva `JORNADAS`.');
  console.log('  Esta limpieza es one-shot: no hace falta volver a correr.');
  process.exit(0);
})().catch((e) => {
  console.error('❌ Error:', e.stack || e.message);
  process.exit(1);
});

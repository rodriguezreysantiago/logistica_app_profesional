// Script one-shot para sembrar el "estado cero" del sistema de
// historial de asignaciones tractor↔enganche.
//
// Recorre EMPLEADOS y, por cada chofer que tenga AMBOS VEHICULO y
// ENGANCHE asignados válidos, crea un doc en ASIGNACIONES_ENGANCHE
// con:
//   - enganche_id  = EMPLEADOS.{dni}.ENGANCHE
//   - tractor_id   = EMPLEADOS.{dni}.VEHICULO
//   - desde: ahora (momento de la migración)
//   - hasta: null (= asignación activa)
//   - asignado_por_*: SISTEMA (estado heredado, no decisión humana)
//   - motivo: "Estado inicial al activar el sistema de historial"
//
// IMPORTANTE: el log NO puede reconstruir asignaciones anteriores a
// este momento. Las cubiertas instaladas antes del go-live no van a
// poder calcular km recorridos retroactivamente — solo desde acá en
// adelante. Esto es coherente con la opción B del estado inicial de
// gomería que confirmaste.
//
// IDEMPOTENTE: si para un (enganche_id, tractor_id) ya hay una
// asignación activa, no se duplica. Podés correrlo varias veces.
//
// USO (mismo patrón que migrar_asignaciones_iniciales.js):
//   cd whatsapp-bot
//   node ../scripts/migrar_asignaciones_enganches_iniciales.js          (dry-run)
//   node ../scripts/migrar_asignaciones_enganches_iniciales.js --apply  (escribe)

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

const COL_EMPLEADOS = 'EMPLEADOS';
const COL_VEHICULOS = 'VEHICULOS';
const COL_ASIGNACIONES_ENGANCHE = 'ASIGNACIONES_ENGANCHE';

const SIN_ASIGNAR = '-';
const MIGRACION_PSEUDO_DNI = 'SISTEMA_MIGRACION_INICIAL';

const dryRun = !process.argv.includes('--apply');

function patenteValida(raw) {
  if (raw == null) return false;
  const t = String(raw).trim();
  return t.length > 0 && t !== SIN_ASIGNAR && t.toUpperCase() !== 'S/D';
}

async function yaTieneActivaPara(engancheId, tractorId) {
  const snap = await db
    .collection(COL_ASIGNACIONES_ENGANCHE)
    .where('enganche_id', '==', engancheId)
    .where('tractor_id', '==', tractorId)
    .where('hasta', '==', null)
    .limit(1)
    .get();
  return !snap.empty;
}

async function leerModelo(patente) {
  try {
    const snap = await db.collection(COL_VEHICULOS).doc(patente).get();
    if (!snap.exists) return null;
    return snap.data().MODELO ?? null;
  } catch (_) {
    return null;
  }
}

async function main() {
  console.log(
    `🌱 Migración inicial ASIGNACIONES_ENGANCHE ${dryRun ? '(DRY-RUN)' : '(APPLY)'}`
  );
  console.log(`   Proyecto: ${admin.app().options.projectId}`);
  console.log('');

  const snap = await db.collection(COL_EMPLEADOS).get();
  console.log(`📊 ${snap.size} empleados leídos.\n`);

  let aCrear = 0;
  let yaExistentes = 0;
  let sinEnganche = 0;
  let sinTractor = 0;
  let creados = 0;
  const errores = [];

  for (const doc of snap.docs) {
    const dni = doc.id;
    const data = doc.data();
    const nombre = String(data.NOMBRE || '?');
    const vehiculo = data.VEHICULO;
    const enganche = data.ENGANCHE;

    if (!patenteValida(enganche)) {
      sinEnganche++;
      continue;
    }
    if (!patenteValida(vehiculo)) {
      // Tiene enganche pero no tractor — caso raro pero posible
      // (chofer asignado a un enganche sin tractor). Skip: sin tractor
      // no podemos asociar enganche↔tractor.
      sinTractor++;
      continue;
    }
    const engancheId = String(enganche).trim().toUpperCase();
    const tractorId = String(vehiculo).trim().toUpperCase();

    const yaTiene = await yaTieneActivaPara(engancheId, tractorId);
    if (yaTiene) {
      yaExistentes++;
      continue;
    }

    aCrear++;
    console.log(`  • ${dni} ${nombre}  →  enganche ${engancheId} en tractor ${tractorId}`);

    if (dryRun) continue;

    try {
      const tractorModelo = await leerModelo(tractorId);
      await db.collection(COL_ASIGNACIONES_ENGANCHE).add({
        enganche_id: engancheId,
        tractor_id: tractorId,
        tractor_modelo: tractorModelo,
        desde: admin.firestore.FieldValue.serverTimestamp(),
        hasta: null,
        asignado_por_dni: MIGRACION_PSEUDO_DNI,
        asignado_por_nombre: 'Migración inicial (estado heredado)',
        motivo: 'Estado inicial al activar el sistema de historial de enganches',
      });
      creados++;
    } catch (e) {
      errores.push({ dni, engancheId, tractorId, error: e.message });
      console.error(`      ❌ Falló: ${e.message}`);
    }
  }

  console.log('');
  console.log('───────────────── RESUMEN ─────────────────');
  console.log(`  Empleados procesados      : ${snap.size}`);
  console.log(`  Sin enganche asignado     : ${sinEnganche}`);
  console.log(`  Con enganche pero sin tractor (skip): ${sinTractor}`);
  console.log(`  Ya tenían asignación      : ${yaExistentes}`);
  console.log(`  A crear                   : ${aCrear}`);
  if (!dryRun) {
    console.log(`  Creadas con éxito         : ${creados}`);
    console.log(`  Errores                   : ${errores.length}`);
  }
  console.log('');

  if (dryRun) {
    console.log('ℹ️  Esto fue un DRY-RUN — no se escribió nada.');
    console.log('   Si el listado de arriba es el esperado, corré con --apply:');
    console.log('   node ../scripts/migrar_asignaciones_enganches_iniciales.js --apply');
  } else {
    console.log('✓ Migración completa.');
    if (errores.length > 0) {
      console.log('');
      console.log('⚠ Documentos que fallaron:');
      errores.forEach((e) =>
        console.log(`   - ${e.dni} (${e.engancheId}↔${e.tractorId}): ${e.error}`)
      );
    }
  }

  process.exit(0);
}

main().catch((e) => {
  console.error('❌ Error fatal:', e);
  process.exit(1);
});

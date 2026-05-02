// Script one-shot para sembrar el "estado cero" del sistema de
// historial de asignaciones chofer↔vehículo.
//
// Recorre EMPLEADOS y, por cada chofer con VEHICULO asignado válido,
// crea un doc en ASIGNACIONES_VEHICULO con:
//   - desde: ahora (momento de la migración)
//   - hasta: null (= asignación activa)
//   - asignado_por_*: SISTEMA (estado heredado, no decisión humana)
//   - motivo: "Estado inicial al activar el sistema de historial"
//
// IMPORTANTE: el log NO puede reconstruir asignaciones anteriores a
// este momento. Las multas/eventos previos al go-live siguen siendo
// "vehículo asignado al momento de la consulta". Para mitigar: cuanto
// antes se corra esto en producción, antes empezamos a acumular
// trazabilidad útil.
//
// IDEMPOTENTE: si para un (vehiculo_id, chofer_dni) ya hay una
// asignación activa, no se duplica. Podés correrlo varias veces.
//
// USO:
//   cd whatsapp-bot   (necesitamos sus node_modules + serviceAccountKey)
//   node ../scripts/migrar_asignaciones_iniciales.js              (dry-run)
//   node ../scripts/migrar_asignaciones_iniciales.js --apply      (escribe)

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
require('dotenv').config();

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
const COL_ASIGNACIONES = 'ASIGNACIONES_VEHICULO';

const SIN_ASIGNAR = '-';

// "Pseudo-DNI" para marcar las asignaciones sembradas por la migración.
// Distinto de cualquier DNI real para que se filtren fácil después.
const MIGRACION_PSEUDO_DNI = 'SISTEMA_MIGRACION_INICIAL';

const dryRun = !process.argv.includes('--apply');

function patenteValida(raw) {
  if (raw == null) return false;
  const t = String(raw).trim();
  return t.length > 0 && t !== SIN_ASIGNAR && t.toUpperCase() !== 'S/D';
}

async function yaTieneActivaPara(vehiculoId, choferDni) {
  const snap = await db
    .collection(COL_ASIGNACIONES)
    .where('vehiculo_id', '==', vehiculoId)
    .where('chofer_dni', '==', choferDni)
    .where('hasta', '==', null)
    .limit(1)
    .get();
  return !snap.empty;
}

async function main() {
  console.log(`🌱 Migración inicial ASIGNACIONES_VEHICULO ${dryRun ? '(DRY-RUN)' : '(APPLY)'}`);
  console.log(`   Proyecto: ${admin.app().options.projectId}`);
  console.log('');

  const snap = await db.collection(COL_EMPLEADOS).get();
  console.log(`📊 ${snap.size} empleados leídos.\n`);

  let aCrear = 0;
  let yaExistentes = 0;
  let sinUnidad = 0;
  let creados = 0;
  const errores = [];

  for (const doc of snap.docs) {
    const dni = doc.id;
    const data = doc.data();
    const nombre = String(data.NOMBRE || '?');
    const vehiculo = data.VEHICULO;

    if (!patenteValida(vehiculo)) {
      sinUnidad++;
      continue;
    }
    const patente = String(vehiculo).trim().toUpperCase();

    const yaTiene = await yaTieneActivaPara(patente, dni);
    if (yaTiene) {
      yaExistentes++;
      continue;
    }

    aCrear++;
    console.log(`  • ${dni}  ${nombre}  →  ${patente}`);

    if (dryRun) continue;

    try {
      await db.collection(COL_ASIGNACIONES).add({
        vehiculo_id: patente,
        chofer_dni: dni,
        chofer_nombre: nombre,
        desde: admin.firestore.FieldValue.serverTimestamp(),
        hasta: null,
        asignado_por_dni: MIGRACION_PSEUDO_DNI,
        asignado_por_nombre: 'Migración inicial (estado heredado)',
        motivo: 'Estado inicial al activar el sistema de historial',
      });
      creados++;
    } catch (e) {
      errores.push({ dni, patente, error: e.message });
      console.error(`      ❌ Falló: ${e.message}`);
    }
  }

  console.log('');
  console.log('───────────────── RESUMEN ─────────────────');
  console.log(`  Empleados procesados : ${snap.size}`);
  console.log(`  Sin unidad asignada  : ${sinUnidad}`);
  console.log(`  Ya tenían asignación : ${yaExistentes}`);
  console.log(`  A crear              : ${aCrear}`);
  if (!dryRun) {
    console.log(`  Creadas con éxito    : ${creados}`);
    console.log(`  Errores              : ${errores.length}`);
  }
  console.log('');

  if (dryRun) {
    console.log('ℹ️  Esto fue un DRY-RUN — no se escribió nada.');
    console.log('   Si el listado de arriba es el esperado, corré con --apply:');
    console.log('   node ../scripts/migrar_asignaciones_iniciales.js --apply');
  } else {
    console.log('✓ Migración completa.');
    if (errores.length > 0) {
      console.log('');
      console.log('⚠ Documentos que fallaron:');
      errores.forEach((e) =>
        console.log(`   - ${e.dni} (${e.patente}): ${e.error}`)
      );
    }
  }

  process.exit(0);
}

main().catch((e) => {
  console.error('❌ Falló:', e.stack || e.message);
  process.exit(1);
});

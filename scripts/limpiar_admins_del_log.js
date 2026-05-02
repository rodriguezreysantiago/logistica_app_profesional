// Script one-shot que saca a los admins/supervisores/planta del sistema
// de asignaciones chofer↔vehículo.
//
// Disparador: la migración inicial sembró ASIGNACIONES_VEHICULO desde
// EMPLEADOS.VEHICULO sin filtrar por rol. Eso metió a Santiago (admin)
// como "chofer" del tractor de pruebas AI162YT. La regla operativa es
// que solo CHOFER cuenta como conductor — admins/supervisores/planta
// no manejan, no deben aparecer en el log ni en cálculos.
//
// Por cada empleado con ROL != CHOFER (y != USUARIO legacy) que tenga
// VEHICULO asignado:
//   1. BORRA todos sus docs en ASIGNACIONES_VEHICULO. El log debería
//      reflejar manejo real, no un estado inicial mal sembrado.
//   2. Setea EMPLEADOS.{dni}.VEHICULO = '-'.
//   3. Si la patente que tenía asignada quedó sin nadie, la libera
//      (VEHICULOS.{patente}.ESTADO = 'LIBRE').
//
// IDEMPOTENTE. Dry-run por default; --apply para escribir.
//
// USO:
//   cd whatsapp-bot
//   node ../scripts/limpiar_admins_del_log.js              (dry-run)
//   node ../scripts/limpiar_admins_del_log.js --apply      (escribe)

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

admin.initializeApp({
  credential: admin.credential.cert(require(absPath)),
  projectId: process.env.FIREBASE_PROJECT_ID || 'coopertrans-movil',
});

const db = admin.firestore();
const SIN_ASIGNAR = '-';

// "Chofer" para el sistema = ROL CHOFER o el legacy USUARIO. Cualquier
// otro rol (ADMIN, SUPERVISOR, PLANTA) no se cuenta como conductor.
function esChofer(rol) {
  const r = String(rol || '').toUpperCase().trim();
  return r === 'CHOFER' || r === 'USUARIO';
}

function patenteValida(raw) {
  if (raw == null) return false;
  const t = String(raw).trim();
  return t.length > 0 && t !== SIN_ASIGNAR && t.toUpperCase() !== 'S/D';
}

const dryRun = !process.argv.includes('--apply');

async function patenteSiguenSiendoOcupada(patente, dniExcluido) {
  // Después de quitar al admin, ¿queda algún OTRO empleado con esa
  // patente en EMPLEADOS.VEHICULO? Si sí, el ESTADO=OCUPADO sigue
  // siendo correcto y NO la liberamos.
  const snap = await db
    .collection('EMPLEADOS')
    .where('VEHICULO', '==', patente)
    .get();
  const otrosDuenios = snap.docs.filter((d) => d.id !== dniExcluido);
  return otrosDuenios.length > 0;
}

async function main() {
  console.log(`🧹 Limpieza admins/supervisores/planta del sistema de asignaciones ${dryRun ? '(DRY-RUN)' : '(APPLY)'}`);
  console.log(`   Proyecto: ${admin.app().options.projectId}`);
  console.log('');

  const snap = await db.collection('EMPLEADOS').get();
  console.log(`📊 ${snap.size} empleados leídos.\n`);

  const candidatos = [];
  for (const doc of snap.docs) {
    const data = doc.data();
    const rol = data.ROL;
    const vehiculo = data.VEHICULO;
    if (esChofer(rol)) continue;
    if (!patenteValida(vehiculo)) continue;
    candidatos.push({
      dni: doc.id,
      nombre: String(data.NOMBRE || '?'),
      rol: String(rol || '(vacío)'),
      patente: String(vehiculo).trim().toUpperCase(),
    });
  }

  if (candidatos.length === 0) {
    console.log('✓ Nada que limpiar — ningún no-chofer tiene unidad asignada.');
    process.exit(0);
  }

  console.log(`Encontrados ${candidatos.length} no-choferes con vehículo asignado:\n`);

  let asignacionesBorradas = 0;
  let empleadosLimpiados = 0;
  let unidadesLiberadas = 0;
  const errores = [];

  for (const { dni, nombre, rol, patente } of candidatos) {
    console.log(`  • ${dni}  ${nombre}  [${rol}]  →  ${patente}`);

    // Buscamos las asignaciones del log (puede haber varias históricas).
    const asigSnap = await db
      .collection('ASIGNACIONES_VEHICULO')
      .where('chofer_dni', '==', dni)
      .get();
    if (!asigSnap.empty) {
      console.log(`      ${asigSnap.size} doc(s) a borrar de ASIGNACIONES_VEHICULO`);
    }

    // ¿Hay otros empleados (ya choferes legítimos) con esa patente?
    const sigueOcupada = await patenteSiguenSiendoOcupada(patente, dni);
    if (sigueOcupada) {
      console.log(`      patente ${patente} sigue ocupada por otro chofer → no liberar`);
    } else {
      console.log(`      patente ${patente} queda libre → ESTADO=LIBRE`);
    }

    if (dryRun) continue;

    try {
      // 1. Borrar docs del log
      const batch = db.batch();
      for (const d of asigSnap.docs) batch.delete(d.ref);
      // 2. Limpiar EMPLEADOS
      batch.update(db.collection('EMPLEADOS').doc(dni), {
        VEHICULO: SIN_ASIGNAR,
      });
      // 3. Liberar VEHICULOS si nadie más lo usa
      if (!sigueOcupada) {
        batch.update(db.collection('VEHICULOS').doc(patente), {
          ESTADO: 'LIBRE',
        });
      }
      await batch.commit();
      asignacionesBorradas += asigSnap.size;
      empleadosLimpiados++;
      if (!sigueOcupada) unidadesLiberadas++;
    } catch (e) {
      errores.push({ dni, patente, error: e.message });
      console.error(`      ❌ Falló: ${e.message}`);
    }
  }

  console.log('');
  console.log('───────────────── RESUMEN ─────────────────');
  console.log(`  Candidatos               : ${candidatos.length}`);
  if (!dryRun) {
    console.log(`  Empleados limpiados      : ${empleadosLimpiados}`);
    console.log(`  Asignaciones borradas    : ${asignacionesBorradas}`);
    console.log(`  Unidades liberadas       : ${unidadesLiberadas}`);
    console.log(`  Errores                  : ${errores.length}`);
  }
  console.log('');

  if (dryRun) {
    console.log('ℹ️  Esto fue un DRY-RUN — no se escribió nada.');
    console.log('   Si el listado de arriba es el esperado, corré con --apply:');
    console.log('   node ../scripts/limpiar_admins_del_log.js --apply');
  } else {
    console.log('✓ Limpieza completa.');
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

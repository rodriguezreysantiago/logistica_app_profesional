// Diagnóstico del aviso "pasá el iButton" para un chofer puntual.
//
// Lee:
//   - SITRACK_POSICIONES/{patente} — ¿qué dice Sitrack del chofer?
//   - META_AVISOS_NO_ID/{dni} — throttle de 30 min del bot
//   - EMPLEADOS/{dni} — datos del chofer
//
// Útil para investigar avisos repetidos (caso Juan Flores 2026-05-13:
// 8 avisos en el día con timing irregular).
//
// USO:
//   cd whatsapp-bot
//   node ../scripts/diagnosticar_no_identificado.js <DNI_CHOFER> [PATENTE]

const path = require('path');
const fsNode = require('fs');

const botDir = path.resolve(__dirname, '..', 'whatsapp-bot');
const botNodeModules = path.join(botDir, 'node_modules');
if (!fsNode.existsSync(botNodeModules)) {
  console.error(`❌ No existe ${botNodeModules}`);
  process.exit(1);
}
module.paths.unshift(botNodeModules);
process.chdir(botDir);
require('dotenv').config({ quiet: true });

const admin = require('firebase-admin');
const credPath =
  process.env.FIREBASE_CREDENTIALS_PATH || '../serviceAccountKey.json';
admin.initializeApp({
  credential: admin.credential.cert(require(path.resolve(credPath))),
  projectId: process.env.FIREBASE_PROJECT_ID || 'coopertrans-movil',
});
const db = admin.firestore();

const dni = (process.argv[2] || '').trim();
const patenteArg = (process.argv[3] || '').trim();
if (!dni) {
  console.error('Uso: node diagnosticar_no_identificado.js <DNI> [PATENTE]');
  process.exit(1);
}

function fmtFecha(ts) {
  if (!ts) return '(null)';
  const d = ts.toDate ? ts.toDate() : new Date(ts);
  return new Intl.DateTimeFormat('es-AR', {
    timeZone: 'America/Argentina/Buenos_Aires',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).format(d);
}

function fmtMin(seg) {
  if (!seg) return '0s';
  const h = Math.floor(seg / 3600);
  const m = Math.floor((seg % 3600) / 60);
  const s = Math.floor(seg % 60);
  return h > 0
    ? `${h}h ${m.toString().padStart(2, '0')}m ${s.toString().padStart(2, '0')}s`
    : `${m}m ${s.toString().padStart(2, '0')}s`;
}

async function main() {
  console.log('\n🔎 DIAGNÓSTICO AVISO "PASÁ EL IBUTTON"');
  console.log('═════════════════════════════════════════');
  console.log(`  DNI : ${dni}`);
  console.log('');

  // 1) Empleado
  const empSnap = await db.collection('EMPLEADOS').doc(dni).get();
  let patente = patenteArg;
  if (empSnap.exists) {
    const e = empSnap.data();
    console.log('👤 EMPLEADO');
    console.log(`  Nombre   : ${e.NOMBRE ?? '(sin nombre)'}`);
    console.log(`  Vehículo : ${e.VEHICULO ?? '(sin asignar)'}`);
    console.log(`  ROL      : ${e.ROL ?? '(sin rol)'}`);
    if (!patente && e.VEHICULO && e.VEHICULO !== '-') {
      patente = String(e.VEHICULO).trim().toUpperCase();
    }
    console.log('');
  }
  if (!patente) {
    console.log('⚠ No hay patente asignada al chofer ni provista por arg.');
    process.exit(1);
  }

  // 2) Sitrack posición actual de la patente
  const sSnap = await db.collection('SITRACK_POSICIONES').doc(patente).get();
  if (!sSnap.exists) {
    console.log(`📍 SITRACK_POSICIONES/${patente} — NO existe`);
  } else {
    const s = sSnap.data();
    const driverDni = (s.driver_dni ?? '').toString().trim();
    const driverNombre = (s.driver_nombre ?? '').toString().trim();
    const speed = s.speed ?? 0;
    const consultadoMs = s.consultado_en?.toMillis?.() ?? 0;
    const haceSeg =
      consultadoMs > 0 ? (Date.now() - consultadoMs) / 1000 : Infinity;

    console.log(`📍 SITRACK_POSICIONES/${patente}`);
    console.log(`  driver_dni       : ${driverDni || '(VACÍO ← sin loguear)'}`);
    console.log(`  driver_nombre    : ${driverNombre || '(vacío)'}`);
    console.log(`  speed            : ${speed} km/h`);
    console.log(`  consultado_en    : ${fmtFecha(s.consultado_en)}`);
    console.log(`  hace             : ${fmtMin(haceSeg)}`);
    console.log('');

    // Diagnóstico automático del estado
    console.log('───────────── ESTADO ─────────────');
    if (!driverDni) {
      console.log(`  ⚠ Sitrack dice driver_dni = "" → SIN LOGUEAR`);
      console.log(`     El aviso "pasá el iButton" SÍ corresponde.`);
    } else if (driverDni === dni) {
      console.log(`  ✓ Sitrack dice driver_dni = ${driverDni} → ESTÁ LOGUEADO CON ESTE DNI`);
      console.log(`     Los avisos serían FALSOS POSITIVOS — algo más está mal.`);
    } else {
      console.log(`  ⚠ Sitrack dice driver_dni = ${driverDni}`);
      console.log(`     PERO el VEHICULO de ese DNI (en EMPLEADOS) puede ser otro.`);
      console.log(`     El bot puede estar avisando al chofer ASIGNADO (${dni})`);
      console.log(`     cuando en realidad maneja OTRO chofer logueado.`);
    }
    console.log('');
  }

  // 3) Meta del throttle (campo real en código: `last_sent_at` —
  // alias histórico)
  const mSnap = await db.collection('META_AVISOS_NO_ID').doc(dni).get();
  if (!mSnap.exists) {
    console.log(`🚦 META_AVISOS_NO_ID/${dni} — NO existe (nunca se avisó)`);
  } else {
    const m = mSnap.data();
    console.log(`🚦 META_AVISOS_NO_ID/${dni}`);
    console.log('  Campos completos del doc:');
    for (const [k, v] of Object.entries(m)) {
      const display =
        v && typeof v.toMillis === 'function' ? fmtFecha(v) : String(v);
      console.log(`    ${k.padEnd(20)} : ${display}`);
    }
    const ts = m.last_sent_at;
    if (ts && typeof ts.toMillis === 'function') {
      const haceSeg = (Date.now() - ts.toMillis()) / 1000;
      console.log(`  → último envío hace ${fmtMin(haceSeg)} (throttle 30 min)`);
      if (haceSeg < 30 * 60) {
        console.log('  ✓ throttle activo, debería bloquear próximos avisos.');
      } else {
        console.log('  ⚠ throttle expirado, próximo cron va a poder avisar.');
      }
    } else {
      console.log('  ⚠ NO hay `last_sent_at` válido → el throttle no se aplica.');
    }
    console.log('');
  }

  // 4) Últimos avisos enviados en COLA_WHATSAPP de este chofer hoy.
  // Query simple por destinatario_id (índice automático single-field)
  // y filtro origen + fecha client-side para no requerir índice
  // compuesto.
  console.log(`📨 COLA_WHATSAPP — avisos no_id de ${dni} (últimos 50):`);
  try {
    const colaSnap = await db
      .collection('COLA_WHATSAPP')
      .where('destinatario_id', '==', dni)
      .limit(500)
      .get();
    const inicioHoyMs = (() => {
      const h = new Date();
      h.setHours(0, 0, 0, 0);
      return h.getTime();
    })();
    const docs = colaSnap.docs
      .map((d) => ({ id: d.id, ...d.data() }))
      .filter((d) => {
        if (d.origen !== 'sitrack_chofer_no_identificado') return false;
        const ms = d.encolado_en?.toMillis?.() ?? 0;
        return ms >= inicioHoyMs;
      })
      .sort((a, b) =>
        (a.encolado_en?.toMillis?.() ?? 0) -
        (b.encolado_en?.toMillis?.() ?? 0)
      );
    if (docs.length === 0) {
      console.log('  (sin avisos no_id encolados hoy)');
    } else {
      console.log(`  ${docs.length} aviso(s):`);
      let prevEnc = 0;
      let prevEnv = 0;
      for (const d of docs) {
        const encMs = d.encolado_en?.toMillis?.() ?? 0;
        const envMs = d.enviado_en?.toMillis?.() ?? 0;
        const enc = fmtFecha(d.encolado_en);
        const env = envMs ? fmtFecha(d.enviado_en) : '(no enviado)';
        const gapEnc = prevEnc ? ` Δenc=${fmtMin((encMs - prevEnc) / 1000)}` : '';
        const gapEnv =
          prevEnv && envMs ? ` Δenv=${fmtMin((envMs - prevEnv) / 1000)}` : '';
        console.log(
          `    [enc ${enc}] [${d.estado}] env: ${env}${gapEnc}${gapEnv}`
        );
        prevEnc = encMs;
        if (envMs) prevEnv = envMs;
      }
    }
  } catch (e) {
    console.log(`  (error consultando: ${e.message})`);
  }

  console.log('');
  process.exit(0);
}

main().catch((e) => {
  console.error('❌ Falló:', e.stack || e.message);
  process.exit(1);
});

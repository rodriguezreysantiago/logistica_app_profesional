// Verifica que el destinatario del aviso diario de service preventivo
// (configurado en SERVICE_DESTINATARIO_DNI del .env) este correctamente
// cargado en la coleccion EMPLEADOS de Firestore.
//
// Uso (desde la carpeta whatsapp-bot/):
//   node scripts/verificar_destinatario_service.js
//
// Que chequea:
//   1. Que SERVICE_DESTINATARIO_DNI este definido en .env.
//   2. Que el documento EMPLEADOS/{DNI} exista.
//   3. Que tenga TELEFONO valido.
//   4. Que tenga APODO o NOMBRE para el saludo.
//   5. Cuantos tractores con urgencia tendrian aviso ahora mismo
//      (preview de lo que recibiria Emmanuel en el proximo ciclo).
//
// No envia ningun mensaje. Solo lee y reporta.

require('dotenv').config();

const path = require('path');
const fs = require('fs');
const admin = require('firebase-admin');

const DNI = process.env.SERVICE_DESTINATARIO_DNI;

if (!DNI) {
  console.error('ERROR: SERVICE_DESTINATARIO_DNI no esta definido en .env');
  console.error('Agregar en .env:  SERVICE_DESTINATARIO_DNI=29820141');
  process.exit(1);
}

console.log(`Verificando destinatario de service diario: DNI ${DNI}`);
console.log('');

// Inicializar Firebase Admin con la misma logica que el bot.
const credsPath = process.env.FIREBASE_CREDENTIALS_PATH || '../serviceAccountKey.json';
const credsAbs = path.resolve(__dirname, '..', credsPath);
if (!fs.existsSync(credsAbs)) {
  console.error(`ERROR: no encontre serviceAccountKey en: ${credsAbs}`);
  console.error('Verificar FIREBASE_CREDENTIALS_PATH en .env');
  process.exit(1);
}
admin.initializeApp({
  credential: admin.credential.cert(require(credsAbs)),
  projectId: process.env.FIREBASE_PROJECT_ID || undefined,
});
const db = admin.firestore();

async function verificar() {
  // ─── 1. Documento EMPLEADOS/{DNI} ────────────────────────────────
  console.log('1) Documento EMPLEADOS/' + DNI);
  const docRef = db.collection('EMPLEADOS').doc(DNI);
  const snap = await docRef.get();
  if (!snap.exists) {
    console.log('   X NO EXISTE.');
    console.log('   Solucion: crear el legajo desde la app (Admin > Personal > Nuevo).');
    process.exit(1);
  }
  const data = snap.data();
  console.log('   OK Existe.');

  // ─── 2. TELEFONO ─────────────────────────────────────────────────
  console.log('');
  console.log('2) TELEFONO');
  const tel = data.TELEFONO ? String(data.TELEFONO).trim() : null;
  if (!tel) {
    console.log('   X NO TIENE TELEFONO. Sin esto, el bot no puede mandar.');
    console.log('   Solucion: editar el legajo desde la app y cargar el telefono.');
    process.exit(1);
  }
  console.log(`   OK ${tel}`);

  // ─── 3. APODO o NOMBRE ────────────────────────────────────────────
  console.log('');
  console.log('3) Saludo del mensaje');
  const apodo = data.APODO ? String(data.APODO).trim() : null;
  const nombre = data.NOMBRE ? String(data.NOMBRE).trim() : null;
  if (apodo) {
    console.log(`   OK Apodo configurado: "${apodo}"`);
    console.log(`      El mensaje arrancara con "Hola ${apodo}."`);
  } else if (nombre) {
    const partes = nombre.split(/\s+/).filter(Boolean);
    if (partes.length >= 2) {
      console.log(`   OK Sin apodo, pero NOMBRE="${nombre}"`);
      console.log(`      El mensaje arrancara con "Hola ${partes[1]}." (segundo token de NOMBRE)`);
    } else {
      console.log(`   ! NOMBRE="${nombre}" (1 sola palabra)`);
      console.log(`      El bot va a usar "Hola" generico. Considerar cargar APODO.`);
    }
  } else {
    console.log('   ! Sin APODO ni NOMBRE. Mensaje generico "Hola".');
  }

  // ─── 4. ROL (informativo) ────────────────────────────────────────
  console.log('');
  console.log('4) Rol y area (informativo)');
  console.log(`   ROL: ${data.ROL || '(no seteado)'}`);
  console.log(`   AREA: ${data.AREA || '(no seteada)'}`);

  // ─── 5. Preview de tractores con urgencia ────────────────────────
  console.log('');
  console.log('5) Preview: tractores con urgencia (lo que recibiria HOY)');
  const vehiculosSnap = await db.collection('VEHICULOS').get();
  const tractores = vehiculosSnap.docs
    .map((d) => ({ id: d.id, data: d.data() }))
    .filter((v) => String(v.data.TIPO || '').toUpperCase() === 'TRACTOR');

  const conUrgencia = [];
  const INTERVALO_KM = 50000;
  for (const t of tractores) {
    const ultimo = Number(t.data.ULTIMO_SERVICE_KM);
    const actual = Number(t.data.KM_ACTUAL);
    let serviceDistance = null;
    if (!isNaN(ultimo) && !isNaN(actual) && ultimo != null && actual != null) {
      serviceDistance = ultimo + INTERVALO_KM - actual;
    } else if (t.data.SERVICE_DISTANCE_KM != null) {
      serviceDistance = Number(t.data.SERVICE_DISTANCE_KM);
    }
    if (serviceDistance == null || isNaN(serviceDistance)) continue;
    if (serviceDistance > 5000) continue;

    let urgencia = 'service_atencion';
    if (serviceDistance <= 0) urgencia = 'service_vencido';
    else if (serviceDistance <= 1000) urgencia = 'service_urgente';
    else if (serviceDistance <= 2500) urgencia = 'service_programar';

    conUrgencia.push({
      patente: t.id,
      km: Math.round(serviceDistance),
      urgencia,
      marca: t.data.MARCA || '',
      modelo: t.data.MODELO || '',
    });
  }

  console.log(`   Total tractores: ${tractores.length}`);
  console.log(`   Con urgencia: ${conUrgencia.length}`);

  if (conUrgencia.length === 0) {
    console.log('');
    console.log('   El proximo ciclo del cron va a mandar mensaje "todo en orden" a Emmanuel.');
  } else {
    console.log('');
    for (const t of conUrgencia.sort((a, b) => a.km - b.km)) {
      const marker = {
        service_vencido: '[VENCIDO]  ',
        service_urgente: '[URGENTE]  ',
        service_programar: '[PROGRAMAR]',
        service_atencion: '[ATENCION] ',
      }[t.urgencia] || '[?]';
      const ref = t.marca && t.modelo
        ? `${t.marca} ${t.modelo} (${t.patente})`
        : t.patente;
      console.log(`   ${marker}  ${ref}: ${t.km > 0 ? 'faltan ' + t.km : 'paso por ' + Math.abs(t.km)} km`);
    }
    console.log('');
    console.log(`   El proximo ciclo del cron va a mandar mensaje a Emmanuel con esta lista.`);
  }

  // ─── Resumen ──────────────────────────────────────────────────────
  console.log('');
  console.log('========================================');
  console.log('OK Destinatario verificado correctamente.');
  console.log('========================================');
  console.log('');
  console.log('Si AUTO_AVISOS_ENABLED=true y el cron corre en horario habil,');
  console.log('Emmanuel va a recibir el primer mensaje en el proximo ciclo.');

  process.exit(0);
}

verificar().catch((e) => {
  console.error('Error verificando:', e.message);
  process.exit(1);
});

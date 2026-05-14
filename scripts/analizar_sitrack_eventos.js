// Análisis de SITRACK_EVENTOS — qué eventos llegaron en las últimas
// N horas, ranking por frecuencia, y diagnóstico de qué consumidores
// son viables con la data real.
//
// El propósito es responder: "después de 24-48h con el cron andando,
// ¿qué tipos de evento están llegando? ¿hay suficiente data de jornada
// para armar el vigilador v2? ¿llegan eventos de viaje? ¿de combustible?"
//
// Sin este análisis, no sabemos qué hardware está configurado para
// emitir qué eventos por unidad — nos podemos meter a codear features
// que no van a tener data.
//
// USO (PowerShell, desde la raíz del repo):
//
//   cd "C:\Users\Colo Logistica\coopertrans_movil"
//   node scripts/analizar_sitrack_eventos.js [--horas N]
//
// Default: 24 horas. Para 48: --horas 48
//
// Requiere serviceAccountKey.json en la raíz (mismo patrón que
// scripts/diagnosticar_vigilador_chofer.js).

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
  console.error('   Seteá FIREBASE_CREDENTIALS_PATH o dejá la key en la raíz.');
  process.exit(1);
}
admin.initializeApp({
  credential: admin.credential.cert(require(absPath)),
  projectId: process.env.FIREBASE_PROJECT_ID || 'coopertrans-movil',
});
const db = admin.firestore();

// ─── Parámetros ──────────────────────────────────────────────────
let horas = 24;
const horasIdx = process.argv.indexOf('--horas');
if (horasIdx > 0 && process.argv[horasIdx + 1]) {
  const n = parseInt(process.argv[horasIdx + 1], 10);
  if (Number.isFinite(n) && n > 0 && n <= 720) {
    horas = n;
  } else {
    console.error('❌ --horas debe ser entero positivo entre 1 y 720');
    process.exit(1);
  }
}

// ─── Categorías de eventos relevantes para próximos consumidores ──
// Cada categoría agrupa los event_id del catálogo Sitrack que dispararían
// la lógica de un consumidor. Si una categoría tiene 0 eventos en la
// ventana → ese consumidor no es viable hoy (probable: hardware/config
// por unidad faltante).
const CATEGORIAS = {
  'JORNADA (vigilador v2)': new Set([
    152, 153, 154, 155, 190, 191, 513, 514, 904, 960, 1015,
    1098, 1099, 1100, 1242, 1243, 1244, 1245, 1246, 1239, 1419, 1420,
    267, 419, 420, 900,
  ]),
  'VIAJES (auto-poblar logística)': new Set([
    23, 24, 75, 76, 77, 78, 128, 129, 200, 201, 202, 203, 260, 269,
    270, 271, 272, 273, 274, 315, 377, 510, 511, 512, 546, 648, 751,
    852, 853, 854, 855, 856, 1052,
  ]),
  'COMBUSTIBLE (anti-robo)': new Set([
    27, 103, 104, 148, 316, 317, 390, 391, 412, 543, 640, 755, 859, 860,
    335, 991, 992,
  ]),
  'CONDUCCIÓN PELIGROSA': new Set([
    8, 9, 64, 65, 66, 67, 178, 213, 214, 217, 218, 225, 275, 338, 339,
    345, 346, 383, 458, 486, 487, 518, 519, 756, 757, 758, 759, 947,
    324, 325, 326, 327, 328, 329, 440, 441, 442, 443, 444, 445, 537,
    540, 541, 901, 902, 1006, 1007, 1017,
  ]),
  'FATIGA / CABINA (MobileEye)': new Set([
    504, 978, 993, 994, 995, 996, 997, 998, 1009, 1011, 1013, 1219,
    1236, 1237, 1238, 1247, 1248, 1260, 1264, 1265, 1281, 1293, 1335,
    1348,
  ]),
  'MANTENIMIENTO': new Set([
    207, 208, 210, 342, 343, 344, 347, 348, 349, 544, 545, 988, 989,
    410, 411,
  ]),
  'PUERTAS / SEGURIDAD': new Set([
    11, 12, 15, 16, 17, 18, 19, 20, 21, 22, 165, 168, 169, 520, 632,
    848, 849, 850, 845, 847, 1062, 1063, 1198, 1199, 1200, 1201,
  ]),
};

(async () => {
  const corteMs = Date.now() - horas * 3600 * 1000;
  const corteTs = admin.firestore.Timestamp.fromMillis(corteMs);

  console.log('');
  console.log('═'.repeat(70));
  console.log(`  ANÁLISIS SITRACK_EVENTOS — últimas ${horas} hs`);
  console.log(`  Corte: >= ${new Date(corteMs).toLocaleString('es-AR', {
    timeZone: 'America/Argentina/Buenos_Aires',
  })} ART`);
  console.log('═'.repeat(70));

  // Indexamos por recibido_en (cuándo el cron lo persistió). Es lo
  // que tenemos disponible como server timestamp confiable. Si en
  // algún punto agregamos índice por report_date, podemos cambiar.
  const snap = await db
    .collection('SITRACK_EVENTOS')
    .where('recibido_en', '>=', corteTs)
    .get();

  if (snap.empty) {
    console.log('');
    console.log('⚠ Sin eventos en la ventana. El cron quizás no corrió');
    console.log('  todavía o falló. Chequeá:');
    console.log('  - META/sitrack_eventos_cursor.ultimo_exito_at');
    console.log('  - firebase functions:log --only sitrackEventosPoller --lines 50');
    process.exit(0);
  }

  const total = snap.size;
  console.log('');
  console.log(`📊 Total eventos: ${total}`);
  console.log(`   Tasa: ${(total / horas).toFixed(1)} eventos/hora`);

  // ─── Ranking por event_id ────────────────────────────────────
  const porEvento = new Map();
  const porPatente = new Map();
  const porChofer = new Map();
  let conChofer = 0;
  let conTrailer = 0;
  let conLimit = 0;
  let sobreLimit = 0;

  for (const d of snap.docs) {
    const e = d.data();
    const eid = typeof e.event_id === 'number' ? e.event_id : -1;
    const ename = (e.event_name || '(sin nombre)').toString();
    const key = `${eid}|${ename}`;
    porEvento.set(key, (porEvento.get(key) || 0) + 1);

    const patente = (e.asset_id || '').toString();
    if (patente) porPatente.set(patente, (porPatente.get(patente) || 0) + 1);

    const dni = (e.driver_dni || '').toString().trim();
    if (dni) {
      conChofer++;
      const nombre = `${e.driver_name || ''} ${e.driver_last_name || ''}`.trim() || dni;
      const choferKey = `${dni}|${nombre}`;
      porChofer.set(choferKey, (porChofer.get(choferKey) || 0) + 1);
    }
    if ((e.trailer_id || '').toString().trim()) conTrailer++;
    if (typeof e.cartography_limit_speed === 'number' && e.cartography_limit_speed > 0) {
      conLimit++;
      if (typeof e.speed === 'number' && e.speed > e.cartography_limit_speed) {
        sobreLimit++;
      }
    }
  }

  // ─── Top 30 eventos ──────────────────────────────────────────
  console.log('');
  console.log('─'.repeat(70));
  console.log(`  TOP TIPOS DE EVENTO (todos los ${porEvento.size} distintos)`);
  console.log('─'.repeat(70));
  const sorted = [...porEvento.entries()].sort((a, b) => b[1] - a[1]);
  const topN = Math.min(sorted.length, 30);
  for (let i = 0; i < topN; i++) {
    const [key, count] = sorted[i];
    const [eid, ename] = key.split('|');
    const pct = ((count / total) * 100).toFixed(1);
    console.log(`  ${count.toString().padStart(6)}  (${pct.padStart(5)}%)  [${eid.padStart(4)}] ${ename}`);
  }
  if (sorted.length > topN) {
    const restante = sorted.slice(topN).reduce((s, [, c]) => s + c, 0);
    console.log(`  ${restante.toString().padStart(6)}  …  + ${sorted.length - topN} tipo(s) más`);
  }

  // ─── Cobertura por categoría (próximos consumidores) ─────────
  console.log('');
  console.log('─'.repeat(70));
  console.log('  COBERTURA POR CATEGORÍA (¿qué consumidores son viables?)');
  console.log('─'.repeat(70));
  for (const [nombre, idsSet] of Object.entries(CATEGORIAS)) {
    let cuenta = 0;
    const idsPresentes = new Map();
    for (const [key, c] of porEvento.entries()) {
      const eid = parseInt(key.split('|')[0], 10);
      if (idsSet.has(eid)) {
        cuenta += c;
        const ename = key.split('|')[1];
        idsPresentes.set(`${eid} ${ename}`, c);
      }
    }
    const pct = ((cuenta / total) * 100).toFixed(1);
    const marca = cuenta > 0 ? '✅' : '❌';
    console.log('');
    console.log(`  ${marca} ${nombre}`);
    console.log(`     ${cuenta} eventos  (${pct}% del total)  — ${idsPresentes.size} de ${idsSet.size} tipos del catálogo presentes`);
    if (idsPresentes.size > 0) {
      const tops = [...idsPresentes.entries()].sort((a, b) => b[1] - a[1]).slice(0, 5);
      for (const [label, c] of tops) {
        console.log(`        ${c.toString().padStart(6)}  ${label}`);
      }
      if (idsPresentes.size > 5) {
        console.log(`        ...  + ${idsPresentes.size - 5} tipo(s) más`);
      }
    } else {
      console.log('        Sin eventos de esta categoría — feature NO viable hoy.');
    }
  }

  // ─── Choferes / patentes / metadatos ─────────────────────────
  console.log('');
  console.log('─'.repeat(70));
  console.log('  COBERTURA OPERATIVA');
  console.log('─'.repeat(70));
  const pctChofer = ((conChofer / total) * 100).toFixed(1);
  const pctTrailer = ((conTrailer / total) * 100).toFixed(1);
  const pctLimit = ((conLimit / total) * 100).toFixed(1);
  console.log(`  Eventos con chofer identificado (driver_dni): ${conChofer} (${pctChofer}%)`);
  console.log(`  Eventos con trailer_id (sensor enganche)    : ${conTrailer} (${pctTrailer}%)`);
  console.log(`  Eventos con límite de velocidad cartográfico: ${conLimit} (${pctLimit}%)`);
  if (conLimit > 0) {
    const pctSobre = ((sobreLimit / conLimit) * 100).toFixed(1);
    console.log(`     De esos, sobre el límite (sobrevelocidad): ${sobreLimit} (${pctSobre}%)`);
  }

  console.log(`  Patentes distintas: ${porPatente.size}`);
  const topPats = [...porPatente.entries()].sort((a, b) => b[1] - a[1]).slice(0, 10);
  for (const [pat, c] of topPats) {
    console.log(`     ${pat.padEnd(10)} ${c}`);
  }

  console.log(`  Choferes distintos identificados: ${porChofer.size}`);
  const topChof = [...porChofer.entries()].sort((a, b) => b[1] - a[1]).slice(0, 10);
  for (const [key, c] of topChof) {
    const [dni, nombre] = key.split('|');
    console.log(`     DNI ${dni.padEnd(10)} ${nombre.padEnd(30)} ${c}`);
  }

  // ─── Recomendación ───────────────────────────────────────────
  console.log('');
  console.log('═'.repeat(70));
  console.log('  RECOMENDACIÓN');
  console.log('═'.repeat(70));
  const orden = Object.entries(CATEGORIAS)
    .map(([nombre, idsSet]) => {
      let cuenta = 0;
      for (const [key, c] of porEvento.entries()) {
        const eid = parseInt(key.split('|')[0], 10);
        if (idsSet.has(eid)) cuenta += c;
      }
      return { nombre, cuenta };
    })
    .filter((c) => c.cuenta > 0)
    .sort((a, b) => b.cuenta - a.cuenta);

  if (orden.length === 0) {
    console.log('  ⚠ Ninguna categoría tiene eventos. Nada para arrancar a codear.');
    console.log('  Posibles razones:');
    console.log('   - Cron arrancó hace muy poco — esperar más tiempo.');
    console.log('   - Equipos no emiten eventos avanzados — pedir activación');
    console.log('     de eventos específicos a Sitrack por unidad.');
  } else {
    console.log('  Categorías con data, en orden de prioridad sugerida:');
    for (let i = 0; i < orden.length; i++) {
      console.log(`    ${i + 1}. ${orden[i].nombre.padEnd(45)} (${orden[i].cuenta} eventos)`);
    }
    console.log('');
    console.log(`  → Empezar por "${orden[0].nombre}".`);
  }

  console.log('');
  process.exit(0);
})().catch((e) => {
  console.error('❌ Falló:', e.stack || e.message);
  process.exit(1);
});

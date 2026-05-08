// Resetea el doc JORNADAS_CHOFER de un chofer del día actual.
//
// Caso de uso: el vigilador acumuló segundos erróneos (bug de
// poll stale o GPS drift) y disparó alertas falsas. Mientras el
// fix se deploya, este script resetea el doc del chofer para
// frenar las alertas y arrancar de cero el conteo.
//
// El cron del próximo ciclo va a actualizar el doc con la
// posición actual y empezar a sumar bien (con el fix que valida
// `polled_en` y umbral 15 km/h).
//
// Uso (desde la raíz del repo, mismo runtime que el bot):
//   node whatsapp-bot/scripts/resetear_jornada_chofer.js <DNI>
//   node whatsapp-bot/scripts/resetear_jornada_chofer.js 12345678 --dry-run
//
// El doc se borra (delete). El cron lo recreará en el próximo ciclo
// con segundos_total_dia=0.

require("dotenv").config({ path: __dirname + "/../whatsapp-bot/.env" });

const path = require("path");
const fs = require("fs");
const admin = require("firebase-admin");

const dni = process.argv[2];
const dryRun = process.argv.includes("--dry-run");

if (!dni || /^[^\d]/.test(dni)) {
  console.error("Uso: node scripts/resetear_jornada_chofer.js <DNI> [--dry-run]");
  console.error("Ejemplo: node scripts/resetear_jornada_chofer.js 12345678");
  process.exit(1);
}

// Init Firebase Admin con service account del repo.
const credsPath = path.resolve(
  process.env.FIREBASE_CREDENTIALS_PATH ||
    path.join(__dirname, "..", "serviceAccountKey.json")
);
if (!fs.existsSync(credsPath)) {
  console.error(`No encuentro service account en ${credsPath}`);
  process.exit(1);
}
admin.initializeApp({
  credential: admin.credential.cert(require(credsPath)),
  projectId: process.env.FIREBASE_PROJECT_ID || "coopertrans-movil",
});
const db = admin.firestore();

async function main() {
  // Fecha de hoy en TZ Argentina (mismo formato que el cron).
  const fechaArt = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Argentina/Buenos_Aires",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());

  const docId = `${dni}_${fechaArt}`;
  const ref = db.collection("JORNADAS_CHOFER").doc(docId);
  const snap = await ref.get();

  if (!snap.exists) {
    console.log(`No hay doc ${docId} — nada que resetear.`);
    return;
  }

  const data = snap.data();
  const totalDia = data.segundos_total_dia || 0;
  const continuoActual = data.segundos_continuo_actual || 0;
  console.log(`Doc encontrado: ${docId}`);
  console.log(`  segundos_total_dia: ${totalDia}s = ${(totalDia / 3600).toFixed(2)}h`);
  console.log(`  segundos_continuo_actual: ${continuoActual}s = ${(continuoActual / 3600).toFixed(2)}h`);
  console.log(`  alerta_3_45_continua_enviada: ${data.alerta_3_45_continua_enviada}`);
  console.log(`  alerta_11_30_diaria_enviada: ${data.alerta_11_30_diaria_enviada}`);
  console.log("");

  if (dryRun) {
    console.log("DRY-RUN: no se borró nada. Para borrar: corré sin --dry-run.");
    return;
  }

  await ref.delete();
  console.log("OK. Doc borrado.");
  console.log("El próximo ciclo del cron (5 min) lo va a recrear con total=0.");
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error("ERROR:", e.message);
    process.exit(1);
  });

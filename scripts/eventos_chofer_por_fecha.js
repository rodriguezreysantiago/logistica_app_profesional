// Distribución temporal de los eventos VOLVO_ALERTAS de un chofer.
// Útil para entender por qué el tablero muestra los mismos números en
// distintas ventanas de tiempo (puede ser que todos los eventos estén
// dentro del rango más chico, o que `chofer_dni` solo se haya
// populado a partir de cierta fecha).
//
// Uso: node scripts/eventos_chofer_por_fecha.js <dni>

const path = require("path");
const fsNode = require("fs");

const botDir = path.resolve(__dirname, "..", "whatsapp-bot");
module.paths.unshift(path.join(botDir, "node_modules"));
process.chdir(botDir);
require("dotenv").config({ quiet: true });

const admin = require("firebase-admin");
admin.initializeApp({
  credential: admin.credential.cert(require(path.resolve(process.env.FIREBASE_CREDENTIALS_PATH || "../serviceAccountKey.json"))),
  projectId: "coopertrans-movil",
});
const db = admin.firestore();

const dni = (process.argv[2] || "").trim();
if (!dni) { console.error("Falta DNI"); process.exit(1); }

(async () => {
  const snap = await db.collection("VOLVO_ALERTAS")
    .where("chofer_dni", "==", dni)
    .get();

  const ahora = Date.now();
  const buckets = {
    "ultimos 1 dia": 0,
    "1-7 dias": 0,
    "7-30 dias": 0,
    "30-90 dias": 0,
    "> 90 dias": 0,
    "sin fecha": 0,
  };

  let masViejo = null;
  let masNuevo = null;

  for (const d of snap.docs) {
    const ts = d.data().creado_en;
    if (!ts || typeof ts.toDate !== "function") {
      buckets["sin fecha"]++;
      continue;
    }
    const fecha = ts.toDate();
    if (!masViejo || fecha < masViejo) masViejo = fecha;
    if (!masNuevo || fecha > masNuevo) masNuevo = fecha;
    const diasAtras = (ahora - fecha.getTime()) / (1000 * 60 * 60 * 24);
    if (diasAtras < 1) buckets["ultimos 1 dia"]++;
    else if (diasAtras < 7) buckets["1-7 dias"]++;
    else if (diasAtras < 30) buckets["7-30 dias"]++;
    else if (diasAtras < 90) buckets["30-90 dias"]++;
    else buckets["> 90 dias"]++;
  }

  console.log(`Total eventos chofer DNI ${dni}: ${snap.size}`);
  console.log(`Mas viejo:  ${masViejo ? masViejo.toISOString() : "n/a"}`);
  console.log(`Mas nuevo:  ${masNuevo ? masNuevo.toISOString() : "n/a"}`);
  console.log("\nDistribución temporal:");
  for (const [k, v] of Object.entries(buckets)) {
    console.log(`  ${v.toString().padStart(4)} - ${k}`);
  }
})().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });

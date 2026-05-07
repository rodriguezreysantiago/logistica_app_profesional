// Busca un chofer por nombre/apellido en EMPLEADOS y reporta sus eventos.

const path = require("path");
const fsNode = require("fs");

const botDir = path.resolve(__dirname, "..", "whatsapp-bot");
module.paths.unshift(path.join(botDir, "node_modules"));
process.chdir(botDir);
require("dotenv").config({ quiet: true });

const admin = require("firebase-admin");
const credPath = path.resolve(process.env.FIREBASE_CREDENTIALS_PATH || "../serviceAccountKey.json");
admin.initializeApp({
  credential: admin.credential.cert(require(credPath)),
  projectId: "coopertrans-movil",
});
const db = admin.firestore();

const ETIQUETAS_OK = new Set([
  "DISTANCE_ALERT", "IDLING", "OVERSPEED", "PTO", "HARSH", "GENERIC",
  "TELL_TALE", "FUEL", "CATALYST", "ALARM", "GEOFENCE", "SAFETY_ZONE",
  "TPM", "TTM", "AEBS", "ESP", "DAS", "LKS", "LCS",
  "UNSAFE_LANE_CHANGE", "TACHO_OUT_OF_SCOPE_MODE_CHANGE", "CARGO",
  "ADBLUELEVEL_LOW", "WITHOUT_ADBLUE", "DRIVING_WITHOUT_BEING_LOGGED_IN",
  "SEATBELT", "BATTERY_PACK_HIGH_DISCHARGE",
  "BATTERY_PACK_CHARGING_STATUS_CHANGE",
]);

const filtro = (process.argv[2] || "").trim().toUpperCase();
if (!filtro) { console.error("Pasame un nombre/apellido a buscar"); process.exit(1); }

(async () => {
  const snap = await db.collection("EMPLEADOS").get();
  const matches = snap.docs.filter((d) => {
    const data = d.data();
    const nombre = (data.NOMBRE || "").toString().toUpperCase();
    return nombre.includes(filtro);
  });

  if (matches.length === 0) {
    console.log(`Sin matches para "${filtro}"`);
    process.exit(0);
  }

  for (const empDoc of matches) {
    const dni = empDoc.id;
    const data = empDoc.data();
    console.log(`\n=== ${data.NOMBRE} | DNI ${dni} ===`);
    console.log(`   ROL: ${data.ROL}, AREA: ${data.AREA}, VEHICULO: ${data.VEHICULO}`);

    // Eventos del chofer.
    const eventos = await db.collection("VOLVO_ALERTAS")
      .where("chofer_dni", "==", dni)
      .get();
    console.log(`   Total eventos VOLVO_ALERTAS: ${eventos.size}`);

    const conteo = new Map();
    for (const d of eventos.docs) {
      const ev = d.data();
      let tipo = (ev.tipo || "").toString().toUpperCase();
      if (tipo === "GENERIC") {
        const det = ev.detalle_generic || {};
        const tt = (det.triggerType || det.type || "").toString().toUpperCase();
        if (tt) tipo = tt;
      }
      conteo.set(tipo, (conteo.get(tipo) || 0) + 1);
    }
    [...conteo.entries()]
      .sort((a, b) => b[1] - a[1])
      .forEach(([t, n]) => {
        const flag = ETIQUETAS_OK.has(t) ? "OK   " : "FALTA";
        console.log(`   ${flag} ${n.toString().padStart(4)} - ${t}`);
      });
  }
})().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });

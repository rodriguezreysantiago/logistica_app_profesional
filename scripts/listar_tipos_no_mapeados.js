// Lista todos los tipos/subtipos únicos en VOLVO_ALERTAS que NO están
// en el mapa de etiquetas del cliente Flutter. Útil para detectar
// huecos en _etiquetasTipoAlertaVolvo.
//
// Uso: node scripts/listar_tipos_no_mapeados.js

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

// Mapa actual del cliente Flutter (mantener en sincro con
// lib/features/eco_driving/utils/etiquetas_alerta_volvo.dart).
const ETIQUETAS = new Set([
  "DISTANCE_ALERT", "IDLING", "OVERSPEED", "PTO", "HARSH", "GENERIC",
  "TELL_TALE", "FUEL", "CATALYST", "ALARM", "GEOFENCE", "SAFETY_ZONE",
  "TPM", "TTM", "AEBS", "ESP", "DAS", "LKS", "LCS",
  "UNSAFE_LANE_CHANGE", "TACHO_OUT_OF_SCOPE_MODE_CHANGE", "CARGO",
  "ADBLUELEVEL_LOW", "WITHOUT_ADBLUE", "DRIVING_WITHOUT_BEING_LOGGED_IN",
  "SEATBELT", "BATTERY_PACK_HIGH_DISCHARGE",
  "BATTERY_PACK_CHARGING_STATUS_CHANGE",
]);

(async () => {
  const snap = await db.collection("VOLVO_ALERTAS").get();
  console.log(`Total eventos en base: ${snap.size}`);

  const conteo = new Map();
  for (const d of snap.docs) {
    const data = d.data();
    let tipo = (data.tipo || "").toString().toUpperCase();
    if (tipo === "GENERIC") {
      const det = data.detalle_generic || {};
      const tt = (det.triggerType || det.type || "").toString().toUpperCase();
      if (tt) tipo = tt;
    }
    conteo.set(tipo, (conteo.get(tipo) || 0) + 1);
  }

  console.log("\nDistribución completa (todos los tipos resueltos):");
  [...conteo.entries()]
    .sort((a, b) => b[1] - a[1])
    .forEach(([t, n]) => {
      const tieneEtiqueta = ETIQUETAS.has(t);
      const flag = tieneEtiqueta ? "OK " : "FALTA";
      console.log(`  ${flag}  ${n.toString().padStart(5)} - ${t}`);
    });

  const faltantes = [...conteo.keys()].filter((t) => !ETIQUETAS.has(t));
  if (faltantes.length > 0) {
    console.log(`\n${faltantes.length} tipo(s) sin etiqueta — agregar al mapa:`);
    faltantes.forEach((t) => console.log(`  '${t}': '???',`));
  } else {
    console.log("\nTodos los tipos tienen etiqueta.");
  }
})().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });

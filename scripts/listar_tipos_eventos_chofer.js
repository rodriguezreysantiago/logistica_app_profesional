// Lista todos los tipos/subtipos de VOLVO_ALERTAS para un chofer.
// Útil para detectar tipos nuevos que no están en el mapa de etiquetas
// y agregar al `_etiquetasTipoAlertaVolvo` correspondiente.
//
// Uso:
//   node scripts/listar_tipos_eventos_chofer.js <dni>

const path = require("path");
const fsNode = require("fs");

const botDir = path.resolve(__dirname, "..", "whatsapp-bot");
module.paths.unshift(path.join(botDir, "node_modules"));
process.chdir(botDir);
require("dotenv").config({ quiet: true });

const admin = require("firebase-admin");
const credPath = path.resolve(process.env.FIREBASE_CREDENTIALS_PATH || "../serviceAccountKey.json");
if (!fsNode.existsSync(credPath)) {
  console.error(`Cred file no encontrado: ${credPath}`);
  process.exit(1);
}
admin.initializeApp({
  credential: admin.credential.cert(require(credPath)),
  projectId: process.env.FIREBASE_PROJECT_ID || "coopertrans-movil",
});

const db = admin.firestore();
const dni = (process.argv[2] || "").trim();
if (!dni) { console.error("Falta DNI"); process.exit(1); }

(async () => {
  const snap = await db.collection("VOLVO_ALERTAS")
    .where("chofer_dni", "==", dni)
    .get();
  console.log(`Total eventos: ${snap.size}`);

  // Cuenta por tipo (resolviendo subtipo de GENERIC).
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
  console.log("\nPor tipo (con subtipo resuelto):");
  [...conteo.entries()]
    .sort((a, b) => b[1] - a[1])
    .forEach(([t, n]) => console.log(`  ${n.toString().padStart(4)} - ${t}`));
})().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });

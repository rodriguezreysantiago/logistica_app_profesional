// Diagnóstico extendido: chequea EMPLEADOS/16969961 y, además, el
// usuario asociado en Firebase Auth — su uid tiene que ser igual al
// DNI para que la rule `isSelf(dni)` permita leer el legajo.
//
// Uso desde la raíz del repo:
//   node scripts/diagnosticar_chofer_16969961.js

const path = require("path");

const botDir = path.resolve(__dirname, "..", "whatsapp-bot");
module.paths.unshift(path.join(botDir, "node_modules"));
process.chdir(botDir);
require("dotenv").config({ quiet: true });

const admin = require("firebase-admin");
const credPath = path.resolve(
  process.env.FIREBASE_CREDENTIALS_PATH || "../serviceAccountKey.json"
);
admin.initializeApp({
  credential: admin.credential.cert(require(credPath)),
  projectId: "coopertrans-movil",
});
const db = admin.firestore();
const auth = admin.auth();

const DNI = "16969961";

(async () => {
  console.log(`\n=== EMPLEADOS/${DNI} ===\n`);
  const snap = await db.collection("EMPLEADOS").doc(DNI).get();
  if (!snap.exists) {
    console.log(`❌ NO existe EMPLEADOS/${DNI}`);
    process.exit(0);
  }
  const d = snap.data();
  console.log("✅ Doc existe.");
  console.log(`   NOMBRE: ${d.NOMBRE}`);
  console.log(`   ROL:    ${d.ROL}`);
  console.log(`   ACTIVO: ${d.ACTIVO} ${d.ACTIVO === undefined ? "(undefined — default true por loginConDni)" : ""}`);
  console.log(`   DNI campo interno: "${d.DNI}"`);
  console.log(`   docId == DNI campo: ${snap.id === d.DNI}`);
  if (snap.id !== d.DNI) {
    console.log(`   ⚠️ MISMATCH: docId "${snap.id}" vs campo DNI "${d.DNI}"`);
  }

  console.log(`\n=== Firebase Auth — buscar user con uid="${DNI}" ===\n`);
  try {
    const user = await auth.getUser(DNI);
    console.log(`✅ Auth user existe con uid="${user.uid}"`);
    console.log(`   email: ${user.email ?? "(no email)"}`);
    console.log(`   disabled: ${user.disabled}`);
    console.log(`   customClaims: ${JSON.stringify(user.customClaims)}`);
    console.log(`   lastSignInTime: ${user.metadata.lastSignInTime}`);
    console.log(`   creationTime: ${user.metadata.creationTime}`);
  } catch (e) {
    if (e.code === "auth/user-not-found") {
      console.log(`⚠️ NO existe un Firebase Auth user con uid="${DNI}".`);
      console.log(`   loginConDni crea el user al primer login con uid=DNI.`);
      console.log(`   Si nunca entró con la app nueva, no existe el user.`);
    } else {
      console.log(`❌ Error consultando Auth: ${e.message}`);
    }
  }

  // Por si quedó un Auth user viejo con uid distinto (ej. email-based
  // de la app legacy), buscamos por email/phone del legajo.
  if (d.MAIL) {
    console.log(`\n=== Buscar Auth user por email "${d.MAIL}" ===`);
    try {
      const user = await auth.getUserByEmail(d.MAIL);
      console.log(`⚠️ Auth user existe con uid="${user.uid}" (email match).`);
      if (user.uid !== DNI) {
        console.log(
          `   🚨 El uid NO coincide con el DNI. ` +
            `Eso explicaría el "perfil no encontrado" — ` +
            `la rule isSelf(dni) falla porque request.auth.uid="${user.uid}" ` +
            `pero el doc está en EMPLEADOS/${DNI}.`
        );
      }
    } catch (e) {
      if (e.code === "auth/user-not-found") {
        console.log(`   (no hay Auth user con ese email)`);
      } else {
        console.log(`   error: ${e.message}`);
      }
    }
  }

  process.exit(0);
})().catch((e) => {
  console.error("error:", e);
  process.exit(1);
});

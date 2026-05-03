// Test end-to-end del trigger `onAlertaVolvoMantenimientoCreated`
// (Fase 4 del roadmap Volvo Alerts).
//
// Crea un doc dummy en VOLVO_ALERTAS que matchea el filtro del trigger
// (tipo FUEL, severidad HIGH, patente de prueba), espera unos segundos
// a que dispare, y verifica que se encoló un mensaje en COLA_WHATSAPP.
//
// Después limpia el doc dummy de VOLVO_ALERTAS para no contaminar
// la colección. NO toca el doc encolado en COLA_WHATSAPP — eso queda
// para que el bot lo procese en su próxima ventana hábil (puede que
// llegue en minutos si corrés en horario laboral, o el lunes 8 AM
// si corrés fin de semana o de noche).
//
// USO:
//   cd whatsapp-bot
//   node ../scripts/probar_alerta_mantenimiento.js

const path = require("path");
const fsNode = require("fs");

const botDir = path.resolve(__dirname, "..", "whatsapp-bot");
const botNodeModules = path.join(botDir, "node_modules");
if (!fsNode.existsSync(botNodeModules)) {
  console.error(
    `❌ No existe ${botNodeModules}. Corré 'npm install' en whatsapp-bot primero.`
  );
  process.exit(1);
}
module.paths.unshift(botNodeModules);
process.chdir(botDir);
require("dotenv").config({ quiet: true });

const admin = require("firebase-admin");

const credPath =
  process.env.FIREBASE_CREDENTIALS_PATH || "../serviceAccountKey.json";
const absPath = path.resolve(credPath);
if (!fsNode.existsSync(absPath)) {
  console.error(`❌ Credenciales no encontradas en: ${absPath}`);
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(absPath)),
  projectId: process.env.FIREBASE_PROJECT_ID || "coopertrans-movil",
});

const db = admin.firestore();

// Patente de unidad de pruebas. Si no es válida en VEHICULOS, igual
// el trigger funciona — solo usa el campo `patente` para el mensaje.
const PATENTE_TEST = "AI162YT";

// Coordenadas: Bahía Blanca centro (cerca de las oficinas de Vecchi).
// Lo importante para el test es que el link de Maps se construya bien.
const LAT_TEST = -38.7196;
const LNG_TEST = -62.2724;

// Si querés probar otro tipo, cambialo: FUEL, CATALYST, GENERIC.
// Para GENERIC con sub-tipo TELL_TALE, agregar `detalle_generic`.
const TIPO_TEST = "FUEL";

const ESPERA_TRIGGER_MS = 8000; // El onCreate de Firestore tarda ~3-5s.

async function main() {
  console.log(`🧪 Test end-to-end onAlertaVolvoMantenimientoCreated`);
  console.log(`   Proyecto: ${admin.app().options.projectId}`);
  console.log(`   Tipo: ${TIPO_TEST}, Patente: ${PATENTE_TEST}`);
  console.log("");

  // 1. Crear doc dummy en VOLVO_ALERTAS.
  const ahora = Date.now();
  const docId = `_TEST_MANTENIMIENTO_${ahora}`;
  const docRef = db.collection("VOLVO_ALERTAS").doc(docId);

  console.log(`📝 [1/4] Creando doc ${docId}...`);
  await docRef.set({
    vin: "TEST_VIN_DUMMY",
    tipo: TIPO_TEST,
    severidad: "HIGH",
    patente: PATENTE_TEST,
    creado_en: admin.firestore.Timestamp.fromMillis(ahora),
    polled_en: admin.firestore.FieldValue.serverTimestamp(),
    atendida: false,
    posicion_gps: { lat: LAT_TEST, lng: LNG_TEST },
    chofer_nombre: "TEST CHOFER (script)",
    chofer_dni: "00000000",
    _es_test: true,
  });
  console.log(`   ✅ Creado.`);
  console.log("");

  // 2. Esperar al trigger.
  console.log(`⏳ [2/4] Esperando ${ESPERA_TRIGGER_MS / 1000}s a que dispare el trigger...`);
  await new Promise((r) => setTimeout(r, ESPERA_TRIGGER_MS));
  console.log("");

  // 3. Verificar COLA_WHATSAPP.
  console.log(`🔍 [3/4] Buscando doc en COLA_WHATSAPP con alert_id=${docId}...`);
  const colaSnap = await db
    .collection("COLA_WHATSAPP")
    .where("alert_id", "==", docId)
    .limit(1)
    .get();

  let exito = false;
  if (colaSnap.empty) {
    console.log(`   ❌ NO se encontró doc en COLA_WHATSAPP.`);
    console.log("      Posibles causas:");
    console.log("      - Trigger no deployado: firebase deploy --only functions:onAlertaVolvoMantenimientoCreated");
    console.log("      - Trigger lanzó pero el destinatario (DNI 35244439) no tiene TELEFONO en EMPLEADOS.");
    console.log("      - Esperar más tiempo (a veces el trigger tarda).");
    console.log("      Revisar logs:");
    console.log(`        firebase functions:log --only onAlertaVolvoMantenimientoCreated --lines 20`);
  } else {
    exito = true;
    const colaDoc = colaSnap.docs[0];
    const d = colaDoc.data();
    console.log(`   ✅ Encontrado: ${colaDoc.id}`);
    console.log(`      estado:      ${d.estado}`);
    console.log(`      telefono:    ${d.telefono}`);
    console.log(`      origen:      ${d.origen}`);
    console.log(`      destinatario:${d.destinatario_id}`);
    console.log("");
    console.log(`   📨 MENSAJE QUE SE VA A ENVIAR:`);
    console.log("      ───────────────────────────");
    String(d.mensaje || "").split("\n").forEach((line) => console.log(`      ${line}`));
    console.log("      ───────────────────────────");
    console.log("");
    console.log(`      Si estás en horario hábil (8-19 lun-vie), el bot lo manda en <30s.`);
    console.log(`      Fuera de horario, queda PENDIENTE hasta el próximo día hábil 8:00 AM.`);
  }
  console.log("");

  // 4. Limpieza: borrar el doc dummy de VOLVO_ALERTAS para no
  //    contaminar la colección. El doc en COLA_WHATSAPP NO se borra
  //    (se procesa o queda como histórico).
  console.log(`🧹 [4/4] Borrando doc dummy de VOLVO_ALERTAS...`);
  await docRef.delete();
  console.log(`   ✅ Limpio.`);
  console.log("");

  if (exito) {
    console.log(`✓ Test EXITOSO — el trigger funciona end-to-end.`);
    process.exit(0);
  } else {
    console.log(`✗ Test FALLÓ — revisar logs de la function.`);
    process.exit(1);
  }
}

main().catch((e) => {
  console.error("❌ Error:", e.stack || e.message);
  process.exit(2);
});

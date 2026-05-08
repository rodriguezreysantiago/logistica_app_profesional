// Audita SITRACK_POSICIONES y lista los iButton/tarjetas que están
// con DNI vacío en Sitrack. Útil para saber qué choferes hay que
// editar en el panel web de Sitrack para cargarles el DNI.
//
// Distingue 3 casos:
//   - SIN_DNI_CON_NOMBRE: el iButton tiene nombre pero falta DNI.
//                         Acción: cargar DNI en Sitrack.
//   - SIN_DNI_SIN_NOMBRE: chofer no pasó iButton (drift legítimo).
//                         Acción: chofer tiene que pasar iButton.
//   - CON_DNI_QUE_NO_MATCHEA: el DNI cargado en Sitrack no coincide
//                              con la asignación. Acción: revisar
//                              cuál es correcto.
//
// Uso (desde la raíz del repo):
//   node scripts/auditar_sitrack_drivers.js
//
// El script lee solo — no modifica nada.

const path = require("path");
const fs = require("fs");

let admin;
try {
  admin = require(path.join(__dirname, "..", "whatsapp-bot", "node_modules", "firebase-admin"));
} catch (_) {
  try {
    admin = require("firebase-admin");
  } catch (_) {
    console.error("No encuentro firebase-admin. Corré desde whatsapp-bot/ después de `npm install`.");
    process.exit(1);
  }
}

const credsPath = path.resolve(
  path.join(__dirname, "..", "serviceAccountKey.json")
);
if (!fs.existsSync(credsPath)) {
  console.error(`No encuentro service account en ${credsPath}`);
  process.exit(1);
}
admin.initializeApp({
  credential: admin.credential.cert(require(credsPath)),
  projectId: "coopertrans-movil",
});
const db = admin.firestore();

async function main() {
  console.log("📡 Leyendo SITRACK_POSICIONES...");
  const snap = await db.collection("SITRACK_POSICIONES").get();
  console.log(`   ${snap.size} tractores en la flota.\n`);

  const sinDniConNombre = [];
  const sinDniSinNombre = [];
  const conDniQueNoMatchea = [];
  const ok = [];
  const apagados = [];

  for (const doc of snap.docs) {
    const d = doc.data();
    const patente = doc.id;
    const ignition = d.ignition === true;
    const driverDni = (d.driver_dni || "").toString().trim();
    const driverNombre = (d.driver_nombre || "").toString().trim();
    const driverApellido = (d.driver_apellido || "").toString().trim();
    const asignacionDni = (d.asignacion_dni || "").toString().trim();
    const asignacionNombre = (d.asignacion_nombre || "").toString().trim();
    const driftTipo = (d.drift_tipo || "").toString();

    // Tractor apagado: no analizar drift, no es problema operativo.
    if (!ignition) {
      apagados.push({ patente, asignacionNombre });
      continue;
    }

    const nombreSitrack = `${driverNombre} ${driverApellido}`.trim();

    if (!driverDni && nombreSitrack) {
      // Caso del bug que fixeé hoy: iButton identifica por nombre
      // pero Sitrack no manda DNI.
      sinDniConNombre.push({
        patente,
        nombreSitrack,
        asignacionDni,
        asignacionNombre,
      });
    } else if (!driverDni && !nombreSitrack) {
      // Drift legítimo: chofer no pasó iButton.
      sinDniSinNombre.push({ patente, asignacionDni, asignacionNombre });
    } else if (driverDni && asignacionDni && driverDni !== asignacionDni) {
      // CHOFER_DISTINTO: el DNI físico no coincide con el asignado.
      conDniQueNoMatchea.push({
        patente,
        driverDni,
        nombreSitrack,
        asignacionDni,
        asignacionNombre,
      });
    } else {
      ok.push({ patente, driverDni, nombreSitrack });
    }
  }

  console.log("📊 RESUMEN:");
  console.log(`   ✅ Tractores OK:                   ${ok.length}`);
  console.log(`   🟢 Tractores apagados:             ${apagados.length}`);
  console.log(`   ⚠️ iButton sin DNI cargado:        ${sinDniConNombre.length}  ← acción: cargar DNI en Sitrack`);
  console.log(`   🚨 Sin iButton (drift legítimo):   ${sinDniSinNombre.length}  ← acción: avisar al chofer`);
  console.log(`   🚨 DNI no matchea con asignación:  ${conDniQueNoMatchea.length}  ← acción: revisar`);
  console.log("");

  if (sinDniConNombre.length > 0) {
    console.log("⚠️ IBUTTON SIN DNI EN SITRACK (cargar DNI en panel web):");
    console.log("");
    // Agrupar por nombre del iButton — un mismo chofer puede aparecer
    // en varios tractores pero el problema es del iButton/persona.
    const porNombre = {};
    for (const x of sinDniConNombre) {
      if (!porNombre[x.nombreSitrack]) {
        porNombre[x.nombreSitrack] = {
          dniEsperado: x.asignacionDni,
          nombreAsignacion: x.asignacionNombre,
          patentes: [],
        };
      }
      porNombre[x.nombreSitrack].patentes.push(x.patente);
    }
    for (const [nombre, info] of Object.entries(porNombre)) {
      console.log(`   📌 iButton "${nombre}"`);
      console.log(`      DNI a cargar en Sitrack: ${info.dniEsperado}`);
      console.log(`      Nombre en asignación:    ${info.nombreAsignacion}`);
      console.log(`      En tractor(es):          ${info.patentes.join(", ")}`);
      console.log("");
    }
  }

  if (conDniQueNoMatchea.length > 0) {
    console.log("🚨 DNI EN SITRACK ≠ DNI ASIGNADO:");
    for (const x of conDniQueNoMatchea) {
      console.log(`   ${x.patente}: Sitrack="${x.nombreSitrack}" (DNI ${x.driverDni}) | Asignado="${x.asignacionNombre}" (DNI ${x.asignacionDni})`);
    }
    console.log("");
  }

  if (sinDniSinNombre.length > 0) {
    console.log("🚨 SIN IBUTTON (chofer no se identificó):");
    for (const x of sinDniSinNombre) {
      console.log(`   ${x.patente}: asignado=${x.asignacionNombre || "(sin asignación)"}`);
    }
    console.log("");
  }
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error("ERROR:", e.message);
    process.exit(1);
  });

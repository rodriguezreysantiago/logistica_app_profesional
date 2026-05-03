// Backfill one-shot de la Volvo Group Scores API.
//
// El cron `volvoScoresPoller` (Cloud Function) corre 1 vez por día y
// guarda los scores del día anterior en `VOLVO_SCORES_DIARIOS`. Eso
// significa que la pantalla "Eco-Driving" del admin tarda 30 días en
// mostrar un mes de historia.
//
// Este script acelera el llenado: pide los últimos N días de scores
// (default 30) en una sola corrida y los persiste con el mismo formato
// que usa el poller. Idempotente (usa merge:true) — corrre seguro
// aunque el poller también haya escrito ese día.
//
// Spec API: GET /score/scores?starttime=YYYY-MM-DD&stoptime=YYYY-MM-DD&contentFilter=FLEET,VEHICLES
// con Basic Auth contra api.volvotrucks.com.
//
// Rate limit: Volvo permite 1 request cada 10s por endpoint. El script
// duerme 11s entre días para estar holgado. 30 días → ~5.5 minutos.
//
// USO (PowerShell, NO tocar el .env del bot):
//   cd whatsapp-bot
//   $cred = Get-Credential -Message "Credenciales Volvo Connect" -UserName "018B1E992E"
//   $env:VOLVO_USERNAME = $cred.UserName
//   $env:VOLVO_PASSWORD = $cred.GetNetworkCredential().Password
//   node ../scripts/backfill_volvo_scores.js              # 30 días
//   node ../scripts/backfill_volvo_scores.js --days 60    # 60 días custom
//   Remove-Item Env:VOLVO_USERNAME, Env:VOLVO_PASSWORD

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
  console.error(`❌ Credenciales Firebase no encontradas: ${absPath}`);
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(absPath)),
  projectId: process.env.FIREBASE_PROJECT_ID || "coopertrans-movil",
});

const db = admin.firestore();

const username = process.env.VOLVO_USERNAME;
const password = process.env.VOLVO_PASSWORD;
const VOLVO_BASE = process.env.VOLVO_BASE || "https://api.volvotrucks.com";
const ACCEPT = "application/x.volvogroup.com.scores.v2.0+json; UTF-8";

if (!username || !password) {
  console.error("❌ Faltan VOLVO_USERNAME o VOLVO_PASSWORD en el environment.");
  console.error("   Ver el bloque USO en el header del script.");
  process.exit(1);
}

// Parsear --days N del CLI (default 30, rango 1..365).
function parseDays() {
  const argIdx = process.argv.indexOf("--days");
  if (argIdx === -1 || argIdx === process.argv.length - 1) return 30;
  const n = parseInt(process.argv[argIdx + 1], 10);
  if (Number.isNaN(n) || n < 1 || n > 365) {
    console.error("❌ --days debe ser entre 1 y 365.");
    process.exit(1);
  }
  return n;
}

const dias = parseDays();

// Generar lista de fechas YYYY-MM-DD (ART), desde ayer hacia atrás N días.
function fechasParaBackfill(n) {
  const ahora = new Date();
  const ymdHoy = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Argentina/Buenos_Aires",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(ahora);
  const hoyArg = new Date(`${ymdHoy}T00:00:00-03:00`);
  const out = [];
  for (let i = 1; i <= n; i++) {
    const d = new Date(hoyArg.getTime() - i * 24 * 60 * 60 * 1000);
    const ymd = new Intl.DateTimeFormat("en-CA", {
      timeZone: "America/Argentina/Buenos_Aires",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(d);
    out.push(ymd);
  }
  return out;
}

function inicioDelDiaArg(ymd) {
  return new Date(`${ymd}T00:00:00-03:00`);
}

const authHeader =
  "Basic " + Buffer.from(`${username}:${password}`).toString("base64");

async function fetchScoresDia(ymd) {
  const qs = new URLSearchParams({
    starttime: ymd,
    stoptime: ymd,
    contentFilter: "FLEET,VEHICLES",
  });
  const url = `${VOLVO_BASE}/score/scores?${qs.toString()}`;
  const res = await fetch(url, {
    method: "GET",
    headers: { Authorization: authHeader, Accept: ACCEPT },
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`HTTP ${res.status}: ${text.slice(0, 300)}`);
  }
  return res.json();
}

function buildVehicleDoc(v, patente, fechaYmd, fechaTs) {
  return {
    vin: (v.vin || "").toString().trim().toUpperCase(),
    patente,
    fecha: fechaYmd,
    fecha_ts: fechaTs,
    scores: v.scores || {},
    totalTime: v.totalTime ?? null,
    avgSpeedDriving: v.avgSpeedDriving ?? null,
    totalDistance: v.totalDistance ?? null,
    avgFuelConsumption: v.avgFuelConsumption ?? null,
    avgFuelConsumptionGaseous: v.avgFuelConsumptionGaseous ?? null,
    avgElectricEnergyConsumption: v.avgElectricEnergyConsumption ?? null,
    vehicleUtilization: v.vehicleUtilization ?? null,
    co2Emissions: v.co2Emissions ?? null,
    co2Saved: v.co2Saved ?? null,
  };
}

function buildFleetDoc(f, fechaYmd, fechaTs) {
  return {
    es_fleet: true,
    fecha: fechaYmd,
    fecha_ts: fechaTs,
    scores: f.scores || {},
    totalTime: f.totalTime ?? null,
    avgSpeedDriving: f.avgSpeedDriving ?? null,
    totalDistance: f.totalDistance ?? null,
    avgFuelConsumption: f.avgFuelConsumption ?? null,
    avgFuelConsumptionGaseous: f.avgFuelConsumptionGaseous ?? null,
    avgElectricEnergyConsumption: f.avgElectricEnergyConsumption ?? null,
    vehicleUtilization: f.vehicleUtilization ?? null,
    co2Emissions: f.co2Emissions ?? null,
    co2Saved: f.co2Saved ?? null,
  };
}

async function main() {
  console.log(`🌱 Backfill Volvo Scores API (últimos ${dias} días)`);
  console.log(`   Proyecto: ${admin.app().options.projectId}`);
  console.log("");

  // Cross-ref VIN → patente. Mismo patrón que volvoScoresPoller.
  console.log(`📋 Cargando mapa VIN → patente desde VEHICULOS...`);
  const vehSnap = await db.collection("VEHICULOS").get();
  const vinToPatente = new Map();
  for (const doc of vehSnap.docs) {
    const data = doc.data();
    const vin = (data.VIN || "").toString().trim().toUpperCase();
    if (vin && vin !== "-") vinToPatente.set(vin, doc.id);
  }
  console.log(`   ${vinToPatente.size} VINs mapeados.`);
  console.log("");

  const fechas = fechasParaBackfill(dias);
  let totalFleetEscritos = 0;
  let totalVehiculosEscritos = 0;
  let diasConData = 0;
  let errores = 0;

  for (let i = 0; i < fechas.length; i++) {
    const ymd = fechas[i];
    const fechaTs = admin.firestore.Timestamp.fromDate(inicioDelDiaArg(ymd));

    process.stdout.write(`  [${i + 1}/${fechas.length}] ${ymd} ... `);

    let body;
    try {
      body = await fetchScoresDia(ymd);
    } catch (e) {
      console.log(`❌ ${e.message}`);
      errores++;
      // Esperar igual antes del próximo (rate limit).
      if (i < fechas.length - 1) await new Promise((r) => setTimeout(r, 11000));
      continue;
    }

    const response = body.vuScoreResponse || {};
    const fleet = response.fleet;
    const vehicles = Array.isArray(response.vehicles) ? response.vehicles : [];

    const tieneData = !!fleet || vehicles.length > 0;
    if (!tieneData) {
      console.log(`(sin data)`);
      if (i < fechas.length - 1) await new Promise((r) => setTimeout(r, 11000));
      continue;
    }

    diasConData++;
    let escritosEsteDia = 0;

    if (fleet) {
      await db
        .collection("VOLVO_SCORES_DIARIOS")
        .doc(`_FLEET_${ymd}`)
        .set(
          {
            ...buildFleetDoc(fleet, ymd, fechaTs),
            polled_en: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      totalFleetEscritos++;
      escritosEsteDia++;
    }

    if (vehicles.length > 0) {
      const batch = db.batch();
      for (const v of vehicles) {
        const vin = (v.vin || "").toString().trim().toUpperCase();
        if (!vin) continue;
        const patente = vinToPatente.get(vin) || vin;
        const ref = db.collection("VOLVO_SCORES_DIARIOS").doc(`${patente}_${ymd}`);
        batch.set(
          ref,
          {
            ...buildVehicleDoc(v, patente, ymd, fechaTs),
            polled_en: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        escritosEsteDia++;
        totalVehiculosEscritos++;
      }
      await batch.commit();
    }

    console.log(`✅ ${escritosEsteDia} doc(s)`);

    // Rate limit: esperar 11s antes del próximo día (Volvo permite
    // 1 req/10s por endpoint).
    if (i < fechas.length - 1) await new Promise((r) => setTimeout(r, 11000));
  }

  console.log("");
  console.log("───────────────── RESUMEN ─────────────────");
  console.log(`  Días pedidos          : ${dias}`);
  console.log(`  Días con data         : ${diasConData}`);
  console.log(`  Días sin data         : ${dias - diasConData - errores}`);
  console.log(`  Errores HTTP          : ${errores}`);
  console.log(`  Docs FLEET escritos   : ${totalFleetEscritos}`);
  console.log(`  Docs vehículo escritos: ${totalVehiculosEscritos}`);
  console.log(`  Total escritos        : ${totalFleetEscritos + totalVehiculosEscritos}`);
  console.log("");
  console.log("✓ Backfill completo. La pantalla 'Eco-Driving' ahora tiene historia.");

  process.exit(errores > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error("❌ Error:", e.stack || e.message);
  process.exit(2);
});

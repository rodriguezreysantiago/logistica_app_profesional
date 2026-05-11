// Enumera los eventName distintos que devuelve la API de Sitrack
// para inferir qué eventos de conducción podríamos usar para
// calcular un ICM (Índice de Conducción) por chofer.
//
// El poller actual (`sitrackPosicionPoller` en functions/src/index.ts)
// solo persiste posición + odómetro y descarta el campo `eventName`.
// Si Sitrack manda eventos tipo "Frenada brusca", "Aceleración
// brusca", "Exceso de velocidad", etc., podemos:
//   1. Pollearlos y persistirlos en SITRACK_EVENTOS_HISTORICO.
//   2. Agregarlos por chofer/día y calcular un score 0-100.
//   3. Mostrar el ICM en la app igual que el Volvo Score.
//
// Uso (desde la raíz del repo):
//   1. Setear las credenciales como env vars una sola vez:
//      $env:SITRACK_USERNAME = "user"
//      $env:SITRACK_PASSWORD = "pass"
//      (los podés sacar del Secret Manager con
//       `firebase functions:secrets:access SITRACK_USERNAME` y _PASSWORD)
//   2. Correr:
//      node scripts/sitrack_listar_eventos.js
//
// El script:
//   - Hace una llamada GET a /v2/report (mismo endpoint que el poller).
//   - Agrupa por `eventName` y muestra:
//       count por evento, ejemplo de campo `assetName` (patente),
//       un timestamp de muestra.
//   - NO escribe nada en Firestore — es solo análisis.

const SITRACK_BASE = "https://externalappgw.ar.sitrack.com";

const user = process.env.SITRACK_USERNAME;
const pass = process.env.SITRACK_PASSWORD;

if (!user || !pass) {
  console.error(
    "❌ Faltan credenciales. Seteá SITRACK_USERNAME y SITRACK_PASSWORD\n" +
    "   como variables de entorno antes de correr."
  );
  console.error("   En PowerShell:");
  console.error('     $env:SITRACK_USERNAME = "..."');
  console.error('     $env:SITRACK_PASSWORD = "..."');
  console.error(
    "   Las podés sacar del Secret Manager:\n" +
    "     firebase functions:secrets:access SITRACK_USERNAME\n" +
    "     firebase functions:secrets:access SITRACK_PASSWORD"
  );
  process.exit(1);
}

(async () => {
  const authHeader =
    "Basic " + Buffer.from(`${user}:${pass}`).toString("base64");

  console.log(`Llamando ${SITRACK_BASE}/v2/report ...\n`);

  let res;
  try {
    res = await fetch(`${SITRACK_BASE}/v2/report`, {
      method: "GET",
      headers: {
        Authorization: authHeader,
        Accept: "application/json",
      },
    });
  } catch (e) {
    console.error("❌ fetch falló:", e.message);
    process.exit(1);
  }

  if (!res.ok) {
    console.error(`❌ HTTP ${res.status} ${res.statusText}`);
    const body = await res.text().catch(() => "<no body>");
    console.error("Body:", body.substring(0, 500));
    process.exit(1);
  }

  let reports;
  try {
    reports = await res.json();
  } catch (e) {
    console.error("❌ JSON parse falló:", e.message);
    process.exit(1);
  }

  if (!Array.isArray(reports)) {
    console.error("❌ Response no es array. Tipo:", typeof reports);
    console.error("Body:", JSON.stringify(reports).substring(0, 500));
    process.exit(1);
  }

  console.log(`✅ ${reports.length} records recibidos\n`);

  // ─── Agrupar por eventName ───
  const porEvento = new Map();
  for (const r of reports) {
    const evt = (r.eventName || "(sin eventName)").trim();
    if (!porEvento.has(evt)) {
      porEvento.set(evt, {
        count: 0,
        eventId: r.eventId ?? null,
        ejemplos: [],
      });
    }
    const bucket = porEvento.get(evt);
    bucket.count++;
    if (bucket.ejemplos.length < 3) {
      bucket.ejemplos.push({
        asset: r.assetName ?? r.assetId ?? "?",
        date: r.reportDate ?? r.inputDate ?? "?",
        chofer: r.driverName ?? "(sin chofer)",
      });
    }
  }

  // ─── Mostrar ordenado por count desc ───
  console.log("=== EVENTOS DISTINTOS ENCONTRADOS ===\n");
  const sorted = [...porEvento.entries()].sort(
    (a, b) => b[1].count - a[1].count
  );
  for (const [evt, info] of sorted) {
    console.log(`▸ ${evt}  [eventId=${info.eventId}]  (${info.count} reports)`);
    for (const ej of info.ejemplos) {
      console.log(
        `    ${ej.asset.padEnd(15)} ${ej.date.padEnd(28)} ${ej.chofer}`
      );
    }
    console.log("");
  }

  // ─── Análisis ICM ───
  console.log("=== ANÁLISIS PARA ICM ===\n");
  const palabrasClaveICM = [
    "frenad", "brusc", "acelerac", "exces", "veloc",
    "harsh", "braking", "speeding", "overspeed",
    "idle", "idling", "ralenti",
    "curva", "cornering",
    "panic", "alarma",
  ];
  const relevantes = sorted.filter(([evt]) => {
    const low = evt.toLowerCase();
    return palabrasClaveICM.some((kw) => low.includes(kw));
  });

  if (relevantes.length === 0) {
    console.log(
      "❌ Ningún eventName del último report parece de conducción.\n" +
      "   Eso es ESPERADO con /v2/report (solo último estado).\n" +
      "   Para histórico de eventos hay que activar /files/reports.\n"
    );
  } else {
    console.log("✅ Eventos relevantes para calcular ICM:\n");
    for (const [evt, info] of relevantes) {
      console.log(`   ▸ ${evt}  (${info.count} reports)`);
    }
    console.log(
      "\n   (igualmente, /files/reports daría histórico completo)\n"
    );
  }

  // ─── Análisis de campos disponibles ───
  // Lo CRÍTICO para decidir si arrancamos Fase 1: saber qué campos
  // ricos para ICM nos están mandando los equipos. Si los samplings
  // y los campos onboardComputer* vienen poblados, podemos calcular
  // un ICM aproximado YA sin esperar a Sitrack.
  console.log("\n=== CAMPOS RICOS DISPONIBLES (para ICM aproximado) ===\n");

  const camposClaveICM = [
    "onboardComputerMaxSpeed",
    "onboardComputerTotalIdleTime",
    "onboardComputerHourmeter",
    "onboardComputerOdometer",
    "onboardComputerFuelRateAverageConsumption",
    "onboardComputerLastActivityConsumedFuelIdleVolume",
    "onboardComputerLastActivityConsumedFuelInRpmExcessVolume",
    "onboardComputerLastActivityConsumedFuelInMovementVolume",
    "speedSampling",
    "rpmSampling",
    "acceleratorSampling",
    "coolantTemperatureSampling",
    "cartographyLimitSpeed",
    "rpm",
    "speed",
    "gpsSpeed",
    "driverDocumentNumber",
    "driverName",
    "trailerId",
  ];

  const conteoCampos = new Map();
  for (const campo of camposClaveICM) {
    conteoCampos.set(campo, { presentes: 0, ejemplos: [] });
  }

  for (const r of reports) {
    for (const campo of camposClaveICM) {
      const v = r[campo];
      if (v != null && v !== "" && v !== 0 &&
          !(Array.isArray(v) && v.length === 0)) {
        const bucket = conteoCampos.get(campo);
        bucket.presentes++;
        if (bucket.ejemplos.length < 2) {
          let valorMostrado;
          if (Array.isArray(v)) {
            valorMostrado = `array[${v.length}]: ${JSON.stringify(v).substring(0, 80)}…`;
          } else if (typeof v === "object") {
            valorMostrado = JSON.stringify(v).substring(0, 80);
          } else {
            valorMostrado = String(v);
          }
          bucket.ejemplos.push({
            asset: r.assetName ?? r.assetId ?? "?",
            valor: valorMostrado,
          });
        }
      }
    }
  }

  const totalReports = reports.length;
  let camposUtiles = 0;
  for (const campo of camposClaveICM) {
    const bucket = conteoCampos.get(campo);
    const pct = totalReports === 0
      ? 0
      : Math.round((bucket.presentes / totalReports) * 100);
    const marca = bucket.presentes > 0 ? "✅" : "  ";
    console.log(
      `${marca} ${campo.padEnd(50)} ${bucket.presentes}/${totalReports} (${pct}%)`
    );
    if (bucket.ejemplos.length > 0) {
      for (const ej of bucket.ejemplos) {
        console.log(`     ${ej.asset.padEnd(15)} → ${ej.valor}`);
      }
    }
    if (bucket.presentes > 0) camposUtiles++;
  }

  console.log(`\n${camposUtiles} de ${camposClaveICM.length} campos clave vienen poblados.\n`);

  if (camposUtiles >= 5) {
    console.log(
      "✅ Hay suficientes datos para arrancar Fase 1 (ICM aproximado)\n" +
      "   SIN esperar a Sitrack. Próximo paso:\n" +
      "   - Actualizar sitrackPosicionPoller para persistir los\n" +
      "     campos extra junto con la posición.\n" +
      "   - Cron diario que agrega y calcula score 0-100 por chofer.\n"
    );
  } else if (camposUtiles >= 2) {
    console.log(
      "⚠️  Algunos campos están pero faltan los críticos.\n" +
      "   Capaz tus equipos no tienen ICAN/computadora de a bordo.\n" +
      "   Necesario sí o sí activar /files/reports en Sitrack.\n"
    );
  } else {
    console.log(
      "❌ Casi no hay campos ricos. Los equipos parecen ser GPS\n" +
      "   básicos sin ICAN. Sin Sitrack no podemos calcular ICM.\n" +
      "   Único camino: pedir a Sitrack /files/reports + eventos.\n"
    );
  }
})().catch((e) => {
  console.error("error:", e);
  process.exit(1);
});

// Probe one-shot para confirmar si Vecchi tiene activado el pack
// "Scores" en su contrato Volvo Connect.
//
// La Volvo Group Scores API (v2.0.2) devuelve scores 0-100 de eco-driving
// por flota / chofer / vehículo. NO es gratuita por default — Volvo cobra
// extra por activar el módulo. Es el mismo patrón que UPTIME, que vimos
// que NO está activado para Vecchi.
//
// Este script hace UN GET a /score/scores con las credenciales del .env
// del bot y reporta:
//   - 200 OK → tienen el pack, podemos avanzar con Fase 3 (Scores poller).
//   - 403    → NO tienen el pack. Hay que pedirle a Vecchi que lo active
//              (con costo) o ir por plan B (Fase 3 calculada desde Vehicle
//              Alerts API, sin el score oficial).
//   - 401    → credenciales mal (verificar .env tras última rotación).
//   - otro   → algo raro, ver el body crudo.
//
// USO (PowerShell, NO tocar el .env del bot — las creds viven solo en
// Secret Manager de Cloud Functions y queremos mantenerlo así):
//
//   cd whatsapp-bot
//   $cred = Get-Credential -Message "Credenciales Volvo Connect" -UserName "018B1E992E"
//   $env:VOLVO_USERNAME = $cred.UserName
//   $env:VOLVO_PASSWORD = $cred.GetNetworkCredential().Password
//   node ../scripts/probar_volvo_scores_api.js
//   Remove-Item Env:VOLVO_USERNAME, Env:VOLVO_PASSWORD
//
// Get-Credential abre un prompt nativo de Windows que NO muestra la
// password en pantalla y la mantiene solo en memoria del proceso
// PowerShell hasta que `Remove-Item` la limpia. Cero exposición a disco
// o a logs.

// Leemos las credenciales SOLO de variables de entorno del proceso.
// NO usamos dotenv ni .env aposta — las creds reales solo deben vivir
// en Secret Manager de GCP, y para este probe el caller las inyecta
// temporal vía Get-Credential de PowerShell (ver bloque USO arriba).
const username = process.env.VOLVO_USERNAME;
const password = process.env.VOLVO_PASSWORD;
const base = process.env.VOLVO_BASE || 'https://api.volvotrucks.com';

if (!username || !password) {
  console.error('❌ Faltan VOLVO_USERNAME o VOLVO_PASSWORD en el environment.');
  console.error('   Ver el bloque USO en el header del script.');
  process.exit(1);
}

// Pedimos scores de los últimos 7 días (ventana razonable que debería
// tener data si hay actividad). La API requiere starttime y stoptime
// como YYYY-MM-DD.
const ahora = new Date();
const hace7 = new Date(ahora.getTime() - 7 * 24 * 60 * 60 * 1000);
const fmt = (d) => d.toISOString().slice(0, 10);

const qs = new URLSearchParams({
  starttime: fmt(hace7),
  stoptime: fmt(ahora),
  contentFilter: 'FLEET',
});
const url = `${base}/score/scores?${qs.toString()}`;

const auth =
  'Basic ' + Buffer.from(`${username}:${password}`).toString('base64');

(async () => {
  console.log(`🔎 Probando Volvo Scores API (Vecchi / Coopertrans)`);
  console.log(`   URL: ${url}`);
  console.log(`   Window: ${fmt(hace7)} → ${fmt(ahora)}`);
  console.log('');

  let res;
  try {
    res = await fetch(url, {
      headers: {
        Authorization: auth,
        Accept: 'application/x.volvogroup.com.scores.v2.0+json; UTF-8',
      },
    });
  } catch (e) {
    console.error(`❌ Error de red: ${e.message}`);
    process.exit(2);
  }

  console.log(`HTTP ${res.status} ${res.statusText}`);
  const text = await res.text();

  if (res.ok) {
    console.log('✅ TIENEN EL PACK SCORES — podemos avanzar con Fase 3.');
    console.log('');
    try {
      const data = JSON.parse(text);
      const fleet = data.vuScoreResponse?.fleet;
      if (fleet) {
        console.log(`   📊 SCORE DE LA FLOTA (últimos 7 días):`);
        console.log(`      total                   : ${fleet.scores?.total ?? 'N/A'}`);
        console.log(`      anticipation            : ${fleet.scores?.anticipation ?? 'N/A'}`);
        console.log(`      braking                 : ${fleet.scores?.braking ?? 'N/A'}`);
        console.log(`      coasting                : ${fleet.scores?.coasting ?? 'N/A'}`);
        console.log(`      engineAndGearUtilization: ${fleet.scores?.engineAndGearUtilization ?? 'N/A'}`);
        console.log(`      idling                  : ${fleet.scores?.idling ?? 'N/A'}`);
        console.log(`      overspeed               : ${fleet.scores?.overspeed ?? 'N/A'}`);
        console.log(`      cruiseControl           : ${fleet.scores?.cruiseControl ?? 'N/A'}`);
        console.log('');
        console.log(`   📈 MÉTRICAS OPERATIVAS:`);
        console.log(`      avgSpeedDriving         : ${fleet.avgSpeedDriving ?? 'N/A'} km/h`);
        console.log(`      totalDistance           : ${(fleet.totalDistance ?? 0) / 1000} km`);
        console.log(`      avgFuelConsumption      : ${fleet.avgFuelConsumption ?? 'N/A'} ml/100km`);
        console.log(`      vehicleUtilization      : ${fleet.vehicleUtilization ?? 'N/A'} %`);
        console.log(`      co2Emissions            : ${fleet.co2Emissions ?? 'N/A'} ton`);
        console.log(`      totalTime motor         : ${(fleet.totalTime ?? 0) / 3600} h`);
      } else {
        console.log('   ⚠️  Sin data agregada de flota en este período. Body:');
        console.log(text.slice(0, 800));
      }
    } catch (e) {
      console.log('   Body crudo (no pudo parsear JSON):');
      console.log(text.slice(0, 800));
    }
    process.exit(0);
  }

  if (res.status === 403) {
    console.log('❌ NO TIENEN EL PACK (403 Forbidden)');
    console.log('');
    console.log('   Vecchi necesita contratar el pack "Scores" en Volvo Connect');
    console.log('   para usar este endpoint. Esto es lo mismo que pasó con UPTIME.');
    console.log('');
    console.log('   OPCIONES:');
    console.log('   A) Pedirle a Vecchi que active Scores (Volvo cobra extra).');
    console.log('   B) Plan B: Fase 3 calculada desde Vehicle Alerts API');
    console.log('      (más trabajo, menos preciso, pero independiente).');
    console.log('');
    console.log('   Body de respuesta (puede tener más detalle):');
    console.log(text.slice(0, 500));
    process.exit(3);
  }

  if (res.status === 401) {
    console.log('⚠️  Credenciales rechazadas (401).');
    console.log('   Verificar que la password ingresada en Get-Credential sea');
    console.log('   la VIGENTE (la rotamos hace un rato — la VIEJA ya no sirve).');
    console.log('   Sacá la actual del portal Volvo Connect o del Secret Manager');
    console.log('   de coopertrans-movil (firebase functions:secrets:access).');
    console.log('');
    console.log('   Body:');
    console.log(text.slice(0, 500));
    process.exit(4);
  }

  console.log(`⚠️  Respuesta inesperada (${res.status}):`);
  console.log(text.slice(0, 1000));
  process.exit(5);
})();

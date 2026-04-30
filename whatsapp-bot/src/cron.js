// Cron interno del bot — Fase 2.
//
// Cada N minutos (default 60) recorre EMPLEADOS y VEHICULOS, calcula
// urgencia de cada vencimiento, y encola avisos automáticos en
// COLA_WHATSAPP. La idempotencia se garantiza con AVISOS_AUTOMATICOS_HISTORICO
// (ver historico.js): el mismo aviso (mismo nivel de urgencia, misma
// fecha de vencimiento) se envía una sola vez.
//
// Se desactiva por default (`AUTO_AVISOS_ENABLED=false`) para que el
// primer arranque no genere sorpresas. El admin lo activa cuando
// confirme que el bot envía bien manualmente.

const admin = require('firebase-admin');
const log = require('./logger');
const { enHorarioHabil } = require('./humano');
const aviso = require('./aviso_builder');
const avisoService = require('./aviso_service_builder');
const hist = require('./historico');
const health = require('./health');

// Intervalo entre services programados de tractores Volvo, en KM.
// Espejo de `AppMantenimiento.intervaloServiceKm` en el cliente Dart.
// Si Vecchi cambia el plan a 25.000 o 75.000 km en el futuro, ajustar
// acá Y en `lib/core/constants/app_constants.dart`.
const INTERVALO_SERVICE_KM = 50000;

// Documentos auditados de EMPLEADOS — replica del listado en
// `lib/features/expirations/screens/admin_vencimientos_choferes_screen.dart`.
// Si en el futuro se centraliza en algún lado, leerlo de ahí.
const DOCS_EMPLEADO = {
  'Licencia de Conducir': 'LICENCIA_DE_CONDUCIR',
  Preocupacional: 'PREOCUPACIONAL',
  'Manejo Defensivo': 'CURSO_DE_MANEJO_DEFENSIVO',
  ART: 'ART',
  'F. 931': '931',
  'Seguro de Vida': 'SEGURO_DE_VIDA',
  Sindicato: 'LIBRE_DE_DEUDA_SINDICAL',
};

// Vencimientos auditados de VEHICULOS por tipo. Replica de
// `lib/core/constants/vencimientos_config.dart`. Mantener sincronizado.
const DOCS_VEHICULO = {
  TRACTOR: [
    { etiqueta: 'RTO', campoFecha: 'VENCIMIENTO_RTO', campoBase: 'RTO' },
    { etiqueta: 'Seguro', campoFecha: 'VENCIMIENTO_SEGURO', campoBase: 'SEGURO' },
    {
      etiqueta: 'Extintor Cabina',
      campoFecha: 'VENCIMIENTO_EXTINTOR_CABINA',
      campoBase: 'EXTINTOR_CABINA',
    },
    {
      etiqueta: 'Extintor Exterior',
      campoFecha: 'VENCIMIENTO_EXTINTOR_EXTERIOR',
      campoBase: 'EXTINTOR_EXTERIOR',
    },
  ],
  // Enganches (BATEA, TOLVA, etc.) tienen RTO + Seguro.
  // Si tu app define más tipos con sus propios vencimientos, sumalos acá.
  BATEA: [
    { etiqueta: 'RTO', campoFecha: 'VENCIMIENTO_RTO', campoBase: 'RTO' },
    { etiqueta: 'Seguro', campoFecha: 'VENCIMIENTO_SEGURO', campoBase: 'SEGURO' },
  ],
  TOLVA: [
    { etiqueta: 'RTO', campoFecha: 'VENCIMIENTO_RTO', campoBase: 'RTO' },
    { etiqueta: 'Seguro', campoFecha: 'VENCIMIENTO_SEGURO', campoBase: 'SEGURO' },
  ],
  BIVUELCO: [
    { etiqueta: 'RTO', campoFecha: 'VENCIMIENTO_RTO', campoBase: 'RTO' },
    { etiqueta: 'Seguro', campoFecha: 'VENCIMIENTO_SEGURO', campoBase: 'SEGURO' },
  ],
  TANQUE: [
    { etiqueta: 'RTO', campoFecha: 'VENCIMIENTO_RTO', campoBase: 'RTO' },
    { etiqueta: 'Seguro', campoFecha: 'VENCIMIENTO_SEGURO', campoBase: 'SEGURO' },
  ],
  ACOPLADO: [
    { etiqueta: 'RTO', campoFecha: 'VENCIMIENTO_RTO', campoBase: 'RTO' },
    { etiqueta: 'Seguro', campoFecha: 'VENCIMIENTO_SEGURO', campoBase: 'SEGURO' },
  ],
};

/**
 * Calcula los días restantes hasta `fechaIso` (`YYYY-MM-DD` o ISO).
 * Negativo si la fecha ya pasó. Devuelve `null` si la fecha es inválida.
 *
 * **Bug fixeado**: antes hacía `new Date("YYYY-MM-DD")` que JS parsea
 * como UTC midnight. En zona ART (UTC-3) eso significaba que una
 * licencia que vence el 30/05 quedaba "atrás un día" porque la
 * medianoche UTC es las 21h del día anterior en ART. El cron
 * recortaba 1 día por el shift de zona.
 *
 * Ahora parseamos los componentes YYYY-MM-DD a mano y construimos
 * la fecha en zona local — el cálculo da exacto.
 */
function calcularDiasRestantes(fechaIso) {
  if (!fechaIso) return null;
  // Parseo manual para evitar el shift UTC vs local.
  const str = String(fechaIso).trim();
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(str);
  let venc;
  if (m) {
    venc = new Date(
      parseInt(m[1], 10),
      parseInt(m[2], 10) - 1,
      parseInt(m[3], 10)
    );
  } else {
    venc = new Date(str);
  }
  if (isNaN(venc.getTime())) return null;
  // Normalizamos a medianoche local para que el cálculo sea estable
  // independientemente de a qué hora corre el cron.
  const hoy = new Date();
  const a = new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate());
  const b = new Date(venc.getFullYear(), venc.getMonth(), venc.getDate());
  const ms = b.getTime() - a.getTime();
  return Math.round(ms / (1000 * 60 * 60 * 24));
}

let _running = false;
let _timer = null;

/**
 * Arranca el cron si está habilitado. Idempotente: una segunda
 * llamada no duplica el timer.
 *
 * @param {object} fs - El módulo `firestore.js` (para reutilizar la
 *   constante COLECCION y los helpers de la cola).
 */
function start(fs) {
  if (_timer) return;
  const enabled =
    String(process.env.AUTO_AVISOS_ENABLED || 'false').toLowerCase() ===
    'true';
  if (!enabled) {
    log.info(
      'Cron de avisos automáticos DESHABILITADO (AUTO_AVISOS_ENABLED=false). ' +
        'Habilitar en .env cuando confirmes que el bot envía bien.'
    );
    return;
  }

  const intervaloMin = parseInt(
    process.env.CRON_INTERVAL_MINUTES || '60',
    10
  );
  log.info(
    `Cron de avisos automáticos HABILITADO (cada ${intervaloMin} min).`
  );
  // Primera corrida 30s después de iniciar — le damos tiempo a wwebjs
  // a estabilizarse antes de escribir a la cola.
  setTimeout(() => _runOnce(fs), 30000);
  _timer = setInterval(() => _runOnce(fs), intervaloMin * 60 * 1000);
}

function stop() {
  if (_timer) {
    clearInterval(_timer);
    _timer = null;
  }
}

async function _runOnce(fs) {
  if (_running) {
    log.warn('Cron previo todavía corriendo, salto este ciclo.');
    return;
  }
  if (!enHorarioHabil()) {
    log.debug('Cron salta — fuera de horario hábil.');
    return;
  }
  _running = true;

  const db = fs.inicializar();
  const stats = { encolados: 0, salteados: 0, errores: 0 };

  try {
    // ─── Throttle por chofer ─────────────────────────────────────
    // Pre-cargamos cuántos avisos ya recibió cada teléfono HOY.
    // Default 2 mensajes/día/chofer — evita ráfagas que disparan el
    // detector de bots de WhatsApp.
    const maxPorChoferDia = parseInt(
      process.env.MAX_AVISOS_POR_CHOFER_DIA || '2',
      10
    );
    const avisosHoyPorTel = new Map();
    try {
      const desde = _inicioDelDia();
      const yaHoySnap = await db
        .collection(fs.COLECCION)
        .where('encolado_en', '>=', admin.firestore.Timestamp.fromDate(desde))
        .get();
      for (const d of yaHoySnap.docs) {
        const tel = String(d.data().telefono || '').trim();
        if (!tel) continue;
        avisosHoyPorTel.set(tel, (avisosHoyPorTel.get(tel) || 0) + 1);
      }
      log.debug(`Throttle: ${avisosHoyPorTel.size} teléfonos con avisos hoy.`);
    } catch (e) {
      log.warn(`No pude pre-cargar throttle por chofer: ${e.message}`);
    }

    const yaSuperoTope = (tel) => {
      if (!tel) return false;
      return (avisosHoyPorTel.get(tel.trim()) || 0) >= maxPorChoferDia;
    };
    const bumpTope = (tel) => {
      if (!tel) return;
      const k = tel.trim();
      avisosHoyPorTel.set(k, (avisosHoyPorTel.get(k) || 0) + 1);
    };

    const empleadosSnap = await db.collection('EMPLEADOS').get();
    const empleadosByDni = new Map();
    // Índice inverso patente → empleado, pre-computado una vez por
    // ciclo. Antes hacíamos _buscarChofer() linealmente para cada
    // vencimiento de unidad, que era O(n*m) con n vehículos × m
    // empleados. Para una flota grande de 500 unidades empezaba a
    // doler — para Vecchi era despreciable, pero igual conviene.
    const choferByPatente = new Map();
    for (const doc of empleadosSnap.docs) {
      const data = doc.data();
      const emp = { id: doc.id, data };
      empleadosByDni.set(doc.id.trim(), emp);
      const veh = String(data.VEHICULO || '').trim().toUpperCase();
      const eng = String(data.ENGANCHE || '').trim().toUpperCase();
      if (veh && veh !== '-') choferByPatente.set(veh, emp);
      if (eng && eng !== '-') choferByPatente.set(eng, emp);
    }

    // ─── 1) Vencimientos personales del chofer ───
    for (const [dni, emp] of empleadosByDni) {
      const data = emp.data;
      const telefono = data.TELEFONO ? String(data.TELEFONO) : null;
      if (!telefono) continue; // sin teléfono, no podemos avisar

      // Saludamos por APODO si está cargado, sino fallback al
      // algoritmo de segundo token. Decisión de diseño en
      // ESTADO_PROYECTO: el admin carga APODO solo donde el algoritmo
      // falla (dos apellidos, segundo nombre, etc).
      const nombre = aviso.resolverNombreSaludo(data);
      for (const [etiqueta, campoBase] of Object.entries(DOCS_EMPLEADO)) {
        const fechaStr = data[`VENCIMIENTO_${campoBase}`];
        const dias = calcularDiasRestantes(fechaStr);
        if (dias == null) continue;
        const urgencia = hist.urgenciaPara(dias);
        if (!urgencia) continue;

        const params = {
          coleccion: 'EMPLEADOS',
          docId: dni,
          campoBase,
          urgencia: urgencia.codigo,
          fechaVenc: fechaStr,
        };
        if (await hist.yaSeEnvio(db, params)) {
          stats.salteados++;
          continue;
        }

        if (yaSuperoTope(telefono)) {
          stats.salteados++;
          log.debug(
            `Throttle: ${dni} ya recibió ${maxPorChoferDia} avisos hoy, salto ${campoBase}.`
          );
          continue;
        }

        const mensaje = aviso.build({
          item: {
            coleccion: 'EMPLEADOS',
            tipoDoc: etiqueta,
            docId: dni,
            titulo: data.NOMBRE || dni,
            fecha: fechaStr,
            dias,
          },
          destinatarioNombre: nombre,
        });

        try {
          const colaRef = await db.collection(fs.COLECCION).add({
            telefono: telefono.trim(),
            mensaje,
            estado: fs.ESTADO.pendiente,
            encolado_en: admin.firestore.FieldValue.serverTimestamp(),
            enviado_en: null,
            error: null,
            intentos: 0,
            origen: 'cron_aviso_vencimiento',
            destinatario_coleccion: 'EMPLEADOS',
            destinatario_id: dni,
            campo_base: campoBase,
            admin_dni: 'BOT',
            admin_nombre: 'Bot automático',
          });
          await hist.registrar(db, params, colaRef.id);
          bumpTope(telefono);
          stats.encolados++;
          log.info(
            `+ Encolado auto: ${etiqueta} de ${dni} (${urgencia.codigo}, ` +
              `${dias} días) → ${colaRef.id}`
          );
        } catch (e) {
          stats.errores++;
          log.error(`No se pudo encolar ${dni}/${campoBase}: ${e.message}`);
        }
      }
    }

    // ─── 2) Vencimientos de unidades (RTO, seguros, extintores) ───
    const vehiculosSnap = await db.collection('VEHICULOS').get();
    for (const vDoc of vehiculosSnap.docs) {
      const v = vDoc.data();
      const tipo = String(v.TIPO || '').toUpperCase();
      const specs = DOCS_VEHICULO[tipo];
      if (!specs) continue;

      // El destinatario es el chofer asignado a la unidad. Si nadie la
      // tiene asignada, no podemos avisar — el admin la verá en la
      // auditoría manual.
      const patente = vDoc.id;
      const chofer = choferByPatente.get(String(patente).trim().toUpperCase());
      if (!chofer) continue;
      const telefono = chofer.data.TELEFONO
        ? String(chofer.data.TELEFONO)
        : null;
      if (!telefono) continue;
      const nombre = aviso.resolverNombreSaludo(chofer.data);

      for (const spec of specs) {
        const fechaStr = v[spec.campoFecha];
        const dias = calcularDiasRestantes(fechaStr);
        if (dias == null) continue;
        const urgencia = hist.urgenciaPara(dias);
        if (!urgencia) continue;

        const params = {
          coleccion: 'VEHICULOS',
          docId: patente,
          campoBase: spec.campoBase,
          urgencia: urgencia.codigo,
          fechaVenc: fechaStr,
        };
        if (await hist.yaSeEnvio(db, params)) {
          stats.salteados++;
          continue;
        }

        if (yaSuperoTope(telefono)) {
          stats.salteados++;
          log.debug(
            `Throttle: chofer ${chofer.id} ya recibió ${maxPorChoferDia} avisos hoy, salto ${spec.campoBase}.`
          );
          continue;
        }

        const mensaje = aviso.build({
          item: {
            coleccion: 'VEHICULOS',
            tipoDoc: spec.etiqueta,
            docId: patente,
            titulo: `${tipo} - ${patente}`,
            fecha: fechaStr,
            dias,
          },
          destinatarioNombre: nombre,
        });

        try {
          const colaRef = await db.collection(fs.COLECCION).add({
            telefono: telefono.trim(),
            mensaje,
            estado: fs.ESTADO.pendiente,
            encolado_en: admin.firestore.FieldValue.serverTimestamp(),
            enviado_en: null,
            error: null,
            intentos: 0,
            origen: 'cron_aviso_vencimiento',
            destinatario_coleccion: 'VEHICULOS',
            destinatario_id: patente,
            campo_base: spec.campoBase,
            admin_dni: 'BOT',
            admin_nombre: 'Bot automático',
          });
          await hist.registrar(db, params, colaRef.id);
          bumpTope(telefono);
          stats.encolados++;
          log.info(
            `+ Encolado auto: ${spec.etiqueta} de ${patente} ` +
              `(${urgencia.codigo}, ${dias} días) → chofer ${chofer.id}`
          );
        } catch (e) {
          stats.errores++;
          log.error(
            `No se pudo encolar ${patente}/${spec.campoBase}: ${e.message}`
          );
        }
      }
    }

    // ─── 3) Service preventivo de TRACTORES ───
    // Para cada tractor: resolvemos `serviceDistanceKm` con la misma
    // lógica del cliente (API si está, sino calculado desde
    // `ULTIMO_SERVICE_KM + 50.000 - KM_ACTUAL`). Si entra en alguno de
    // los 4 niveles de urgencia, encolamos aviso al chofer asignado.
    //
    // Idempotencia: cuando el admin marca "service hecho" desde la app,
    // `ULTIMO_SERVICE_KM` cambia → el id determinístico cambia → ciclo
    // limpio para los próximos avisos.
    for (const vDoc of vehiculosSnap.docs) {
      const v = vDoc.data();
      const tipo = String(v.TIPO || '').toUpperCase();
      if (tipo !== 'TRACTOR') continue;

      const patente = vDoc.id;
      const chofer = choferByPatente.get(String(patente).trim().toUpperCase());
      if (!chofer) continue;
      const telefono = chofer.data.TELEFONO
        ? String(chofer.data.TELEFONO)
        : null;
      if (!telefono) continue;
      const nombre = aviso.resolverNombreSaludo(chofer.data);

      const serviceDistanceKm = _resolverServiceDistance(v);
      if (serviceDistanceKm == null) continue;
      const urgencia = hist.urgenciaServicePara(serviceDistanceKm);
      if (!urgencia) continue;

      // Para la idempotencia usamos `ULTIMO_SERVICE_KM` como
      // "anclaje del ciclo": cuando se hace un service nuevo, ese
      // valor cambia y el id se renueva.
      //
      // Bug C7 del code review: antes el fallback (sin manual) usaba
      // `Math.floor(KM_ACTUAL / 50000) * 50000`, que cambiaba al cruzar
      // los 50k km y disparaba avisos duplicados. Ahora si no hay
      // manual cargado, NO encolamos avisos preventivos — el admin
      // tiene que cargar `ULTIMO_SERVICE_KM` desde la app para que
      // la idempotencia funcione. Solo encolamos cuando viene de
      // `SERVICE_DISTANCE_KM` directo del API (que tiene anclaje
      // implícito en el endpoint Volvo).
      let anclaCiclo;
      if (v.ULTIMO_SERVICE_KM != null) {
        anclaCiclo = Math.round(Number(v.ULTIMO_SERVICE_KM));
      } else if (v.SERVICE_DISTANCE_KM != null) {
        // Camino API: el dato viene de Volvo. Anclamos por la "fecha
        // efectiva del próximo service" (KM_ACTUAL + serviceDistance),
        // redondeado a int. Cuando el admin haga service y reset, ese
        // anclaje cambia.
        anclaCiclo = Math.round(
          Number(v.KM_ACTUAL || 0) + Number(v.SERVICE_DISTANCE_KM || 0)
        );
      } else {
        // Sin ningún anclaje confiable → no encolamos. El admin verá
        // el tractor en estado "Sin datos" en la pantalla y debe
        // cargar el último service.
        continue;
      }

      const params = {
        coleccion: 'VEHICULOS',
        docId: patente,
        campoBase: 'SERVICE',
        urgencia: urgencia.codigo,
        // El historico usa esta clave como `fechaVenc`, pero acá el
        // "período" se identifica por el km del último service en
        // lugar de una fecha. La función `buildId` lo concatena tal
        // cual, así que un string del km nos sirve igual.
        fechaVenc: String(anclaCiclo),
      };
      if (await hist.yaSeEnvio(db, params)) {
        stats.salteados++;
        continue;
      }

      if (yaSuperoTope(telefono)) {
        stats.salteados++;
        log.debug(
          `Throttle: chofer ${chofer.id} ya recibió ${maxPorChoferDia} avisos hoy, salto SERVICE de ${patente}.`
        );
        continue;
      }

      const mensaje = avisoService.build({
        patente,
        marca: v.MARCA,
        modelo: v.MODELO,
        serviceDistanceKm,
        destinatarioNombre: nombre,
      });
      // build() devuelve null si los datos no son válidos (NaN, patente
      // vacía, etc). En ese caso saltamos sin encolar.
      if (!mensaje) {
        log.warn(
          `Service ${patente}: datos inválidos (km=${serviceDistanceKm}), no encolo.`
        );
        continue;
      }

      try {
        const colaRef = await db.collection(fs.COLECCION).add({
          telefono: telefono.trim(),
          mensaje,
          estado: fs.ESTADO.pendiente,
          encolado_en: admin.firestore.FieldValue.serverTimestamp(),
          enviado_en: null,
          error: null,
          intentos: 0,
          origen: 'cron_aviso_service',
          destinatario_coleccion: 'VEHICULOS',
          destinatario_id: patente,
          campo_base: 'SERVICE',
          admin_dni: 'BOT',
          admin_nombre: 'Bot automático',
        });
        await hist.registrar(db, params, colaRef.id);
        bumpTope(telefono);
        stats.encolados++;
        log.info(
          `+ Encolado service: ${patente} (${urgencia.codigo}, ` +
            `${Math.round(serviceDistanceKm)} km) → chofer ${chofer.id}`
        );
      } catch (e) {
        stats.errores++;
        log.error(
          `No se pudo encolar service ${patente}: ${e.message}`
        );
      }
    }

    log.info(
      `Cron ciclo cerrado: encolados=${stats.encolados} ` +
        `salteados=${stats.salteados} errores=${stats.errores}`
    );
    health.registrarCicloCron(stats);
  } catch (e) {
    log.error(`Cron falló: ${e.stack || e.message}`);
    health.registrarError('cron', e.message);
  } finally {
    _running = false;
  }
}

/**
 * Calcula `serviceDistanceKm` para un doc de VEHICULOS.
 *
 * Prioridad:
 *  1. Si el doc tiene `SERVICE_DISTANCE_KM` (vino del API Volvo) → usar
 *     ese (puede ser negativo para vencido).
 *  2. Sino, si tiene `ULTIMO_SERVICE_KM` y `KM_ACTUAL` → calcular
 *     `(ULTIMO_SERVICE_KM + 50.000) − KM_ACTUAL`.
 *  3. Sino → null (sin datos suficientes).
 *
 * Espejo de `_resolverServiceDistance` en el cliente Dart.
 */
function _resolverServiceDistance(v) {
  const api = Number(v.SERVICE_DISTANCE_KM);
  if (!isNaN(api) && v.SERVICE_DISTANCE_KM != null) return api;

  const ultimo = Number(v.ULTIMO_SERVICE_KM);
  const actual = Number(v.KM_ACTUAL);
  if (
    !isNaN(ultimo) &&
    !isNaN(actual) &&
    v.ULTIMO_SERVICE_KM != null &&
    v.KM_ACTUAL != null
  ) {
    return ultimo + INTERVALO_SERVICE_KM - actual;
  }
  return null;
}

// `_buscarChofer` removida — reemplazada por el índice inverso
// `choferByPatente` que se construye una vez al inicio del ciclo y
// permite lookup O(1) en lugar de O(n) por cada vencimiento.

/**
 * Devuelve un Date apuntando al inicio del día actual en zona local
 * del server. Usado por el throttle por chofer para contar avisos de
 * "hoy".
 */
function _inicioDelDia() {
  const d = new Date();
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

module.exports = {
  start,
  stop,
  // Exportados para tests / uso interno:
  calcularDiasRestantes,
  DOCS_EMPLEADO,
  DOCS_VEHICULO,
  INTERVALO_SERVICE_KM,
};

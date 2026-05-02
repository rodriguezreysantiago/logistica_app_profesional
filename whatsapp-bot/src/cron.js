// Cron interno del bot — Fase 2.
//
// Cada N minutos (default 60) recorre EMPLEADOS y VEHICULOS, calcula
// urgencia de cada vencimiento, y encola avisos automáticos en
// COLA_WHATSAPP. La idempotencia se garantiza con AVISOS_AUTOMATICOS_HISTORICO
// (ver historico.js): el mismo aviso (mismo nivel de urgencia, misma
// fecha de vencimiento) se envía una sola vez.
//
// AGRUPACIÓN POR CHOFER (2026-04-30): si un mismo chofer tiene 2+
// vencimientos para avisar en el mismo ciclo, mandamos UN solo mensaje
// con la lista completa en lugar de N mensajes separados. Eso reduce
// drásticamente la huella de bot ante WhatsApp (mensajes consecutivos
// al mismo número en pocos segundos = signal fuerte de spam) y le da
// al chofer toda la info de un saque.

const admin = require('firebase-admin');
const log = require('./logger');
const { enHorarioHabil } = require('./humano');
const aviso = require('./aviso_builder');
const avisoService = require('./aviso_service_builder');
const avisoAlertasVolvo = require('./aviso_alertas_volvo_builder');
const hist = require('./historico');
const health = require('./health');
const fs = require('./firestore');
const { aIsoLocal } = require('./fechas');

// Intervalo entre services programados de tractores Volvo, en KM.
const INTERVALO_SERVICE_KM = 50000;

// Documentos auditados de EMPLEADOS — replica del listado en
// `lib/features/expirations/screens/admin_vencimientos_choferes_screen.dart`.
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
    { etiqueta: 'Extintor Cabina', campoFecha: 'VENCIMIENTO_EXTINTOR_CABINA', campoBase: 'EXTINTOR_CABINA' },
    { etiqueta: 'Extintor Exterior', campoFecha: 'VENCIMIENTO_EXTINTOR_EXTERIOR', campoBase: 'EXTINTOR_EXTERIOR' },
  ],
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
 * Parseo manual de YYYY-MM-DD para evitar el shift UTC vs local que
 * `new Date("YYYY-MM-DD")` aplica (medianoche UTC = 21h del día
 * anterior en ART → días corridos para atrás).
 */
function calcularDiasRestantes(fechaIso) {
  if (!fechaIso) return null;
  const str = String(fechaIso).trim();
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(str);
  let venc;
  if (m) {
    venc = new Date(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10));
  } else {
    venc = new Date(str);
  }
  if (isNaN(venc.getTime())) return null;
  const hoy = new Date();
  const a = new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate());
  const b = new Date(venc.getFullYear(), venc.getMonth(), venc.getDate());
  const ms = b.getTime() - a.getTime();
  return Math.round(ms / (1000 * 60 * 60 * 24));
}

let _running = false;
let _timer = null;

function start(fs) {
  if (_timer) return;
  const enabled =
    String(process.env.AUTO_AVISOS_ENABLED || 'false').toLowerCase() === 'true';
  if (!enabled) {
    log.info(
      'Cron de avisos automáticos DESHABILITADO (AUTO_AVISOS_ENABLED=false). ' +
        'Habilitar en .env cuando confirmes que el bot envía bien.'
    );
    return;
  }

  const intervaloMin = parseInt(process.env.CRON_INTERVAL_MINUTES || '60', 10);
  const intervaloMs = intervaloMin * 60 * 1000;
  log.info(`Cron de avisos automáticos HABILITADO (cada ${intervaloMin} min).`);

  // Patrón setTimeout recursivo (no setInterval): el siguiente ciclo
  // solo se programa DESPUÉS de que termina el anterior. Evita brechas
  // cuando un ciclo tarda más que el intervalo (ej: cron tarda 70min
  // con intervalo de 60min → con setInterval se perdían ciclos; con
  // setTimeout recursivo el siguiente arranca a los 60min DESPUÉS de
  // que el anterior termine).
  const programarProximo = () => {
    _timer = setTimeout(async () => {
      try {
        await _runOnce(fs);
      } catch (e) {
        log.error(`Cron _runOnce no atrapado: ${e.message}`);
      } finally {
        if (_timer) programarProximo(); // si stop() corrió, _timer = null
      }
    }, intervaloMs);
  };

  // Primera corrida más rápida (30s después de arrancar) y después se
  // engancha al ciclo recursivo.
  _timer = setTimeout(async () => {
    try {
      await _runOnce(fs);
    } catch (e) {
      log.error(`Cron _runOnce inicial no atrapado: ${e.message}`);
    } finally {
      if (_timer) programarProximo();
    }
  }, 30000);
}

function stop() {
  if (_timer) {
    clearTimeout(_timer);
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
  const stats = { encolados: 0, agrupados: 0, salteados: 0, errores: 0 };

  try {
    // ─── Cleanup de historico viejo (mantenimiento de coleccion) ──
    // Borra hasta 500 docs de AVISOS_AUTOMATICOS_HISTORICO con
    // `creado_en` > 90 dias atras. Sin esto, la coleccion crece
    // indefinidamente (cada urgencia + cada chofer + cada fecha
    // genera un doc). Es barato (1 query + 1 batch) y se hace cada
    // ciclo del cron (1x por hora aprox), asi que la limpieza es
    // gradual y nunca acumula.
    try {
      await hist.limpiarObsoletos(db);
    } catch (e) {
      log.warn(`Cleanup de historico fallo: ${e.message}`);
    }

    // ─── Cargar empleados + índice patente → chofer ───
    const empleadosSnap = await db.collection('EMPLEADOS').get();
    const empleadosByDni = new Map();
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

    // ─── Recolectar items por chofer ───
    // Map<dni, { chofer, items: [{tipo, tipoDoc, dias, fecha, referencia, params}] }>
    // `params` se usa para el registro de idempotencia individual.
    const itemsPorChofer = new Map();

    function _addItem(dni, chofer, item) {
      if (!itemsPorChofer.has(dni)) {
        itemsPorChofer.set(dni, { chofer, items: [] });
      }
      itemsPorChofer.get(dni).items.push(item);
    }

    // 1) Vencimientos personales del chofer
    for (const [dni, emp] of empleadosByDni) {
      const data = emp.data;
      const telefono = data.TELEFONO ? String(data.TELEFONO) : null;
      if (!telefono) continue;

      for (const [etiqueta, campoBase] of Object.entries(DOCS_EMPLEADO)) {
        // Normalizamos a YYYY-MM-DD via aIsoLocal: cubre strings,
        // Timestamps de Firestore, Date objects y JSON con _seconds
        // sin sufrir el shift UTC vs ART (bug del 2026-05).
        const fechaStr = aIsoLocal(data[`VENCIMIENTO_${campoBase}`]);
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
        _addItem(dni, emp, {
          tipo: 'vencimiento',
          tipoDoc: etiqueta,
          dias,
          fecha: fechaStr,
          referencia: null, // personal del chofer, sin referencia a unidad
          params,
        });
      }
    }

    // 2) Vencimientos de unidades (asignadas al chofer)
    const vehiculosSnap = await db.collection('VEHICULOS').get();
    for (const vDoc of vehiculosSnap.docs) {
      const v = vDoc.data();
      const tipo = String(v.TIPO || '').toUpperCase();
      const specs = DOCS_VEHICULO[tipo];
      if (!specs) continue;

      const patente = vDoc.id;
      const chofer = choferByPatente.get(String(patente).trim().toUpperCase());
      if (!chofer) continue;
      const telefono = chofer.data.TELEFONO ? String(chofer.data.TELEFONO) : null;
      if (!telefono) continue;

      for (const spec of specs) {
        // Misma normalizacion que para vencimientos personales.
        const fechaStr = aIsoLocal(v[spec.campoFecha]);
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
        _addItem(chofer.id, chofer, {
          tipo: 'vencimiento',
          tipoDoc: spec.etiqueta,
          dias,
          fecha: fechaStr,
          referencia: `${tipo} ${patente}`,
          params,
        });
      }
    }

    // 3) Service preventivo de TRACTORES
    //
    // CAMBIO 2026-05: el aviso de service ya NO se manda al chofer del
    // tractor. Va consolidado en UN solo mensaje diario al encargado
    // de mantenimiento (SERVICE_DESTINATARIO_DNI en .env, ej.
    // Emmanuel Corchete). Recolectamos aca todos los tractores con
    // urgencia y los procesamos despues del loop "por chofer", en un
    // bloque dedicado.
    const tractoresConUrgencia = [];
    for (const vDoc of vehiculosSnap.docs) {
      const v = vDoc.data();
      const tipo = String(v.TIPO || '').toUpperCase();
      if (tipo !== 'TRACTOR') continue;

      const patente = vDoc.id;
      const serviceDistanceKm = _resolverServiceDistance(v);
      if (serviceDistanceKm == null) continue;
      const urgencia = hist.urgenciaServicePara(serviceDistanceKm);
      if (!urgencia) continue;

      tractoresConUrgencia.push({
        patente,
        urgencia: urgencia.codigo,
        km: serviceDistanceKm,
        marca: v.MARCA || '',
        modelo: v.MODELO || '',
      });
    }

    // ─── Encolar mensajes (agrupados por chofer) ───
    for (const [dni, { chofer, items }] of itemsPorChofer) {
      if (items.length === 0) continue;
      const telefono = chofer.data.TELEFONO ? String(chofer.data.TELEFONO).trim() : null;
      if (!telefono) continue;
      const nombre = aviso.resolverNombreSaludo(chofer.data);

      let mensaje;
      let origen;
      if (items.length === 1) {
        // Un solo item — mensaje individual con variantes (texto más
        // natural y empático para casos sueltos).
        const item = items[0];
        if (item.tipo === 'service') {
          // Service usa builder dedicado.
          const v = vehiculosSnap.docs.find((d) => d.id === item.referencia.split(' ').pop());
          mensaje = avisoService.build({
            patente: item.referencia,
            marca: v ? v.data().MARCA : '',
            modelo: v ? v.data().MODELO : '',
            serviceDistanceKm: item.dias,
            destinatarioNombre: nombre,
          });
          if (!mensaje) {
            log.warn(`Service ${item.referencia}: datos inválidos, salto.`);
            continue;
          }
          origen = 'cron_aviso_service';
        } else {
          // Vencimiento normal.
          const titulo = item.referencia
            ? `${item.referencia}` // ya viene formateado "TRACTOR AB123"
            : (chofer.data.NOMBRE || dni);
          mensaje = aviso.build({
            item: {
              coleccion: item.params.coleccion,
              tipoDoc: item.tipoDoc,
              docId: item.params.docId,
              titulo,
              fecha: item.fecha,
              dias: item.dias,
            },
            destinatarioNombre: nombre,
          });
          origen = 'cron_aviso_vencimiento';
        }
      } else {
        // 2+ items — mensaje agrupado.
        mensaje = aviso.buildAgrupado({
          destinatarioNombre: nombre,
          items: items.map((it) => ({
            tipo: it.tipo,
            tipoDoc: it.tipoDoc,
            dias: it.dias,
            fecha: it.fecha,
            referencia: it.referencia,
          })),
        });
        origen = 'cron_aviso_agrupado';
        stats.agrupados++;
      }

      // Encolar UN solo doc en COLA_WHATSAPP.
      try {
        const colaRef = await db.collection(fs.COLECCION).add({
          telefono,
          mensaje,
          estado: fs.ESTADO.pendiente,
          encolado_en: admin.firestore.FieldValue.serverTimestamp(),
          enviado_en: null,
          error: null,
          intentos: 0,
          origen,
          destinatario_coleccion: 'EMPLEADOS',
          destinatario_id: dni,
          campo_base: items.length === 1 ? items[0].params.campoBase : 'AGRUPADO',
          admin_dni: 'BOT',
          admin_nombre: 'Bot automático',
          // Si es agrupado, guardamos también qué papeles incluyó —
          // útil para debugging y para que la pantalla de cola muestre
          // un resumen en vez de "AGRUPADO" pelado.
          items_agrupados: items.length > 1
            ? items.map((it) => ({
                tipoDoc: it.tipoDoc,
                campoBase: it.params.campoBase,
                coleccion: it.params.coleccion,
                docId: it.params.docId,
                fecha: it.fecha,
                dias: it.dias,
              }))
            : null,
        });

        // Registrar idempotencia POR ITEM (cada papel queda marcado
        // individualmente, así si mañana se suma un papel nuevo solo
        // ese se va a re-encolar — los demás ya están "marcados").
        for (const item of items) {
          await hist.registrar(db, item.params, colaRef.id);
        }

        stats.encolados++;
        if (items.length === 1) {
          log.info(`+ Encolado: ${dni} ${items[0].tipoDoc} → ${colaRef.id}`);
        } else {
          log.info(
            `+ Encolado AGRUPADO: ${dni} (${items.length} papeles) → ${colaRef.id}`
          );
        }
      } catch (e) {
        stats.errores++;
        log.error(`No se pudo encolar para ${dni}: ${e.message}`);
      }
    }

    // ─── Service diario consolidado (1 msj/dia al encargado) ─────
    const dniDestinatarioService = process.env.SERVICE_DESTINATARIO_DNI;
    if (dniDestinatarioService) {
      const yaEnviado = await hist.yaSeEnvioServiceDiario(db, dniDestinatarioService);
      if (yaEnviado) {
        log.debug(`Service diario ya enviado hoy a ${dniDestinatarioService}, skip.`);
      } else {
        const empDest = empleadosByDni.get(String(dniDestinatarioService).trim());
        if (!empDest) {
          log.warn(
            `SERVICE_DESTINATARIO_DNI=${dniDestinatarioService} no esta en EMPLEADOS. ` +
            `Service diario no se envia hoy.`
          );
        } else {
          const telefonoDest = empDest.data.TELEFONO ? String(empDest.data.TELEFONO).trim() : null;
          if (!telefonoDest) {
            log.warn(
              `Destinatario service ${dniDestinatarioService} no tiene TELEFONO. ` +
              `Service diario no se envia hoy.`
            );
          } else {
            const apodoDest = aviso.resolverNombreSaludo(empDest.data);
            const mensajeService = avisoService.buildResumenDiario({
              destinatarioNombre: apodoDest,
              tractores: tractoresConUrgencia,
            });
            try {
              const colaRef = await db.collection(fs.COLECCION).add({
                telefono: telefonoDest,
                mensaje: mensajeService,
                estado: fs.ESTADO.pendiente,
                encolado_en: admin.firestore.FieldValue.serverTimestamp(),
                enviado_en: null,
                error: null,
                intentos: 0,
                origen: 'cron_service_diario',
                destinatario_coleccion: 'EMPLEADOS',
                destinatario_id: dniDestinatarioService,
                campo_base: 'SERVICE_DIARIO',
                admin_dni: 'BOT',
                admin_nombre: 'Bot automatico',
                // Lista de tractores incluidos en el reporte. La pantalla
                // "Cola de WhatsApp" puede mostrarlos desplegables
                // (mismo patron que items_agrupados de vencimientos).
                items_agrupados: tractoresConUrgencia.length > 0
                  ? tractoresConUrgencia.map((t) => ({
                      tipoDoc: 'Service',
                      campoBase: 'SERVICE',
                      coleccion: 'VEHICULOS',
                      docId: t.patente,
                      fecha: null,
                      dias: t.km,
                      urgencia: t.urgencia,
                    }))
                  : null,
              });
              await hist.registrarServiceDiario(db, dniDestinatarioService, {
                cantidadTractores: tractoresConUrgencia.length,
                colaDocId: colaRef.id,
              });
              stats.encolados++;
              log.info(
                `+ Encolado SERVICE DIARIO: ${dniDestinatarioService} ` +
                `(${tractoresConUrgencia.length} tractores) -> ${colaRef.id}`
              );
            } catch (e) {
              stats.errores++;
              log.error(`No se pudo encolar service diario: ${e.message}`);
            }
          }
        }
      }
    } else {
      log.debug('SERVICE_DESTINATARIO_DNI no configurado. Skip aviso service diario.');
    }

    // ─── Alertas Volvo: resumen diario al admin ─────────────────────
    // Mismo patron que service diario: 1 mensaje por dia con el listado
    // consolidado de eventos HIGH severity de las ultimas 24h. Se envia
    // al primer ciclo del dia que cae en horario habil (~8:00 ART).
    // Si no hubo eventos HIGH, NO se manda nada (silencio = nada que
    // reportar; mandar "todo OK" todos los dias seria ruido para algo
    // que ya tiene baja frecuencia).
    const dniAlertasResumen = process.env.ALERTAS_RESUMEN_DESTINATARIO_DNI;
    if (dniAlertasResumen) {
      const yaEnviadoAlertas = await hist.yaSeEnvioAlertasResumen(
        db,
        dniAlertasResumen
      );
      if (yaEnviadoAlertas) {
        log.debug(
          `Alertas Volvo resumen ya enviado hoy a ${dniAlertasResumen}, skip.`
        );
      } else {
        const empAlertas = empleadosByDni.get(
          String(dniAlertasResumen).trim()
        );
        if (!empAlertas) {
          log.warn(
            `ALERTAS_RESUMEN_DESTINATARIO_DNI=${dniAlertasResumen} no esta en EMPLEADOS. ` +
              `Resumen alertas Volvo no se envia hoy.`
          );
        } else {
          const telAlertas = empAlertas.data.TELEFONO
            ? String(empAlertas.data.TELEFONO).trim()
            : null;
          if (!telAlertas) {
            log.warn(
              `Destinatario alertas ${dniAlertasResumen} no tiene TELEFONO. ` +
                `Resumen alertas Volvo no se envia hoy.`
            );
          } else {
            // Query VOLVO_ALERTAS de las ultimas 24h con severidad HIGH.
            const desde = admin.firestore.Timestamp.fromMillis(
              Date.now() - 24 * 60 * 60 * 1000
            );
            const alertasSnap = await db
              .collection('VOLVO_ALERTAS')
              .where('severidad', '==', 'HIGH')
              .where('creado_en', '>=', desde)
              .get();
            const eventos = alertasSnap.docs.map((d) => {
              const data = d.data();
              const patente = String(data.patente || '—').trim();
              const tipo = String(data.tipo || '').trim();
              const creadoEn = data.creado_en;
              const fechaHora = creadoEn && typeof creadoEn.toDate === 'function'
                ? creadoEn.toDate()
                : new Date();
              // Lookup chofer por patente (mapa ya cargado al inicio
              // del cron). Si no hay match, dejamos null y el builder
              // lo muestra como "patente sin chofer".
              const chofer = choferByPatente.get(
                patente.toUpperCase()
              );
              const choferNombre = chofer
                ? aviso.resolverNombreSaludo(chofer.data)
                : null;
              return { patente, tipo, choferNombre, fechaHora };
            });

            if (eventos.length === 0) {
              log.info(
                `Resumen alertas Volvo: 0 eventos HIGH en ultimas 24h, ` +
                  `no se envia mensaje.`
              );
              // Marcamos en historico igual para que no se chequee mil
              // veces en el mismo dia. Idempotencia diaria preservada.
              await hist.registrarAlertasResumen(db, dniAlertasResumen, {
                cantidadEventos: 0,
                colaDocId: null,
              });
            } else {
              const apodoAlertas = aviso.resolverNombreSaludo(empAlertas.data);
              const mensajeAlertas = avisoAlertasVolvo.buildResumenDiario({
                destinatarioNombre: apodoAlertas,
                eventos,
              });
              if (!mensajeAlertas) {
                // No deberia pasar (eventos.length > 0 garantiza que el
                // builder devuelve string), pero defensivo.
                log.warn(
                  `Builder de resumen alertas devolvio null con ${eventos.length} ` +
                    `eventos. Skip.`
                );
              } else {
                try {
                  const colaRef = await db.collection(fs.COLECCION).add({
                    telefono: telAlertas,
                    mensaje: mensajeAlertas,
                    estado: fs.ESTADO.pendiente,
                    encolado_en: admin.firestore.FieldValue.serverTimestamp(),
                    enviado_en: null,
                    error: null,
                    intentos: 0,
                    origen: 'cron_alertas_volvo_diario',
                    destinatario_coleccion: 'EMPLEADOS',
                    destinatario_id: dniAlertasResumen,
                    campo_base: 'ALERTAS_VOLVO_DIARIO',
                    admin_dni: 'BOT',
                    admin_nombre: 'Bot automatico',
                    items_agrupados: eventos.map((e) => ({
                      tipoDoc: 'AlertaVolvo',
                      campoBase: 'ALERTAS_VOLVO',
                      coleccion: 'VOLVO_ALERTAS',
                      docId: `${e.patente}_${e.tipo}_${e.fechaHora.toISOString()}`,
                      fecha: e.fechaHora.toISOString(),
                      tipo: e.tipo,
                      chofer: e.choferNombre,
                    })),
                  });
                  await hist.registrarAlertasResumen(db, dniAlertasResumen, {
                    cantidadEventos: eventos.length,
                    colaDocId: colaRef.id,
                  });
                  stats.encolados++;
                  log.info(
                    `+ Encolado RESUMEN ALERTAS VOLVO: ${dniAlertasResumen} ` +
                      `(${eventos.length} eventos HIGH 24h) -> ${colaRef.id}`
                  );
                } catch (e) {
                  stats.errores++;
                  log.error(
                    `No se pudo encolar resumen alertas Volvo: ${e.message}`
                  );
                }
              }
            }
          }
        }
      }
    } else {
      log.debug(
        'ALERTAS_RESUMEN_DESTINATARIO_DNI no configurado. Skip resumen alertas Volvo.'
      );
    }

    log.info(
      `Cron ciclo cerrado: encolados=${stats.encolados} ` +
        `(de los cuales ${stats.agrupados} agrupados) ` +
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
 * Espejo de `_resolverServiceDistance` en el cliente Dart.
 */
function _resolverServiceDistance(v) {
  const api = Number(v.SERVICE_DISTANCE_KM);
  if (!isNaN(api) && v.SERVICE_DISTANCE_KM != null) return api;

  const ultimo = Number(v.ULTIMO_SERVICE_KM);
  const actual = Number(v.KM_ACTUAL);
  if (!isNaN(ultimo) && !isNaN(actual) && v.ULTIMO_SERVICE_KM != null && v.KM_ACTUAL != null) {
    return ultimo + INTERVALO_SERVICE_KM - actual;
  }
  return null;
}

/**
 * Fuerza una corrida del cron AHORA, ignorando el setInterval. Usado
 * por el comando admin /forzar-cron y por tests. Idempotente con
 * `_running`: si ya hay uno corriendo, sale silencioso.
 *
 * @returns {Promise<{stats: object} | {skipped: true}>}
 */
async function forzarRunOnce(fs) {
  if (_running) {
    log.info('forzarRunOnce: ya hay un ciclo en progreso, salteo.');
    return { skipped: true };
  }
  return _runOnce(fs);
}

module.exports = {
  start,
  stop,
  forzarRunOnce,
  // Exportado para tests / debugging.
  calcularDiasRestantes,
};

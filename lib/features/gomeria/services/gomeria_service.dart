import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/audit_log_service.dart';
import '../constants/posiciones.dart';
import '../models/cubierta.dart';
import '../models/cubierta_instalada.dart';
import '../models/cubierta_modelo.dart';
import '../models/cubierta_recapado.dart';

/// Único punto de entrada para mutar el inventario de cubiertas y su
/// ciclo de vida (alta, instalación, retiro, recapado, descarte).
///
/// **Por qué es un service único**: las operaciones tocan varias colecciones
/// en simultáneo y necesitan validaciones cruzadas (ej. tipo_uso vs
/// posición, no instalar dos cubiertas en la misma posición, sumar
/// km_acumulados al retirar). Tener un único punto evita inconsistencias
/// si la UI evoluciona o si se agregan más callers (Cloud Function de
/// alertas, ABM admin, importación masiva).
///
/// **Transactional para writes que tocan más de una colección**:
/// - instalar: lee posición ocupada (READ) + crea CUBIERTAS_INSTALADAS +
///   actualiza CUBIERTAS.estado.
/// - retirar: cierra CUBIERTAS_INSTALADAS + actualiza CUBIERTAS.estado y
///   km_acumulados.
/// - mandarARecapar: crea CUBIERTAS_RECAPADOS + actualiza CUBIERTAS.estado.
/// - recibirDeRecapado: cierra CUBIERTAS_RECAPADOS + actualiza
///   CUBIERTAS.estado/vidas (si RECIBIDA) o estado=DESCARTADA.
///
/// **Cálculo de km recorridos al retirar**:
/// - Tractor: `KM_ACTUAL del tractor − km_unidad_al_instalar` directo.
/// - Enganche: en Fase 1 queda `null`. Fase 2 lo calcula cruzando con
///   `ASIGNACIONES_ENGANCHE` (qué tractores arrastraron este enganche
///   durante el período de la instalación). Lógica diferida porque
///   requiere otra subquery por cada tractor — primero hagamos andar el
///   loop básico.
class GomeriaService {
  final FirebaseFirestore _db;

  GomeriaService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  /// DocId estable del lock de posición. Combina patente + posición con
  /// `__` (doble underscore) — patente nunca lleva esa secuencia y los
  /// códigos de posición son ASCII alfanuméricos con `_` simple.
  static String _posicionLockId(String unidadId, String posicionCodigo) =>
      '${unidadId}__$posicionCodigo';

  // ===========================================================================
  // ALTA DE CUBIERTAS
  // ===========================================================================

  /// Genera el próximo código `CUB-XXXX` zero-padded a 4 dígitos.
  ///
  /// Lo hace en una transaction sobre `META/cubiertas_counter`. Si el doc
  /// no existe, arranca en 1. El padding crece naturalmente a 5 dígitos
  /// cuando supere 9999 (el orden lexicográfico se rompe pero ya es
  /// problema futuro — Vecchi tiene < 200 cubiertas hoy).
  Future<String> _proximoCodigoCubierta(Transaction tx) async {
    final ref = _db.collection(AppCollections.meta).doc('cubiertas_counter');
    final snap = await tx.get(ref);
    final actual = (snap.data()?['proximo'] as num?)?.toInt() ?? 0;
    final siguiente = actual + 1;
    tx.set(ref, {'proximo': siguiente}, SetOptions(merge: true));
    return 'CUB-${siguiente.toString().padLeft(4, '0')}';
  }

  /// Da de alta una cubierta nueva en estado `EN_DEPOSITO` con vidas=1.
  ///
  /// Devuelve el doc id generado. El [modeloId] debe existir (se valida
  /// dentro de la transaction y se guarda snapshot del modelo para
  /// queries sin join).
  ///
  /// Si se pasa [precioCompra], queda guardado en `CUBIERTAS.precio_compra`
  /// — habilita el cálculo de costo por km en reportes.
  Future<String> crearCubierta({
    required String modeloId,
    required String supervisorDni,
    String? supervisorNombre,
    String? observaciones,
    double? precioCompra,
  }) async {
    final modeloLimpio = modeloId.trim();
    if (modeloLimpio.isEmpty) {
      throw ArgumentError('modeloId vacío');
    }
    final supervisorLimpio = supervisorDni.trim();
    if (supervisorLimpio.isEmpty) {
      throw ArgumentError('supervisorDni vacío');
    }

    final cubiertaId = _db.collection(AppCollections.cubiertas).doc().id;

    final codigo = await _db.runTransaction((tx) async {
      final modeloRef =
          _db.collection(AppCollections.cubiertasModelos).doc(modeloLimpio);
      final modeloSnap = await tx.get(modeloRef);
      if (!modeloSnap.exists) {
        throw StateError('Modelo $modeloLimpio no existe');
      }
      final modelo = CubiertaModelo.fromMap(modeloLimpio, modeloSnap.data());
      if (!modelo.activo) {
        throw StateError('Modelo ${modelo.etiqueta} está dado de baja');
      }

      final codigoNuevo = await _proximoCodigoCubierta(tx);

      final cubiertaRef =
          _db.collection(AppCollections.cubiertas).doc(cubiertaId);
      tx.set(cubiertaRef, <String, dynamic>{
        'codigo': codigoNuevo,
        'modelo_id': modeloLimpio,
        'modelo_etiqueta': modelo.etiqueta,
        'tipo_uso': modelo.tipoUso.codigo,
        'estado': EstadoCubierta.enDeposito.codigo,
        'vidas': 1,
        'km_acumulados': 0,
        if (observaciones != null && observaciones.trim().isNotEmpty)
          'observaciones': observaciones.trim(),
        if (precioCompra != null && precioCompra > 0)
          'precio_compra': precioCompra,
        'creado_en': FieldValue.serverTimestamp(),
        'creado_por_dni': supervisorLimpio,
        if (supervisorNombre != null && supervisorNombre.trim().isNotEmpty)
          'creado_por_nombre': supervisorNombre.trim(),
      });

      return codigoNuevo;
    });

    unawaited(AuditLog.registrar(
      accion: AuditAccion.crearCubierta,
      entidad: AppCollections.cubiertas,
      entidadId: cubiertaId,
      detalles: {
        'codigo': codigo,
        'modelo_id': modeloLimpio,
      },
    ));

    return cubiertaId;
  }

  // ===========================================================================
  // INSTALAR / RETIRAR
  // ===========================================================================

  /// Instala una cubierta en una posición específica de una unidad.
  ///
  /// Validaciones (todas dentro de la transaction):
  /// - La cubierta existe y está EN_DEPOSITO.
  /// - La posición existe y `aceptaTipoUso(cubierta.tipoUso) == true`.
  ///   STRICT: una cubierta TRACCION no se puede instalar en posición
  ///   DIRECCION (decisión confirmada por Santiago: "es un error de tipeo
  ///   seguramente").
  /// - La posición no tiene otra cubierta activa (nadie más en
  ///   `CUBIERTAS_INSTALADAS` con `unidad_id == X && posicion == Y &&
  ///   hasta == null`).
  /// - La unidad existe en VEHICULOS y su TIPO coincide con [unidadTipo].
  ///
  /// Si todo OK: crea CUBIERTAS_INSTALADAS (activa) y actualiza
  /// `CUBIERTAS.estado = INSTALADA`.
  Future<String> instalar({
    required String cubiertaId,
    required String unidadId,
    required TipoUnidadCubierta unidadTipo,
    required String posicionCodigo,
    required String supervisorDni,
    String? supervisorNombre,
    String? motivo,
  }) async {
    final cubiertaLimpia = cubiertaId.trim();
    final unidadLimpia = unidadId.trim().toUpperCase();
    final posicionLimpia = posicionCodigo.trim().toUpperCase();
    final supervisorLimpio = supervisorDni.trim();
    if (cubiertaLimpia.isEmpty ||
        unidadLimpia.isEmpty ||
        posicionLimpia.isEmpty ||
        supervisorLimpio.isEmpty) {
      throw ArgumentError(
          'cubiertaId, unidadId, posicionCodigo y supervisorDni son obligatorios');
    }

    // Resolver la posición desde el catálogo en compile-time. Si no existe
    // es un bug del caller (la UI mandó un código que no figura).
    final posicion = posicionPorCodigo[posicionLimpia];
    if (posicion == null) {
      throw ArgumentError('Posición desconocida: $posicionLimpia');
    }
    if (posicion.tipoUnidad != unidadTipo) {
      throw ArgumentError(
        'Posición $posicionLimpia es de ${posicion.tipoUnidad.codigo}, '
        'no de ${unidadTipo.codigo}',
      );
    }

    final instalacionId =
        _db.collection(AppCollections.cubiertasInstaladas).doc().id;

    final posicionLockId = _posicionLockId(unidadLimpia, posicionLimpia);

    await _db.runTransaction((tx) async {
      // 1) Locks de unicidad — se leen FIRST con `tx.get` para
      //    detectar colisiones aún si dos clientes instalan en paralelo.
      //    `where().get()` dentro de tx no es transaccional en client
      //    SDK, así que esta es la única forma de garantizar atomicidad.
      final posicionLockRef = _db
          .collection(AppCollections.cubiertasPosicionesActivas)
          .doc(posicionLockId);
      final posicionLockSnap = await tx.get(posicionLockRef);
      if (posicionLockSnap.exists) {
        final otroCodigo =
            (posicionLockSnap.data()?['cubierta_codigo'] ?? '').toString();
        throw StateError(
          'La posición ${posicion.etiqueta} ya tiene la cubierta '
          '$otroCodigo instalada. Retirala primero.',
        );
      }
      final cubiertaLockRef = _db
          .collection(AppCollections.cubiertasActivas)
          .doc(cubiertaLimpia);
      final cubiertaLockSnap = await tx.get(cubiertaLockRef);
      if (cubiertaLockSnap.exists) {
        throw StateError(
          'La cubierta $cubiertaLimpia figura activa en otra posición. '
          'Cerrá esa instalación antes de instalar acá.',
        );
      }

      // 2) Lecturas de dominio (Firestore exige reads antes de writes).
      final cubiertaRef =
          _db.collection(AppCollections.cubiertas).doc(cubiertaLimpia);
      final cubiertaSnap = await tx.get(cubiertaRef);
      if (!cubiertaSnap.exists) {
        throw StateError('Cubierta $cubiertaLimpia no existe');
      }
      final cubierta = Cubierta.fromMap(cubiertaLimpia, cubiertaSnap.data());

      if (cubierta.estado != EstadoCubierta.enDeposito) {
        throw StateError(
          'La cubierta ${cubierta.codigo} está ${cubierta.estado.codigo}, '
          'solo se puede instalar si está EN_DEPOSITO',
        );
      }

      // VALIDACIÓN ESTRICTA tipo_uso vs posición. La regla más importante
      // del módulo (Santiago: "es un error de tipeo seguramente").
      if (!posicion.aceptaTipoUso(cubierta.tipoUso)) {
        throw StateError(
          'La cubierta ${cubierta.codigo} es ${cubierta.tipoUso.codigo} y la '
          'posición ${posicion.etiqueta} requiere '
          '${posicion.tipoUsoRequerido.codigo}',
        );
      }

      // Snapshot del modelo al instalar — la grilla de la unidad muestra
      // marca/modelo en cada tile y el % de vida útil consumida sin
      // joinear contra CUBIERTAS_MODELOS en cada rebuild.
      final modeloSnap = await tx.get(_db
          .collection(AppCollections.cubiertasModelos)
          .doc(cubierta.modeloId));
      final modelo = modeloSnap.exists
          ? CubiertaModelo.fromMap(cubierta.modeloId, modeloSnap.data())
          : null;
      final kmEsperadosSnapshot = modelo?.kmEsperadosParaVida(cubierta.vidas);

      // Validar que la unidad existe y es del tipo esperado.
      final vehiculoRef =
          _db.collection(AppCollections.vehiculos).doc(unidadLimpia);
      final vehiculoSnap = await tx.get(vehiculoRef);
      if (!vehiculoSnap.exists) {
        throw StateError('Unidad $unidadLimpia no existe');
      }
      final vehiculoData = vehiculoSnap.data() ?? const <String, dynamic>{};
      final tipoVehiculo =
          (vehiculoData['TIPO'] ?? '').toString().toUpperCase();
      final esTractor = tipoVehiculo == AppTiposVehiculo.tractor;
      if (unidadTipo == TipoUnidadCubierta.tractor && !esTractor) {
        throw StateError(
          '$unidadLimpia tiene TIPO=$tipoVehiculo, no es TRACTOR',
        );
      }
      if (unidadTipo == TipoUnidadCubierta.enganche && esTractor) {
        throw StateError(
          '$unidadLimpia es TRACTOR — se esperaba un enganche',
        );
      }

      // Tomar km_actual SOLO si es tractor (los enganches no tienen
      // odómetro propio).
      final double? kmUnidadActual = esTractor
          ? (vehiculoData['KM_ACTUAL'] as num?)?.toDouble()
          : null;

      final colInst = _db.collection(AppCollections.cubiertasInstaladas);
      final ahora = Timestamp.now();
      final nuevaRef = colInst.doc(instalacionId);
      tx.set(nuevaRef, <String, dynamic>{
        'cubierta_id': cubiertaLimpia,
        'cubierta_codigo': cubierta.codigo,
        'unidad_id': unidadLimpia,
        'unidad_tipo': unidadTipo.codigo,
        'posicion': posicionLimpia,
        'vida_al_instalar': cubierta.vidas,
        'modelo_etiqueta': cubierta.modeloEtiqueta,
        if (kmEsperadosSnapshot != null)
          'km_vida_estimada_al_instalar': kmEsperadosSnapshot,
        'desde': ahora,
        'hasta': null,
        'km_unidad_al_instalar': kmUnidadActual,
        'km_unidad_al_retirar': null,
        'km_recorridos': null,
        'instalado_por_dni': supervisorLimpio,
        if (supervisorNombre != null && supervisorNombre.trim().isNotEmpty)
          'instalado_por_nombre': supervisorNombre.trim(),
        'retirado_por_dni': null,
        'retirado_por_nombre': null,
        if (motivo != null && motivo.trim().isNotEmpty)
          'motivo': motivo.trim(),
      });

      tx.update(cubiertaRef, {
        'estado': EstadoCubierta.instalada.codigo,
      });

      // Crear los locks de unicidad — su existencia bloquea cualquier
      // intento concurrente de instalar otra cubierta en la misma
      // posición o de instalar esta cubierta en otra posición.
      tx.set(posicionLockRef, <String, dynamic>{
        'instalacion_id': instalacionId,
        'cubierta_id': cubiertaLimpia,
        'cubierta_codigo': cubierta.codigo,
        'unidad_id': unidadLimpia,
        'posicion': posicionLimpia,
        'desde': ahora,
      });
      tx.set(cubiertaLockRef, <String, dynamic>{
        'instalacion_id': instalacionId,
        'unidad_id': unidadLimpia,
        'posicion': posicionLimpia,
        'desde': ahora,
      });
    });

    unawaited(AuditLog.registrar(
      accion: AuditAccion.instalarCubierta,
      entidad: AppCollections.cubiertas,
      entidadId: cubiertaLimpia,
      detalles: {
        'unidad_id': unidadLimpia,
        'posicion': posicionLimpia,
        'instalacion_id': instalacionId,
      },
    ));

    return instalacionId;
  }

  /// Retira una cubierta instalada. Calcula km recorridos para tractor;
  /// para enganche queda en `null` (Fase 2 lo calcula con cruce
  /// ASIGNACIONES_ENGANCHE).
  ///
  /// Si [destinoFinal] es `descartada`, la cubierta queda
  /// `EstadoCubierta.descartada` en vez de volver al depósito (atajo
  /// para "saqué la cubierta porque está rota, no la voy a recapar").
  Future<void> retirar({
    required String instalacionId,
    required String supervisorDni,
    String? supervisorNombre,
    String? motivo,
    EstadoCubierta destinoFinal = EstadoCubierta.enDeposito,
  }) async {
    final idLimpio = instalacionId.trim();
    final supervisorLimpio = supervisorDni.trim();
    if (idLimpio.isEmpty || supervisorLimpio.isEmpty) {
      throw ArgumentError('instalacionId y supervisorDni son obligatorios');
    }
    if (destinoFinal != EstadoCubierta.enDeposito &&
        destinoFinal != EstadoCubierta.descartada) {
      throw ArgumentError(
        'destinoFinal solo puede ser EN_DEPOSITO o DESCARTADA al retirar '
        '(no $destinoFinal)',
      );
    }

    await _db.runTransaction((tx) async {
      final instRef =
          _db.collection(AppCollections.cubiertasInstaladas).doc(idLimpio);
      final instSnap = await tx.get(instRef);
      if (!instSnap.exists) {
        throw StateError('Instalación $idLimpio no existe');
      }
      final inst = CubiertaInstalada.fromDoc(instSnap);
      if (!inst.esActiva) {
        throw StateError(
            'La instalación $idLimpio ya está cerrada (hasta != null)');
      }

      // Releer la cubierta para mantener km_acumulados consistente.
      final cubiertaRef =
          _db.collection(AppCollections.cubiertas).doc(inst.cubiertaId);
      final cubiertaSnap = await tx.get(cubiertaRef);
      if (!cubiertaSnap.exists) {
        throw StateError('Cubierta ${inst.cubiertaId} no existe');
      }
      final cubierta = Cubierta.fromMap(inst.cubiertaId, cubiertaSnap.data());

      // Para tractor: km_actual del tractor en este momento.
      double? kmActualTractor;
      double? kmRecorridos;
      if (inst.unidadTipo == TipoUnidadCubierta.tractor) {
        final vehSnap = await tx.get(_db
            .collection(AppCollections.vehiculos)
            .doc(inst.unidadId));
        kmActualTractor =
            (vehSnap.data()?['KM_ACTUAL'] as num?)?.toDouble();
        if (kmActualTractor != null && inst.kmUnidadAlInstalar != null) {
          final diff = kmActualTractor - inst.kmUnidadAlInstalar!;
          // Defensa: si por algún motivo el odómetro retrocedió (sync
          // Volvo erróneo, reset manual), no contamos km negativos.
          kmRecorridos = diff < 0 ? 0 : diff;
        }
      }
      // Para enganche: dejamos los km en null. Cuando arranque Fase 2 el
      // cálculo se hará en background sobre los docs cerrados.

      final ahora = Timestamp.now();
      tx.update(instRef, {
        'hasta': ahora,
        'km_unidad_al_retirar': kmActualTractor,
        'km_recorridos': kmRecorridos,
        'retirado_por_dni': supervisorLimpio,
        if (supervisorNombre != null && supervisorNombre.trim().isNotEmpty)
          'retirado_por_nombre': supervisorNombre.trim(),
        if (motivo != null && motivo.trim().isNotEmpty)
          'motivo_retiro': motivo.trim(),
      });

      tx.update(cubiertaRef, {
        'estado': destinoFinal.codigo,
        if (kmRecorridos != null && kmRecorridos > 0)
          'km_acumulados': cubierta.kmAcumulados + kmRecorridos,
      });

      // Liberar locks de unicidad — la posición vuelve a estar
      // disponible y la cubierta deja de figurar como activa. Si por
      // estado inconsistente el lock no existe, igual seguimos (delete
      // en doc inexistente es no-op para Firestore).
      tx.delete(_db
          .collection(AppCollections.cubiertasPosicionesActivas)
          .doc(_posicionLockId(inst.unidadId, inst.posicion)));
      tx.delete(_db
          .collection(AppCollections.cubiertasActivas)
          .doc(inst.cubiertaId));
    });

    unawaited(AuditLog.registrar(
      accion: destinoFinal == EstadoCubierta.descartada
          ? AuditAccion.descartarCubierta
          : AuditAccion.retirarCubierta,
      entidad: AppCollections.cubiertas,
      entidadId: idLimpio,
      detalles: {
        'instalacion_id': idLimpio,
        'destino_final': destinoFinal.codigo,
        if (motivo != null && motivo.trim().isNotEmpty) 'motivo': motivo.trim(),
      },
    ));
  }

  /// Marca la cubierta como DESCARTADA sin pasar por una instalación
  /// (ej. cubierta del depósito que se decide tirar antes de instalarla).
  /// Si la cubierta está INSTALADA, usar [retirar] con
  /// `destinoFinal = EstadoCubierta.descartada` en vez de este método.
  Future<void> descartar({
    required String cubiertaId,
    required String supervisorDni,
    String? motivo,
  }) async {
    final cubiertaLimpia = cubiertaId.trim();
    final supervisorLimpio = supervisorDni.trim();
    if (cubiertaLimpia.isEmpty || supervisorLimpio.isEmpty) {
      throw ArgumentError('cubiertaId y supervisorDni son obligatorios');
    }

    await _db.runTransaction((tx) async {
      final cubiertaRef =
          _db.collection(AppCollections.cubiertas).doc(cubiertaLimpia);
      final cubiertaSnap = await tx.get(cubiertaRef);
      if (!cubiertaSnap.exists) {
        throw StateError('Cubierta $cubiertaLimpia no existe');
      }
      final cubierta = Cubierta.fromMap(cubiertaLimpia, cubiertaSnap.data());
      if (cubierta.estado == EstadoCubierta.instalada) {
        throw StateError(
          'La cubierta ${cubierta.codigo} está INSTALADA — usá retirar() '
          'con destinoFinal=DESCARTADA',
        );
      }
      if (cubierta.estado == EstadoCubierta.descartada) {
        return; // no-op idempotente
      }
      tx.update(cubiertaRef, {
        'estado': EstadoCubierta.descartada.codigo,
      });
    });

    unawaited(AuditLog.registrar(
      accion: AuditAccion.descartarCubierta,
      entidad: AppCollections.cubiertas,
      entidadId: cubiertaLimpia,
      detalles: {
        'descartada_por': supervisorLimpio,
        if (motivo != null && motivo.trim().isNotEmpty) 'motivo': motivo.trim(),
      },
    ));
  }

  // ===========================================================================
  // CONTROL — registrar última lectura de presión / profundidad de banda
  // ===========================================================================

  /// Registra una lectura de control de la cubierta instalada (pisada
  /// sobre la doc activa de `CUBIERTAS_INSTALADAS`). Si la lectura
  /// histórica fuese necesaria a futuro, hay que crear una colección
  /// `CUBIERTAS_CONTROLES` aparte. Por ahora capturamos solo la última.
  Future<void> registrarLectura({
    required String instalacionId,
    int? presionPsi,
    double? profundidadBandaMm,
    required String supervisorDni,
    String? supervisorNombre,
  }) async {
    final id = instalacionId.trim();
    final supervisorLimpio = supervisorDni.trim();
    if (id.isEmpty || supervisorLimpio.isEmpty) {
      throw ArgumentError(
          'instalacionId y supervisorDni son obligatorios');
    }
    if (presionPsi == null && profundidadBandaMm == null) {
      throw ArgumentError(
          'Pasá al menos uno: presión o profundidad de banda');
    }
    await _db
        .collection(AppCollections.cubiertasInstaladas)
        .doc(id)
        .update({
      if (presionPsi != null) 'ultima_presion_psi': presionPsi,
      if (profundidadBandaMm != null)
        'ultima_profundidad_banda_mm': profundidadBandaMm,
      'ultima_lectura_en': FieldValue.serverTimestamp(),
      'ultima_lectura_por_dni': supervisorLimpio,
      if (supervisorNombre != null && supervisorNombre.trim().isNotEmpty)
        'ultima_lectura_por_nombre': supervisorNombre.trim(),
    });
  }

  // ===========================================================================
  // ROTAR
  // ===========================================================================

  /// Rota una cubierta de una posición a otra DENTRO DE LA MISMA UNIDAD.
  /// Atómico: si la posición destino está vacía, cierra el log de origen
  /// y crea uno nuevo en destino. Si está ocupada, hace swap (cruza
  /// ambas cubiertas) — útil para emparejar desgaste rotando duales.
  ///
  /// Validaciones:
  /// - Origen y destino son de la misma unidad.
  /// - Destino acepta `tipo_uso` de la cubierta de origen (y viceversa
  ///   en caso de swap).
  /// - Para tractor: km_unidad_al_instalar del nuevo log usa el
  ///   `KM_ACTUAL` actual; los km_recorridos del log que se cierra se
  ///   calculan igual que `retirar()`.
  /// - Para enganche: km_recorridos quedan `null` (Fase 2).
  ///
  /// Para mover a OTRA UNIDAD: usar `retirar` + `instalar` (la rotación
  /// inter-unidades es operativamente distinta — pasa por el depósito).
  Future<void> rotar({
    required String instalacionOrigenId,
    required String posicionDestinoCodigo,
    required String supervisorDni,
    String? supervisorNombre,
    String? motivo,
  }) async {
    final origenId = instalacionOrigenId.trim();
    final destinoCodigo = posicionDestinoCodigo.trim().toUpperCase();
    final supervisorLimpio = supervisorDni.trim();
    if (origenId.isEmpty ||
        destinoCodigo.isEmpty ||
        supervisorLimpio.isEmpty) {
      throw ArgumentError(
          'instalacionOrigenId, posicionDestino y supervisorDni son obligatorios');
    }
    final posicionDestino = posicionPorCodigo[destinoCodigo];
    if (posicionDestino == null) {
      throw ArgumentError('Posición destino desconocida: $destinoCodigo');
    }

    // Generamos los IDs de las nuevas instalaciones afuera de la tx
    // para mantenerlos estables si la tx se reintenta.
    final nuevoIdA = _db.collection(AppCollections.cubiertasInstaladas).doc().id;
    final nuevoIdB = _db.collection(AppCollections.cubiertasInstaladas).doc().id;

    await _db.runTransaction((tx) async {
      final colInst = _db.collection(AppCollections.cubiertasInstaladas);
      final origenRef = colInst.doc(origenId);
      final origenSnap = await tx.get(origenRef);
      if (!origenSnap.exists) {
        throw StateError('Instalación $origenId no existe');
      }
      final origen = CubiertaInstalada.fromDoc(origenSnap);
      if (!origen.esActiva) {
        throw StateError('La instalación de origen ya está cerrada');
      }
      final posicionOrigen = origen.posicionTipada;
      if (posicionOrigen == null) {
        throw StateError(
            'Posición origen desconocida: ${origen.posicion}');
      }
      if (posicionOrigen.codigo == posicionDestino.codigo) {
        throw StateError('Origen y destino son la misma posición');
      }
      if (posicionOrigen.tipoUnidad != posicionDestino.tipoUnidad) {
        throw StateError(
            'Origen y destino deben ser de la misma unidad (tractor vs enganche).');
      }

      // Lock destino: si existe, hay swap.
      final lockDestinoRef = _db
          .collection(AppCollections.cubiertasPosicionesActivas)
          .doc(_posicionLockId(origen.unidadId, posicionDestino.codigo));
      final lockDestinoSnap = await tx.get(lockDestinoRef);
      final lockOrigenRef = _db
          .collection(AppCollections.cubiertasPosicionesActivas)
          .doc(_posicionLockId(origen.unidadId, posicionOrigen.codigo));
      // No hace falta releer el lock de origen — sabemos que existe
      // porque hay una instalación activa.

      // Cubierta de origen (la que se está moviendo).
      final cubiertaARef =
          _db.collection(AppCollections.cubiertas).doc(origen.cubiertaId);
      final cubiertaASnap = await tx.get(cubiertaARef);
      if (!cubiertaASnap.exists) {
        throw StateError('Cubierta ${origen.cubiertaId} no existe');
      }
      final cubiertaA = Cubierta.fromMap(origen.cubiertaId, cubiertaASnap.data());

      // Validar que destino acepte la cubierta A.
      if (!posicionDestino.aceptaTipoUso(cubiertaA.tipoUso)) {
        throw StateError(
          'La cubierta ${cubiertaA.codigo} es ${cubiertaA.tipoUso.codigo} '
          'y la posición ${posicionDestino.etiqueta} requiere '
          '${posicionDestino.tipoUsoRequerido.codigo}',
        );
      }

      // Si destino tiene cubierta (swap), preparar B.
      CubiertaInstalada? destinoOriginal;
      Cubierta? cubiertaB;
      if (lockDestinoSnap.exists) {
        final destinoInstId =
            (lockDestinoSnap.data()?['instalacion_id'] ?? '').toString();
        if (destinoInstId.isEmpty) {
          throw StateError(
              'Lock de destino sin instalacion_id — estado inconsistente');
        }
        final destinoInstRef = colInst.doc(destinoInstId);
        final destinoInstSnap = await tx.get(destinoInstRef);
        if (!destinoInstSnap.exists) {
          throw StateError(
              'La instalación destino $destinoInstId no existe');
        }
        destinoOriginal = CubiertaInstalada.fromDoc(destinoInstSnap);
        final cubiertaBRef = _db
            .collection(AppCollections.cubiertas)
            .doc(destinoOriginal.cubiertaId);
        final cubiertaBSnap = await tx.get(cubiertaBRef);
        if (!cubiertaBSnap.exists) {
          throw StateError(
              'Cubierta destino ${destinoOriginal.cubiertaId} no existe');
        }
        cubiertaB = Cubierta.fromMap(destinoOriginal.cubiertaId, cubiertaBSnap.data());
        // Para swap, B tiene que poder instalarse en la posición de A.
        if (!posicionOrigen.aceptaTipoUso(cubiertaB.tipoUso)) {
          throw StateError(
            'No se puede intercambiar: la cubierta ${cubiertaB.codigo} '
            'es ${cubiertaB.tipoUso.codigo} y la posición '
            '${posicionOrigen.etiqueta} requiere '
            '${posicionOrigen.tipoUsoRequerido.codigo}',
          );
        }
      }

      // Snapshots de modelos para los nuevos logs (uno o dos).
      final modeloASnap = await tx.get(_db
          .collection(AppCollections.cubiertasModelos)
          .doc(cubiertaA.modeloId));
      final modeloA = modeloASnap.exists
          ? CubiertaModelo.fromMap(cubiertaA.modeloId, modeloASnap.data())
          : null;
      CubiertaModelo? modeloB;
      if (cubiertaB != null) {
        final modeloBSnap = await tx.get(_db
            .collection(AppCollections.cubiertasModelos)
            .doc(cubiertaB.modeloId));
        modeloB = modeloBSnap.exists
            ? CubiertaModelo.fromMap(cubiertaB.modeloId, modeloBSnap.data())
            : null;
      }

      // KM actual de la unidad para tractor (para cerrar y abrir logs).
      double? kmActualUnidad;
      if (origen.unidadTipo == TipoUnidadCubierta.tractor) {
        final vehSnap = await tx.get(
          _db.collection(AppCollections.vehiculos).doc(origen.unidadId),
        );
        kmActualUnidad =
            (vehSnap.data()?['KM_ACTUAL'] as num?)?.toDouble();
      }

      double? calcularKm(CubiertaInstalada inst) {
        if (inst.unidadTipo != TipoUnidadCubierta.tractor) return null;
        final km = kmActualUnidad;
        final base = inst.kmUnidadAlInstalar;
        if (km == null || base == null) return null;
        final diff = km - base;
        return diff < 0 ? 0 : diff;
      }

      final ahora = Timestamp.now();
      final motivoLimpio = motivo?.trim();
      final motivoEtiqueta =
          motivoLimpio == null || motivoLimpio.isEmpty ? 'rotación' : motivoLimpio;

      // 1) Cerrar log origen (A).
      final kmRecorridosA = calcularKm(origen);
      tx.update(origenRef, {
        'hasta': ahora,
        'km_unidad_al_retirar': kmActualUnidad,
        'km_recorridos': kmRecorridosA,
        'retirado_por_dni': supervisorLimpio,
        if (supervisorNombre != null && supervisorNombre.trim().isNotEmpty)
          'retirado_por_nombre': supervisorNombre.trim(),
        'motivo_retiro': motivoEtiqueta,
      });
      if (kmRecorridosA != null && kmRecorridosA > 0) {
        tx.update(cubiertaARef, {
          'km_acumulados': cubiertaA.kmAcumulados + kmRecorridosA,
        });
      }

      // 2) Si swap, cerrar log destino (B).
      if (destinoOriginal != null && cubiertaB != null) {
        final destinoInstRef = colInst.doc(destinoOriginal.id);
        final cubiertaBRef = _db
            .collection(AppCollections.cubiertas)
            .doc(cubiertaB.id);
        final kmRecorridosB = calcularKm(destinoOriginal);
        tx.update(destinoInstRef, {
          'hasta': ahora,
          'km_unidad_al_retirar': kmActualUnidad,
          'km_recorridos': kmRecorridosB,
          'retirado_por_dni': supervisorLimpio,
          if (supervisorNombre != null && supervisorNombre.trim().isNotEmpty)
            'retirado_por_nombre': supervisorNombre.trim(),
          'motivo_retiro': motivoEtiqueta,
        });
        if (kmRecorridosB != null && kmRecorridosB > 0) {
          tx.update(cubiertaBRef, {
            'km_acumulados': cubiertaB.kmAcumulados + kmRecorridosB,
          });
        }
      }

      // 3) Liberar lock origen y, si swap, lock destino.
      tx.delete(lockOrigenRef);
      if (destinoOriginal != null) tx.delete(lockDestinoRef);

      // 4) Crear log nuevo en destino con cubierta A.
      final kmEsperadosA = modeloA?.kmEsperadosParaVida(cubiertaA.vidas);
      final nuevoARef = colInst.doc(nuevoIdA);
      tx.set(nuevoARef, <String, dynamic>{
        'cubierta_id': cubiertaA.id,
        'cubierta_codigo': cubiertaA.codigo,
        'unidad_id': origen.unidadId,
        'unidad_tipo': origen.unidadTipo.codigo,
        'posicion': posicionDestino.codigo,
        'vida_al_instalar': cubiertaA.vidas,
        'modelo_etiqueta': cubiertaA.modeloEtiqueta,
        if (kmEsperadosA != null)
          'km_vida_estimada_al_instalar': kmEsperadosA,
        'desde': ahora,
        'hasta': null,
        'km_unidad_al_instalar': kmActualUnidad,
        'km_unidad_al_retirar': null,
        'km_recorridos': null,
        'instalado_por_dni': supervisorLimpio,
        if (supervisorNombre != null && supervisorNombre.trim().isNotEmpty)
          'instalado_por_nombre': supervisorNombre.trim(),
        'retirado_por_dni': null,
        'retirado_por_nombre': null,
        'motivo': motivoEtiqueta,
      });
      // Crear lock posición destino apuntando al nuevo log A.
      tx.set(lockDestinoRef, <String, dynamic>{
        'instalacion_id': nuevoIdA,
        'cubierta_id': cubiertaA.id,
        'cubierta_codigo': cubiertaA.codigo,
        'unidad_id': origen.unidadId,
        'posicion': posicionDestino.codigo,
        'desde': ahora,
      });
      // Lock cubierta A: ya existe (no se borró), pero apuntaba al log
      // anterior — actualizamos su contenido para reflejar la posición
      // nueva. `set` con merge no aplica acá porque las rules prohíben
      // update; lo borramos y recreamos.
      final lockCubiertaARef = _db
          .collection(AppCollections.cubiertasActivas)
          .doc(cubiertaA.id);
      tx.delete(lockCubiertaARef);
      tx.set(lockCubiertaARef, <String, dynamic>{
        'instalacion_id': nuevoIdA,
        'unidad_id': origen.unidadId,
        'posicion': posicionDestino.codigo,
        'desde': ahora,
      });

      // 5) Si swap, crear log nuevo en origen con cubierta B + lock.
      if (destinoOriginal != null && cubiertaB != null) {
        final kmEsperadosB = modeloB?.kmEsperadosParaVida(cubiertaB.vidas);
        final nuevoBRef = colInst.doc(nuevoIdB);
        tx.set(nuevoBRef, <String, dynamic>{
          'cubierta_id': cubiertaB.id,
          'cubierta_codigo': cubiertaB.codigo,
          'unidad_id': origen.unidadId,
          'unidad_tipo': origen.unidadTipo.codigo,
          'posicion': posicionOrigen.codigo,
          'vida_al_instalar': cubiertaB.vidas,
          'modelo_etiqueta': cubiertaB.modeloEtiqueta,
          if (kmEsperadosB != null)
            'km_vida_estimada_al_instalar': kmEsperadosB,
          'desde': ahora,
          'hasta': null,
          'km_unidad_al_instalar': kmActualUnidad,
          'km_unidad_al_retirar': null,
          'km_recorridos': null,
          'instalado_por_dni': supervisorLimpio,
          if (supervisorNombre != null && supervisorNombre.trim().isNotEmpty)
            'instalado_por_nombre': supervisorNombre.trim(),
          'retirado_por_dni': null,
          'retirado_por_nombre': null,
          'motivo': motivoEtiqueta,
        });
        // Recrear lock posición origen apuntando al nuevo log B.
        tx.set(lockOrigenRef, <String, dynamic>{
          'instalacion_id': nuevoIdB,
          'cubierta_id': cubiertaB.id,
          'cubierta_codigo': cubiertaB.codigo,
          'unidad_id': origen.unidadId,
          'posicion': posicionOrigen.codigo,
          'desde': ahora,
        });
        // Lock cubierta B.
        final lockCubiertaBRef = _db
            .collection(AppCollections.cubiertasActivas)
            .doc(cubiertaB.id);
        tx.delete(lockCubiertaBRef);
        tx.set(lockCubiertaBRef, <String, dynamic>{
          'instalacion_id': nuevoIdB,
          'unidad_id': origen.unidadId,
          'posicion': posicionOrigen.codigo,
          'desde': ahora,
        });
      }
    });

    unawaited(AuditLog.registrar(
      accion: AuditAccion.instalarCubierta,
      entidad: AppCollections.cubiertas,
      entidadId: origenId,
      detalles: {
        'tipo': 'rotacion',
        'instalacion_origen_id': origenId,
        'posicion_destino': destinoCodigo,
        'instalacion_a_id': nuevoIdA,
        'instalacion_b_id': nuevoIdB,
      },
    ));
  }

  // ===========================================================================
  // RECAPADOS
  // ===========================================================================

  /// Manda una cubierta al proveedor de recapado. La cubierta debe estar
  /// EN_DEPOSITO y su modelo debe ser `recapable`.
  Future<String> mandarARecapar({
    required String cubiertaId,
    required String proveedor,
    required String supervisorDni,
    DateTime? fechaEnvio,
    String? supervisorNombre,
    String? notas,
  }) async {
    final cubiertaLimpia = cubiertaId.trim();
    final proveedorLimpio = proveedor.trim();
    final supervisorLimpio = supervisorDni.trim();
    if (cubiertaLimpia.isEmpty ||
        proveedorLimpio.isEmpty ||
        supervisorLimpio.isEmpty) {
      throw ArgumentError(
          'cubiertaId, proveedor y supervisorDni son obligatorios');
    }

    final recapadoId =
        _db.collection(AppCollections.cubiertasRecapados).doc().id;
    final fechaEnvioFinal = fechaEnvio ?? DateTime.now();

    await _db.runTransaction((tx) async {
      final cubiertaRef =
          _db.collection(AppCollections.cubiertas).doc(cubiertaLimpia);
      final cubiertaSnap = await tx.get(cubiertaRef);
      if (!cubiertaSnap.exists) {
        throw StateError('Cubierta $cubiertaLimpia no existe');
      }
      final cubierta = Cubierta.fromMap(cubiertaLimpia, cubiertaSnap.data());
      if (cubierta.estado != EstadoCubierta.enDeposito) {
        throw StateError(
          'Solo se puede mandar a recapar una cubierta EN_DEPOSITO '
          '(${cubierta.codigo} está ${cubierta.estado.codigo})',
        );
      }

      // Validar que el modelo sea recapable.
      final modeloSnap = await tx.get(_db
          .collection(AppCollections.cubiertasModelos)
          .doc(cubierta.modeloId));
      if (!modeloSnap.exists) {
        throw StateError(
            'El modelo ${cubierta.modeloId} de la cubierta no existe');
      }
      final modelo =
          CubiertaModelo.fromMap(cubierta.modeloId, modeloSnap.data());
      if (!modelo.recapable) {
        throw StateError(
          'El modelo ${modelo.etiqueta} no es recapable',
        );
      }

      final recapadoRef = _db
          .collection(AppCollections.cubiertasRecapados)
          .doc(recapadoId);
      tx.set(recapadoRef, <String, dynamic>{
        'cubierta_id': cubiertaLimpia,
        'cubierta_codigo': cubierta.codigo,
        // vida que TENDRÁ si vuelve recibida (vida actual + 1).
        'vida_recapado': cubierta.vidas + 1,
        'proveedor': proveedorLimpio,
        'fecha_envio': Timestamp.fromDate(fechaEnvioFinal),
        'fecha_retorno': null,
        'costo': null,
        'resultado': null,
        if (notas != null && notas.trim().isNotEmpty) 'notas': notas.trim(),
        'enviado_por_dni': supervisorLimpio,
        if (supervisorNombre != null && supervisorNombre.trim().isNotEmpty)
          'enviado_por_nombre': supervisorNombre.trim(),
        'cerrado_por_dni': null,
        'cerrado_por_nombre': null,
      });

      tx.update(cubiertaRef, {
        'estado': EstadoCubierta.enRecapado.codigo,
      });
    });

    unawaited(AuditLog.registrar(
      accion: AuditAccion.enviarCubiertaARecapar,
      entidad: AppCollections.cubiertas,
      entidadId: cubiertaLimpia,
      detalles: {
        'recapado_id': recapadoId,
        'proveedor': proveedorLimpio,
      },
    ));

    return recapadoId;
  }

  /// Cierra un evento de recapado al recibir la cubierta del proveedor.
  ///
  /// Si [resultado] es `RECIBIDA`: cubierta vuelve EN_DEPOSITO, vidas++.
  /// Si [resultado] es `DESCARTADA_POR_PROVEEDOR`: cubierta queda
  /// DESCARTADA (estructura dañada, etc).
  Future<void> recibirDeRecapado({
    required String recapadoId,
    required ResultadoRecapado resultado,
    required String supervisorDni,
    DateTime? fechaRetorno,
    double? costo,
    String? notas,
    String? supervisorNombre,
  }) async {
    final idLimpio = recapadoId.trim();
    final supervisorLimpio = supervisorDni.trim();
    if (idLimpio.isEmpty || supervisorLimpio.isEmpty) {
      throw ArgumentError('recapadoId y supervisorDni son obligatorios');
    }

    final fechaFinal = fechaRetorno ?? DateTime.now();

    await _db.runTransaction((tx) async {
      final recapadoRef =
          _db.collection(AppCollections.cubiertasRecapados).doc(idLimpio);
      final recapadoSnap = await tx.get(recapadoRef);
      if (!recapadoSnap.exists) {
        throw StateError('Recapado $idLimpio no existe');
      }
      final recapado = CubiertaRecapado.fromDoc(recapadoSnap);
      if (!recapado.enProceso) {
        throw StateError(
            'El recapado $idLimpio ya está cerrado (fecha_retorno != null)');
      }

      final cubiertaRef =
          _db.collection(AppCollections.cubiertas).doc(recapado.cubiertaId);
      final cubiertaSnap = await tx.get(cubiertaRef);
      if (!cubiertaSnap.exists) {
        throw StateError('Cubierta ${recapado.cubiertaId} no existe');
      }
      final cubierta =
          Cubierta.fromMap(recapado.cubiertaId, cubiertaSnap.data());

      tx.update(recapadoRef, {
        'fecha_retorno': Timestamp.fromDate(fechaFinal),
        'resultado': resultado.codigo,
        if (costo != null) 'costo': costo,
        if (notas != null && notas.trim().isNotEmpty) 'notas': notas.trim(),
        'cerrado_por_dni': supervisorLimpio,
        if (supervisorNombre != null && supervisorNombre.trim().isNotEmpty)
          'cerrado_por_nombre': supervisorNombre.trim(),
      });

      switch (resultado) {
        case ResultadoRecapado.recibida:
          tx.update(cubiertaRef, {
            'estado': EstadoCubierta.enDeposito.codigo,
            'vidas': cubierta.vidas + 1,
          });
        case ResultadoRecapado.descartadaPorProveedor:
          tx.update(cubiertaRef, {
            'estado': EstadoCubierta.descartada.codigo,
          });
      }
    });

    unawaited(AuditLog.registrar(
      accion: AuditAccion.recibirCubiertaDeRecapado,
      entidad: AppCollections.cubiertas,
      entidadId: idLimpio,
      detalles: {
        'recapado_id': idLimpio,
        'resultado': resultado.codigo,
        if (costo != null) 'costo': costo,
      },
    ));
  }

  // ===========================================================================
  // QUERIES / STREAMS
  // ===========================================================================

  /// Stream de TODAS las cubiertas activas instaladas en una unidad.
  /// Hasta 14 docs (10 tractor + 12 enganche es el cap teórico).
  Stream<List<CubiertaInstalada>> streamInstalacionesActivasPorUnidad(
      String unidadId) {
    final unidadLimpia = unidadId.trim().toUpperCase();
    if (unidadLimpia.isEmpty) {
      return Stream.value(const <CubiertaInstalada>[]);
    }
    return _db
        .collection(AppCollections.cubiertasInstaladas)
        .where('unidad_id', isEqualTo: unidadLimpia)
        .where('hasta', isNull: true)
        .snapshots()
        .map((s) => s.docs.map(CubiertaInstalada.fromDoc).toList());
  }

  /// Stream del historial completo de instalaciones de una cubierta
  /// (más reciente primero). [limit] por default 30.
  Stream<List<CubiertaInstalada>> streamHistorialInstalacionesPorCubierta(
    String cubiertaId, {
    int limit = 30,
  }) {
    final cubiertaLimpia = cubiertaId.trim();
    if (cubiertaLimpia.isEmpty) {
      return Stream.value(const <CubiertaInstalada>[]);
    }
    return _db
        .collection(AppCollections.cubiertasInstaladas)
        .where('cubierta_id', isEqualTo: cubiertaLimpia)
        .orderBy('desde', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(CubiertaInstalada.fromDoc).toList());
  }

  /// Stream de cubiertas en depósito. Si [tipoUso] se pasa, filtra por
  /// dirección o tracción (útil para "qué tengo en stock para reemplazar
  /// una de dirección").
  Stream<List<Cubierta>> streamCubiertasEnDeposito({
    TipoUsoCubierta? tipoUso,
  }) {
    Query<Map<String, dynamic>> q = _db
        .collection(AppCollections.cubiertas)
        .where('estado', isEqualTo: EstadoCubierta.enDeposito.codigo);
    if (tipoUso != null) {
      q = q.where('tipo_uso', isEqualTo: tipoUso.codigo);
    }
    return q.snapshots().map((s) => s.docs.map(Cubierta.fromDoc).toList());
  }

  /// Stream de TODAS las cubiertas con filtros opcionales — usado por la
  /// pantalla de Stock con filtro por estado ("¿qué cubiertas instaladas
  /// tengo?", "¿cuáles descarté?") y por la búsqueda global por código.
  ///
  /// Si [estado] es `null`, devuelve todas. Si [tipoUso] es `null`,
  /// devuelve todas las del estado dado. La pantalla complementa con
  /// filtro client-side por código (CUB-XXXX) — el universo de cubiertas
  /// es chico (<200 hoy, <1000 a futuro) y eso evita índices de texto.
  Stream<List<Cubierta>> streamCubiertasFiltradas({
    EstadoCubierta? estado,
    TipoUsoCubierta? tipoUso,
  }) {
    Query<Map<String, dynamic>> q = _db.collection(AppCollections.cubiertas);
    if (estado != null) {
      q = q.where('estado', isEqualTo: estado.codigo);
    }
    if (tipoUso != null) {
      q = q.where('tipo_uso', isEqualTo: tipoUso.codigo);
    }
    return q.snapshots().map((s) => s.docs.map(Cubierta.fromDoc).toList());
  }

  /// Stream de UNA cubierta puntual (detalle).
  Stream<Cubierta?> streamCubierta(String cubiertaId) {
    final id = cubiertaId.trim();
    if (id.isEmpty) return Stream.value(null);
    return _db
        .collection(AppCollections.cubiertas)
        .doc(id)
        .snapshots()
        .map((s) => s.exists ? Cubierta.fromDoc(s) : null);
  }

  /// Stream del historial de recapados de una cubierta (más reciente
  /// primero). Trae cerrados y en proceso.
  Stream<List<CubiertaRecapado>> streamHistorialRecapadosPorCubierta(
    String cubiertaId, {
    int limit = 30,
  }) {
    final id = cubiertaId.trim();
    if (id.isEmpty) return Stream.value(const <CubiertaRecapado>[]);
    return _db
        .collection(AppCollections.cubiertasRecapados)
        .where('cubierta_id', isEqualTo: id)
        .orderBy('fecha_envio', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(CubiertaRecapado.fromDoc).toList());
  }

  /// Stream de los recapados en proceso (fecha_retorno == null), más
  /// recientes primero.
  Stream<List<CubiertaRecapado>> streamRecapadosEnProceso() {
    return _db
        .collection(AppCollections.cubiertasRecapados)
        .where('fecha_retorno', isNull: true)
        .orderBy('fecha_envio', descending: true)
        .snapshots()
        .map((s) => s.docs.map(CubiertaRecapado.fromDoc).toList());
  }

  /// Stream de recapados ya cerrados (fecha_retorno != null), más
  /// recientes primero. Uso: tab "histórico" en pantalla de recapados.
  /// Limitamos a [limit] últimos para no descargar histórico completo.
  Stream<List<CubiertaRecapado>> streamRecapadosCerrados({int limit = 100}) {
    return _db
        .collection(AppCollections.cubiertasRecapados)
        .orderBy('fecha_retorno', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs
            .map(CubiertaRecapado.fromDoc)
            // El orderBy no filtra los nulls — los excluimos client-side
            // para no necesitar otro índice. La cantidad de "en proceso"
            // es chica (<10 típicamente).
            .where((r) => r.fechaRetorno != null)
            .toList());
  }
}

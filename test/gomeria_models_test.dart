import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logistica_app_profesional/features/gomeria/constants/posiciones.dart';
import 'package:logistica_app_profesional/features/gomeria/models/cubierta.dart';
import 'package:logistica_app_profesional/features/gomeria/models/cubierta_instalada.dart';
import 'package:logistica_app_profesional/features/gomeria/models/cubierta_marca.dart';
import 'package:logistica_app_profesional/features/gomeria/models/cubierta_modelo.dart';
import 'package:logistica_app_profesional/features/gomeria/models/cubierta_recapado.dart';

/// Tests del módulo Gomería — modelos data + constantes de posiciones.
///
/// Foco crítico: la validación tipo_uso vs posición (decisión confirmada
/// por Santiago: "que no le permita, sería un error de tipeo seguramente"),
/// el cálculo de km_esperados según vidas, y los parsers defensivos
/// (Firestore puede devolver datos parciales o corruptos sin que la app
/// crashee — patrón establecido en el resto del codebase).
void main() {
  // ===========================================================================
  // POSICIONES — layout fijo + validación estricta tipo_uso
  // ===========================================================================
  group('PosicionCubierta — layout fijo', () {
    test('tractor tiene exactamente 10 posiciones', () {
      expect(posicionesTractor.length, 10);
    });

    test('enganche tiene exactamente 12 posiciones (3 ejes × 4 ruedas)', () {
      expect(posicionesEnganche.length, 12);
    });

    test('todas las posiciones tienen códigos únicos', () {
      final codigos = [
        ...posicionesTractor.map((p) => p.codigo),
        ...posicionesEnganche.map((p) => p.codigo),
      ];
      expect(codigos.toSet().length, codigos.length,
          reason: 'no debe haber códigos duplicados entre tractor y enganche');
    });

    test('tractor: 2 posiciones DIRECCION, 8 TRACCION', () {
      final dir = posicionesTractor
          .where((p) => p.tipoUsoRequerido == TipoUsoCubierta.direccion)
          .length;
      final trac = posicionesTractor
          .where((p) => p.tipoUsoRequerido == TipoUsoCubierta.traccion)
          .length;
      expect(dir, 2);
      expect(trac, 8);
    });

    test('enganche: 0 posiciones DIRECCION, 12 TRACCION', () {
      final dir = posicionesEnganche
          .where((p) => p.tipoUsoRequerido == TipoUsoCubierta.direccion)
          .length;
      final trac = posicionesEnganche
          .where((p) => p.tipoUsoRequerido == TipoUsoCubierta.traccion)
          .length;
      expect(dir, 0);
      expect(trac, 12);
    });

    test('todas las posiciones de enganche son del mismo tipoUnidad', () {
      for (final p in posicionesEnganche) {
        expect(p.tipoUnidad, TipoUnidadCubierta.enganche);
      }
    });

    test('todas las posiciones de tractor son del mismo tipoUnidad', () {
      for (final p in posicionesTractor) {
        expect(p.tipoUnidad, TipoUnidadCubierta.tractor);
      }
    });

    test('posicionPorCodigo resuelve códigos válidos', () {
      expect(posicionPorCodigo['DIR_IZQ'], posTractorDirIzq);
      expect(posicionPorCodigo['TRAC1_DER_EXT'], posTractorTrac1DerExt);
      expect(posicionPorCodigo['ENG1_IZQ_EXT']?.tipoUnidad,
          TipoUnidadCubierta.enganche);
      expect(posicionPorCodigo['ENG3_DER_INT']?.eje, 3);
    });

    test('posicionPorCodigo devuelve null si no existe', () {
      expect(posicionPorCodigo['INEXISTENTE'], isNull);
      expect(posicionPorCodigo[''], isNull);
    });

    test('posicionesParaUnidad devuelve la lista correcta', () {
      expect(posicionesParaUnidad(TipoUnidadCubierta.tractor),
          posicionesTractor);
      expect(posicionesParaUnidad(TipoUnidadCubierta.enganche),
          posicionesEnganche);
    });
  });

  group('PosicionCubierta.aceptaTipoUso — validación ESTRICTA', () {
    test('cubierta DIRECCION en posición DIRECCION → OK', () {
      expect(posTractorDirIzq.aceptaTipoUso(TipoUsoCubierta.direccion), isTrue);
    });

    test('cubierta TRACCION en posición DIRECCION → RECHAZA', () {
      // Esta es LA regla crítica. Santiago: "es un error de tipeo seguramente,
      // es imposible que salga con una de tracción en la dirección".
      expect(posTractorDirIzq.aceptaTipoUso(TipoUsoCubierta.traccion), isFalse);
    });

    test('cubierta DIRECCION en posición TRACCION → RECHAZA', () {
      expect(posTractorTrac1IzqExt.aceptaTipoUso(TipoUsoCubierta.direccion),
          isFalse);
    });

    test('cubierta TRACCION en posición TRACCION → OK', () {
      expect(posTractorTrac1IzqExt.aceptaTipoUso(TipoUsoCubierta.traccion),
          isTrue);
      // Idem para enganche (todas son TRACCION).
      final pEng = posicionesEnganche.first;
      expect(pEng.aceptaTipoUso(TipoUsoCubierta.traccion), isTrue);
      expect(pEng.aceptaTipoUso(TipoUsoCubierta.direccion), isFalse);
    });
  });

  group('TipoUsoCubierta.fromCodigo', () {
    test('parsea códigos válidos', () {
      expect(TipoUsoCubierta.fromCodigo('DIRECCION'),
          TipoUsoCubierta.direccion);
      expect(TipoUsoCubierta.fromCodigo('TRACCION'),
          TipoUsoCubierta.traccion);
    });

    test('case-insensitive y trimmed', () {
      expect(TipoUsoCubierta.fromCodigo('  direccion  '),
          TipoUsoCubierta.direccion);
      expect(TipoUsoCubierta.fromCodigo('Traccion'),
          TipoUsoCubierta.traccion);
    });

    test('null o desconocido → null', () {
      expect(TipoUsoCubierta.fromCodigo(null), isNull);
      expect(TipoUsoCubierta.fromCodigo('OTRO'), isNull);
      expect(TipoUsoCubierta.fromCodigo(''), isNull);
    });
  });

  group('EstadoCubierta.fromCodigo', () {
    test('parsea los 4 estados', () {
      expect(EstadoCubierta.fromCodigo('EN_DEPOSITO'),
          EstadoCubierta.enDeposito);
      expect(EstadoCubierta.fromCodigo('INSTALADA'),
          EstadoCubierta.instalada);
      expect(EstadoCubierta.fromCodigo('EN_RECAPADO'),
          EstadoCubierta.enRecapado);
      expect(EstadoCubierta.fromCodigo('DESCARTADA'),
          EstadoCubierta.descartada);
    });

    test('null o desconocido → null (el modelo aplica default)', () {
      expect(EstadoCubierta.fromCodigo(null), isNull);
      expect(EstadoCubierta.fromCodigo('FOO'), isNull);
    });
  });

  group('ResultadoRecapado.fromCodigo', () {
    test('parsea los 2 resultados', () {
      expect(ResultadoRecapado.fromCodigo('RECIBIDA'),
          ResultadoRecapado.recibida);
      expect(ResultadoRecapado.fromCodigo('DESCARTADA_POR_PROVEEDOR'),
          ResultadoRecapado.descartadaPorProveedor);
    });

    test('null mientras está en proceso', () {
      expect(ResultadoRecapado.fromCodigo(null), isNull);
    });
  });

  // ===========================================================================
  // CUBIERTA_MARCA — modelo simple
  // ===========================================================================
  group('CubiertaMarca.fromMap', () {
    test('parsea correctamente', () {
      final m = CubiertaMarca.fromMap('marcaA', {
        'nombre': 'Bridgestone',
        'activo': true,
      });
      expect(m.id, 'marcaA');
      expect(m.nombre, 'Bridgestone');
      expect(m.activo, isTrue);
    });

    test('data null → defaults sin romper', () {
      final m = CubiertaMarca.fromMap('marcaB', null);
      expect(m.nombre, '');
      expect(m.activo, isTrue, reason: 'default activo=true');
    });

    test('campo activo no-bool → fallback a true', () {
      final m = CubiertaMarca.fromMap('x', {'nombre': 'X', 'activo': 'sí'});
      expect(m.activo, isTrue);
    });
  });

  // ===========================================================================
  // CUBIERTA_MODELO — km_esperados + recapable + etiqueta
  // ===========================================================================
  group('CubiertaModelo.kmEsperadosParaVida', () {
    const modelo = CubiertaModelo(
      id: 'mod1',
      marcaId: 'marca1',
      marcaNombre: 'Bridgestone',
      modelo: 'R268',
      medida: '295/80R22.5',
      tipoUso: TipoUsoCubierta.direccion,
      kmVidaEstimadaNueva: 120000,
      kmVidaEstimadaRecapada: 60000,
      recapable: true,
      activo: true,
    );

    test('vida 1 (nueva) → km_vida_estimada_nueva', () {
      expect(modelo.kmEsperadosParaVida(1), 120000);
    });

    test('vida 2+ (recapada) → km_vida_estimada_recapada', () {
      expect(modelo.kmEsperadosParaVida(2), 60000);
      expect(modelo.kmEsperadosParaVida(3), 60000);
    });

    test('vida 0 o negativa (corrupción) → trata como nueva', () {
      expect(modelo.kmEsperadosParaVida(0), 120000);
      expect(modelo.kmEsperadosParaVida(-1), 120000);
    });

    test('si km_recapada es null (no recapable) → null en vida 2+', () {
      const noRecapable = CubiertaModelo(
        id: 'mod2',
        marcaId: 'marca2',
        marcaNombre: 'GenericaChina',
        modelo: 'XYZ',
        medida: '11R22.5',
        tipoUso: TipoUsoCubierta.traccion,
        kmVidaEstimadaNueva: 50000,
        kmVidaEstimadaRecapada: null,
        recapable: false,
        activo: true,
      );
      expect(noRecapable.kmEsperadosParaVida(1), 50000);
      expect(noRecapable.kmEsperadosParaVida(2), isNull);
    });
  });

  group('CubiertaModelo.etiqueta', () {
    test('formato compacto para listados', () {
      const m = CubiertaModelo(
        id: 'mod1',
        marcaId: 'marca1',
        marcaNombre: 'Bridgestone',
        modelo: 'R268',
        medida: '295/80R22.5',
        tipoUso: TipoUsoCubierta.direccion,
        kmVidaEstimadaNueva: 120000,
        kmVidaEstimadaRecapada: 60000,
        recapable: true,
        activo: true,
      );
      expect(m.etiqueta, 'Bridgestone R268 295/80R22.5 — Dirección');
    });
  });

  group('CubiertaModelo.fromMap', () {
    test('parsea todos los campos', () {
      final m = CubiertaModelo.fromMap('mod1', {
        'marca_id': 'marca1',
        'marca_nombre': 'Bridgestone',
        'modelo': 'R268',
        'medida': '295/80R22.5',
        'tipo_uso': 'DIRECCION',
        'km_vida_estimada_nueva': 120000,
        'km_vida_estimada_recapada': 60000,
        'recapable': true,
        'activo': true,
      });
      expect(m.id, 'mod1');
      expect(m.tipoUso, TipoUsoCubierta.direccion);
      expect(m.kmVidaEstimadaNueva, 120000);
      expect(m.kmVidaEstimadaRecapada, 60000);
      expect(m.recapable, isTrue);
    });

    test('data null → defaults sin romper', () {
      final m = CubiertaModelo.fromMap('x', null);
      expect(m.marcaNombre, '');
      expect(m.tipoUso, TipoUsoCubierta.traccion,
          reason: 'fallback más conservador (mayoría de posiciones son traccion)');
      expect(m.recapable, isFalse);
      expect(m.activo, isTrue);
      expect(m.kmVidaEstimadaNueva, isNull);
    });

    test('km_vida_estimada como double → toInt()', () {
      final m = CubiertaModelo.fromMap('x', {
        'km_vida_estimada_nueva': 120000.5,
      });
      expect(m.kmVidaEstimadaNueva, 120000);
    });
  });

  group('CubiertaModelo.toMap → fromMap roundtrip', () {
    test('preserva todos los campos relevantes', () {
      const original = CubiertaModelo(
        id: 'mod1',
        marcaId: 'marca1',
        marcaNombre: 'Pirelli',
        modelo: 'FR01',
        medida: '11R22.5',
        tipoUso: TipoUsoCubierta.traccion,
        kmVidaEstimadaNueva: 100000,
        kmVidaEstimadaRecapada: 45000,
        recapable: true,
        activo: false,
      );
      final reparsed = CubiertaModelo.fromMap(original.id, original.toMap());
      expect(reparsed.marcaId, original.marcaId);
      expect(reparsed.marcaNombre, original.marcaNombre);
      expect(reparsed.modelo, original.modelo);
      expect(reparsed.medida, original.medida);
      expect(reparsed.tipoUso, original.tipoUso);
      expect(reparsed.kmVidaEstimadaNueva, original.kmVidaEstimadaNueva);
      expect(reparsed.kmVidaEstimadaRecapada, original.kmVidaEstimadaRecapada);
      expect(reparsed.recapable, original.recapable);
      expect(reparsed.activo, original.activo);
    });
  });

  // ===========================================================================
  // CUBIERTA — estado + puedeRecaparse + parsing defensivo
  // ===========================================================================
  group('Cubierta.puedeRecaparse', () {
    Cubierta crear(EstadoCubierta estado) => Cubierta(
          id: 'c1',
          codigo: 'CUB-0001',
          modeloId: 'mod1',
          modeloEtiqueta: 'Bridgestone R268',
          tipoUso: TipoUsoCubierta.direccion,
          estado: estado,
          vidas: 1,
          kmAcumulados: 0,
          observaciones: null,
          creadoEn: null,
        );

    test('EN_DEPOSITO → puede', () {
      expect(crear(EstadoCubierta.enDeposito).puedeRecaparse, isTrue);
    });

    test('INSTALADA → puede (se podría retirar y mandar a recapar)', () {
      expect(crear(EstadoCubierta.instalada).puedeRecaparse, isTrue);
    });

    test('EN_RECAPADO → no puede (ya está allá)', () {
      expect(crear(EstadoCubierta.enRecapado).puedeRecaparse, isFalse);
    });

    test('DESCARTADA → no puede (fin de vida)', () {
      expect(crear(EstadoCubierta.descartada).puedeRecaparse, isFalse);
    });
  });

  group('Cubierta.fromMap', () {
    test('parsea todos los campos', () {
      final c = Cubierta.fromMap('c1', {
        'codigo': 'CUB-0042',
        'modelo_id': 'mod1',
        'modelo_etiqueta': 'Bridgestone R268 295/80R22.5 — Dirección',
        'tipo_uso': 'DIRECCION',
        'estado': 'INSTALADA',
        'vidas': 2,
        'km_acumulados': 87500.5,
        'observaciones': 'pinchazo en lateral',
        'creado_en': Timestamp.fromDate(DateTime(2026, 1, 15)),
      });
      expect(c.codigo, 'CUB-0042');
      expect(c.tipoUso, TipoUsoCubierta.direccion);
      expect(c.estado, EstadoCubierta.instalada);
      expect(c.vidas, 2);
      expect(c.kmAcumulados, 87500.5);
      expect(c.observaciones, 'pinchazo en lateral');
      expect(c.creadoEn, DateTime(2026, 1, 15));
    });

    test('data null → defaults sin romper', () {
      final c = Cubierta.fromMap('c1', null);
      expect(c.codigo, '');
      expect(c.estado, EstadoCubierta.enDeposito,
          reason: 'default razonable: una cubierta nueva está en depósito');
      expect(c.vidas, 1);
      expect(c.kmAcumulados, 0);
      expect(c.tipoUso, TipoUsoCubierta.traccion);
    });

    test('campos numéricos como int → toDouble graceful', () {
      final c = Cubierta.fromMap('c1', {
        'codigo': 'CUB-0001',
        'km_acumulados': 50000, // int, no double
      });
      expect(c.kmAcumulados, 50000.0);
    });

    test('estado desconocido → fallback a EN_DEPOSITO', () {
      final c = Cubierta.fromMap('c1', {'estado': 'BASURA'});
      expect(c.estado, EstadoCubierta.enDeposito);
    });
  });

  // ===========================================================================
  // CUBIERTA_INSTALADA — esActiva + posicionTipada + duración
  // ===========================================================================
  group('CubiertaInstalada.esActiva', () {
    test('hasta == null → activa', () {
      final i = CubiertaInstalada(
        id: 'i1',
        cubiertaId: 'c1',
        cubiertaCodigo: 'CUB-0001',
        unidadId: 'TR123',
        unidadTipo: TipoUnidadCubierta.tractor,
        posicion: 'DIR_IZQ',
        vidaAlInstalar: 1,
        desde: DateTime(2026, 1, 1),
        hasta: null,
        kmUnidadAlInstalar: 100000,
        kmUnidadAlRetirar: null,
        kmRecorridos: null,
        instaladoPorDni: '111',
        instaladoPorNombre: 'Sup',
        retiradoPorDni: null,
        retiradoPorNombre: null,
        motivo: null,
      );
      expect(i.esActiva, isTrue);
    });

    test('hasta != null → cerrada', () {
      final i = CubiertaInstalada(
        id: 'i1',
        cubiertaId: 'c1',
        cubiertaCodigo: 'CUB-0001',
        unidadId: 'TR123',
        unidadTipo: TipoUnidadCubierta.tractor,
        posicion: 'DIR_IZQ',
        vidaAlInstalar: 1,
        desde: DateTime(2026, 1, 1),
        hasta: DateTime(2026, 4, 1),
        kmUnidadAlInstalar: 100000,
        kmUnidadAlRetirar: 150000,
        kmRecorridos: 50000,
        instaladoPorDni: '111',
        instaladoPorNombre: 'Sup',
        retiradoPorDni: '111',
        retiradoPorNombre: 'Sup',
        motivo: 'rotación',
      );
      expect(i.esActiva, isFalse);
    });
  });

  group('CubiertaInstalada.posicionTipada', () {
    test('posición tractor válida → resuelve correctamente', () {
      final i = CubiertaInstalada.fromMap('i1', {
        'cubierta_id': 'c1',
        'unidad_id': 'TR123',
        'unidad_tipo': 'TRACTOR',
        'posicion': 'DIR_IZQ',
        'desde': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      expect(i.posicionTipada, posTractorDirIzq);
      expect(
          i.posicionTipada?.tipoUsoRequerido, TipoUsoCubierta.direccion);
    });

    test('posición enganche válida → resuelve correctamente', () {
      final i = CubiertaInstalada.fromMap('i1', {
        'cubierta_id': 'c1',
        'unidad_id': 'BAT456',
        'unidad_tipo': 'ENGANCHE',
        'posicion': 'ENG2_DER_INT',
        'desde': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      expect(i.posicionTipada?.codigo, 'ENG2_DER_INT');
      expect(i.posicionTipada?.tipoUnidad, TipoUnidadCubierta.enganche);
      expect(i.posicionTipada?.eje, 2);
    });

    test('posición desconocida → null (no crashea)', () {
      final i = CubiertaInstalada.fromMap('i1', {
        'cubierta_id': 'c1',
        'unidad_id': 'TR123',
        'unidad_tipo': 'TRACTOR',
        'posicion': 'INEXISTENTE',
        'desde': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      expect(i.posicionTipada, isNull);
    });
  });

  group('CubiertaInstalada.diasDuracion', () {
    test('instalación cerrada usa hasta', () {
      final i = CubiertaInstalada(
        id: 'i1',
        cubiertaId: 'c1',
        cubiertaCodigo: 'CUB-0001',
        unidadId: 'TR123',
        unidadTipo: TipoUnidadCubierta.tractor,
        posicion: 'DIR_IZQ',
        vidaAlInstalar: 1,
        desde: DateTime(2026, 1, 1),
        hasta: DateTime(2026, 1, 31),
        kmUnidadAlInstalar: null,
        kmUnidadAlRetirar: null,
        kmRecorridos: null,
        instaladoPorDni: '111',
        instaladoPorNombre: null,
        retiradoPorDni: null,
        retiradoPorNombre: null,
        motivo: null,
      );
      expect(i.diasDuracion(), 30);
    });

    test('instalación activa cuenta hasta ahora', () {
      final hace10 = DateTime.now().subtract(const Duration(days: 10));
      final i = CubiertaInstalada(
        id: 'i1',
        cubiertaId: 'c1',
        cubiertaCodigo: 'CUB-0001',
        unidadId: 'TR123',
        unidadTipo: TipoUnidadCubierta.tractor,
        posicion: 'DIR_IZQ',
        vidaAlInstalar: 1,
        desde: hace10,
        hasta: null,
        kmUnidadAlInstalar: null,
        kmUnidadAlRetirar: null,
        kmRecorridos: null,
        instaladoPorDni: '111',
        instaladoPorNombre: null,
        retiradoPorDni: null,
        retiradoPorNombre: null,
        motivo: null,
      );
      expect(i.diasDuracion(), greaterThanOrEqualTo(9));
      expect(i.diasDuracion(), lessThanOrEqualTo(10));
    });
  });

  group('CubiertaInstalada.fromMap — defensas', () {
    test('data null → defaults sin romper', () {
      final i = CubiertaInstalada.fromMap('i1', null);
      expect(i.id, 'i1');
      expect(i.cubiertaId, '');
      expect(i.unidadTipo, TipoUnidadCubierta.tractor,
          reason: 'fallback default');
      expect(i.vidaAlInstalar, 1);
      expect(i.kmUnidadAlInstalar, isNull);
      expect(i.hasta, isNull);
    });

    test('unidad_tipo "ENGANCHE" → enum correcto', () {
      final i = CubiertaInstalada.fromMap('i1', {
        'unidad_tipo': 'ENGANCHE',
      });
      expect(i.unidadTipo, TipoUnidadCubierta.enganche);
    });

    test('unidad_tipo cualquier-otra-cosa → fallback a tractor', () {
      final i = CubiertaInstalada.fromMap('i1', {
        'unidad_tipo': 'FOO',
      });
      expect(i.unidadTipo, TipoUnidadCubierta.tractor);
    });
  });

  // ===========================================================================
  // CUBIERTA_RECAPADO — enProceso + diasEnRecapado + parsing
  // ===========================================================================
  group('CubiertaRecapado.enProceso', () {
    test('fechaRetorno == null → en proceso', () {
      final r = CubiertaRecapado(
        id: 'r1',
        cubiertaId: 'c1',
        cubiertaCodigo: 'CUB-0001',
        vidaRecapado: 2,
        proveedor: 'Recauchutados Sur',
        fechaEnvio: DateTime(2026, 4, 1),
        fechaRetorno: null,
        costo: null,
        resultado: null,
        notas: null,
        enviadoPorDni: '111',
        enviadoPorNombre: 'Sup',
        cerradoPorDni: null,
        cerradoPorNombre: null,
      );
      expect(r.enProceso, isTrue);
    });

    test('fechaRetorno != null → cerrado', () {
      final r = CubiertaRecapado(
        id: 'r1',
        cubiertaId: 'c1',
        cubiertaCodigo: 'CUB-0001',
        vidaRecapado: 2,
        proveedor: 'Recauchutados Sur',
        fechaEnvio: DateTime(2026, 4, 1),
        fechaRetorno: DateTime(2026, 4, 20),
        costo: 45000,
        resultado: ResultadoRecapado.recibida,
        notas: 'OK',
        enviadoPorDni: '111',
        enviadoPorNombre: 'Sup',
        cerradoPorDni: '111',
        cerradoPorNombre: 'Sup',
      );
      expect(r.enProceso, isFalse);
    });
  });

  group('CubiertaRecapado.diasEnRecapado', () {
    test('cerrado usa fechaRetorno', () {
      final r = CubiertaRecapado(
        id: 'r1',
        cubiertaId: 'c1',
        cubiertaCodigo: 'CUB-0001',
        vidaRecapado: 2,
        proveedor: 'X',
        fechaEnvio: DateTime(2026, 4, 1),
        fechaRetorno: DateTime(2026, 4, 21),
        costo: null,
        resultado: ResultadoRecapado.recibida,
        notas: null,
        enviadoPorDni: '111',
        enviadoPorNombre: null,
        cerradoPorDni: '111',
        cerradoPorNombre: null,
      );
      expect(r.diasEnRecapado(), 20);
    });

    test('en proceso cuenta hasta ahora', () {
      final hace15 = DateTime.now().subtract(const Duration(days: 15));
      final r = CubiertaRecapado(
        id: 'r1',
        cubiertaId: 'c1',
        cubiertaCodigo: 'CUB-0001',
        vidaRecapado: 2,
        proveedor: 'X',
        fechaEnvio: hace15,
        fechaRetorno: null,
        costo: null,
        resultado: null,
        notas: null,
        enviadoPorDni: '111',
        enviadoPorNombre: null,
        cerradoPorDni: null,
        cerradoPorNombre: null,
      );
      expect(r.diasEnRecapado(), greaterThanOrEqualTo(14));
      expect(r.diasEnRecapado(), lessThanOrEqualTo(15));
    });
  });

  group('CubiertaRecapado.fromMap', () {
    test('parsea todos los campos cerrado', () {
      final r = CubiertaRecapado.fromMap('r1', {
        'cubierta_id': 'c1',
        'cubierta_codigo': 'CUB-0042',
        'vida_recapado': 2,
        'proveedor': 'Recauchutados Sur',
        'fecha_envio': Timestamp.fromDate(DateTime(2026, 4, 1)),
        'fecha_retorno': Timestamp.fromDate(DateTime(2026, 4, 20)),
        'costo': 45000.5,
        'resultado': 'RECIBIDA',
        'notas': 'banda nueva OK',
        'enviado_por_dni': '111',
        'enviado_por_nombre': 'Santiago',
        'cerrado_por_dni': '111',
        'cerrado_por_nombre': 'Santiago',
      });
      expect(r.cubiertaCodigo, 'CUB-0042');
      expect(r.vidaRecapado, 2);
      expect(r.proveedor, 'Recauchutados Sur');
      expect(r.fechaRetorno, DateTime(2026, 4, 20));
      expect(r.costo, 45000.5);
      expect(r.resultado, ResultadoRecapado.recibida);
      expect(r.enProceso, isFalse);
    });

    test('data null → defaults sin romper', () {
      final r = CubiertaRecapado.fromMap('r1', null);
      expect(r.cubiertaId, '');
      expect(r.proveedor, '');
      expect(r.vidaRecapado, 2);
      expect(r.fechaRetorno, isNull);
      expect(r.resultado, isNull);
      expect(r.enProceso, isTrue);
    });

    test('costo como int → toDouble', () {
      final r = CubiertaRecapado.fromMap('r1', {
        'cubierta_id': 'c1',
        'fecha_envio': Timestamp.fromDate(DateTime(2026, 4, 1)),
        'costo': 45000, // int, no double
      });
      expect(r.costo, 45000.0);
    });
  });
}

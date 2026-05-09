# Carga masiva de "cubiertas legacy" — una por cada posición de cada
# unidad de la flota. Usado UNA VEZ al inicio para que el módulo Gomería
# refleje que las unidades ya tienen cubiertas montadas físicamente,
# aunque no haya datos del histórico previo.
#
# Decisión operativa (Santiago, 2026-05-08): no hay info de las cubiertas
# que ya están instaladas. Las cargamos como placeholders genéricos
# (modelo "SIN IDENTIFICAR — Dirección/Tracción", vidas=1, km_acumulados=0)
# y, a medida que se reemplacen, las nuevas cubiertas se cargan con datos
# reales y desde ese punto se cuentan los km verdaderos.
#
# Para distinguir las cohort 1 (legacy) de la cohort 2 (cargas reales),
# todos los docs creados por este script llevan `legacy_inicial: true`.
# Reportes futuros pueden filtrar por ese flag.
#
# Idempotente: si una posición ya tiene una cubierta activa (lock en
# CUBIERTAS_POSICIONES_ACTIVAS) la salta. Re-correr el script no
# duplica nada.
#
# Uso (desde la raíz del repo):
#   python scripts/importar_cubiertas_legacy.py --dry-run     # solo lista
#   python scripts/importar_cubiertas_legacy.py --apply       # crea
#   python scripts/importar_cubiertas_legacy.py --apply --operador-dni <DNI>
#
# Clasificación tractor vs enganche: prioridad VEHICULOS.TIPO si está
# poblado; sino fallback a la regla de Santiago — "MARCA contiene VOLVO
# → tractor, sino → enganche". Si los dos criterios discrepan, imprime
# warning para revisar manualmente.
#
# Costo aprox: 4 sets por posición × ~1100 posiciones = ~4400 writes.
# Firestore Spark plan free tier diario: 20.000 writes/día — sobra.

import argparse
import sys
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore

# === Constantes (deben coincidir con lib/features/gomeria/constants/posiciones.dart) ===

POSICIONES_TRACTOR = [
    'DIR_IZQ', 'DIR_DER',
    'TRAC1_IZQ_EXT', 'TRAC1_IZQ_INT', 'TRAC1_DER_INT', 'TRAC1_DER_EXT',
    'TRAC2_IZQ_EXT', 'TRAC2_IZQ_INT', 'TRAC2_DER_INT', 'TRAC2_DER_EXT',
]

POSICIONES_ENGANCHE = [
    f'ENG{eje}_{lado}'
    for eje in (1, 2, 3)
    for lado in ('IZQ_EXT', 'IZQ_INT', 'DER_INT', 'DER_EXT')
]

# Solo las 2 posiciones de dirección (eje 1 del tractor) son DIRECCION.
# Todas las demás (tracción del tractor + 12 del enganche) son TRACCION.
POSICIONES_DIRECCION = {'DIR_IZQ', 'DIR_DER'}

MARCA_LEGACY_ID = 'sin-identificar'
MODELO_LEGACY_DIRECCION_ID = 'sin-identificar-direccion'
MODELO_LEGACY_TRACCION_ID = 'sin-identificar-traccion'


def conectar():
    repo_root = Path(__file__).resolve().parent.parent
    sa_path = repo_root / 'serviceAccountKey.json'
    if not sa_path.exists():
        print(f'❌ No encuentro {sa_path}')
        print('   Bajá el service account de Firebase Console → Settings → Service accounts.')
        sys.exit(1)
    cred = credentials.Certificate(str(sa_path))
    firebase_admin.initialize_app(cred)
    return firestore.client()


def crear_catalogo_legacy(db, dry_run):
    """Crea marca + 2 modelos legacy si no existen. Idempotente.
    Devuelve lista de strings de lo que creó (vacía si todo existía)."""
    creados = []

    marca_ref = db.collection('CUBIERTAS_MARCAS').document(MARCA_LEGACY_ID)
    if not marca_ref.get().exists:
        if not dry_run:
            marca_ref.set({
                'nombre': 'SIN IDENTIFICAR',
                'activo': True,
                'creado_en': firestore.SERVER_TIMESTAMP,
                'creado_por_dni': 'SCRIPT_LEGACY',
                'legacy_inicial': True,
            })
        creados.append(f'CUBIERTAS_MARCAS/{MARCA_LEGACY_ID}')

    for (id_, tipo_uso, etiqueta) in (
        (MODELO_LEGACY_DIRECCION_ID, 'DIRECCION', 'SIN IDENTIFICAR — Dirección'),
        (MODELO_LEGACY_TRACCION_ID, 'TRACCION', 'SIN IDENTIFICAR — Tracción'),
    ):
        modelo_ref = db.collection('CUBIERTAS_MODELOS').document(id_)
        if not modelo_ref.get().exists:
            if not dry_run:
                modelo_ref.set({
                    'marca_id': MARCA_LEGACY_ID,
                    'marca_nombre': 'SIN IDENTIFICAR',
                    'modelo': 'GENÉRICA',
                    'medida': '—',
                    'tipo_uso': tipo_uso,
                    'etiqueta': etiqueta,
                    'recapable': True,
                    'activo': True,
                    # km_vida_estimada_nueva / _recapada / presion_recomendada_psi /
                    # profundidad_banda_minima_mm: NO se setean (null) — sin datos.
                    # Eso hace que el % vida útil consumida no se calcule en la UI
                    # para estas cubiertas, lo cual es honesto.
                    'creado_en': firestore.SERVER_TIMESTAMP,
                    'creado_por_dni': 'SCRIPT_LEGACY',
                    'legacy_inicial': True,
                })
            creados.append(f'CUBIERTAS_MODELOS/{id_}')

    return creados


def reservar_codigo_cubierta(db):
    """Reserva el próximo código CUB-XXXX incrementando el counter
    transaccional. Devuelve string tipo 'CUB-0042'."""
    counter_ref = db.collection('META').document('cubiertas_counter')

    @firestore.transactional
    def _reservar(tx):
        snap = counter_ref.get(transaction=tx)
        actual = snap.to_dict().get('proximo', 0) if snap.exists else 0
        siguiente = actual + 1
        if snap.exists:
            tx.update(counter_ref, {'proximo': siguiente})
        else:
            tx.set(counter_ref, {'proximo': siguiente})
        return siguiente

    n = _reservar(db.transaction())
    return f'CUB-{n:04d}'


def clasificar_unidad(patente, data):
    """Devuelve ('TRACTOR'|'ENGANCHE', warning|None).

    Prioridad:
    1. Si VEHICULOS.TIPO está poblado y vale 'TRACTOR' o uno de los
       enganches reconocidos, lo usamos (source of truth).
    2. Sino fallback: si MARCA contiene 'VOLVO', tractor; sino enganche.
    3. Si los dos criterios discrepan, devuelvo el de TIPO + warning."""
    tipo = (data.get('TIPO') or '').strip().upper()
    marca = (data.get('MARCA') or '').strip().upper()
    es_volvo = 'VOLVO' in marca

    if tipo == 'TRACTOR':
        clasificacion = 'TRACTOR'
        warning = None if es_volvo else (
            f'TIPO=TRACTOR pero MARCA="{marca or "?"}" no contiene VOLVO')
        return clasificacion, warning

    if tipo in ('BATEA', 'TOLVA', 'BIVUELCO', 'TANQUE', 'ACOPLADO'):
        clasificacion = 'ENGANCHE'
        warning = (
            f'TIPO={tipo} pero MARCA="{marca}" contiene VOLVO'
            if es_volvo else None)
        return clasificacion, warning

    # TIPO no poblado o desconocido: fallback a la regla de la marca.
    if not tipo:
        return ('TRACTOR' if es_volvo else 'ENGANCHE'), (
            f'TIPO vacío — clasificado por MARCA="{marca or "?"}"')

    # TIPO poblado pero desconocido: no clasificamos.
    return None, f'TIPO={tipo} desconocido — saltado'


def importar_unidad(db, patente, data, clasificacion, operador_dni, dry_run):
    """Crea cubiertas + instalaciones + locks para todas las posiciones
    de UNA unidad. Saltea las que ya tienen lock activo.
    Devuelve (creadas, saltadas, errores)."""
    es_tractor = clasificacion == 'TRACTOR'
    posiciones = POSICIONES_TRACTOR if es_tractor else POSICIONES_ENGANCHE
    unidad_tipo = 'TRACTOR' if es_tractor else 'ENGANCHE'
    km_actual = (
        float(data.get('KM_ACTUAL') or 0) if es_tractor and data.get('KM_ACTUAL') is not None
        else None
    )

    creadas, saltadas, errores = 0, 0, 0

    for posicion in posiciones:
        lock_id = f'{patente}__{posicion}'
        lock_ref = db.collection('CUBIERTAS_POSICIONES_ACTIVAS').document(lock_id)
        if lock_ref.get().exists:
            saltadas += 1
            continue

        es_direccion = posicion in POSICIONES_DIRECCION
        modelo_id = MODELO_LEGACY_DIRECCION_ID if es_direccion else MODELO_LEGACY_TRACCION_ID
        tipo_uso = 'DIRECCION' if es_direccion else 'TRACCION'
        modelo_etiqueta = (
            'SIN IDENTIFICAR — Dirección' if es_direccion
            else 'SIN IDENTIFICAR — Tracción'
        )

        if dry_run:
            creadas += 1
            continue

        try:
            codigo = reservar_codigo_cubierta(db)
            cubierta_ref = db.collection('CUBIERTAS').document()
            instalacion_ref = db.collection('CUBIERTAS_INSTALADAS').document()
            cubierta_lock_ref = (
                db.collection('CUBIERTAS_ACTIVAS').document(cubierta_ref.id))

            ahora = firestore.SERVER_TIMESTAMP
            batch = db.batch()

            batch.set(cubierta_ref, {
                'codigo': codigo,
                'modelo_id': modelo_id,
                'modelo_etiqueta': modelo_etiqueta,
                'tipo_uso': tipo_uso,
                'estado': 'INSTALADA',
                'vidas': 1,
                'km_acumulados': 0,
                'observaciones': 'Carga inicial — cubierta existente sin datos previos',
                'legacy_inicial': True,
                'creado_en': ahora,
                'creado_por_dni': operador_dni,
                'creado_por_nombre': 'Carga Inicial — Script',
            })

            batch.set(instalacion_ref, {
                'cubierta_id': cubierta_ref.id,
                'cubierta_codigo': codigo,
                'unidad_id': patente,
                'unidad_tipo': unidad_tipo,
                'posicion': posicion,
                'vida_al_instalar': 1,
                'modelo_etiqueta': modelo_etiqueta,
                # km_vida_estimada_al_instalar omitido: sin datos.
                'desde': ahora,
                'hasta': None,
                'km_unidad_al_instalar': km_actual,
                'km_unidad_al_retirar': None,
                'km_recorridos': None,
                'instalado_por_dni': operador_dni,
                'instalado_por_nombre': 'Carga Inicial — Script',
                'retirado_por_dni': None,
                'retirado_por_nombre': None,
                'motivo': 'Carga inicial — cubierta legacy sin datos previos',
                'legacy_inicial': True,
            })

            batch.set(lock_ref, {
                'instalacion_id': instalacion_ref.id,
                'cubierta_id': cubierta_ref.id,
                'cubierta_codigo': codigo,
                'unidad_id': patente,
                'posicion': posicion,
                'desde': ahora,
            })

            batch.set(cubierta_lock_ref, {
                'instalacion_id': instalacion_ref.id,
                'unidad_id': patente,
                'posicion': posicion,
                'desde': ahora,
            })

            batch.commit()
            creadas += 1
        except Exception as e:
            print(f'    ❌ {patente} / {posicion}: {e}')
            errores += 1

    return creadas, saltadas, errores


def main():
    parser = argparse.ArgumentParser(
        description='Carga masiva de cubiertas legacy en todas las posiciones de la flota')
    grp = parser.add_mutually_exclusive_group(required=True)
    grp.add_argument('--dry-run', action='store_true',
                     help='Lista lo que haría sin escribir')
    grp.add_argument('--apply', action='store_true',
                     help='Aplica los cambios a Firestore')
    parser.add_argument('--operador-dni', default='SCRIPT_LEGACY',
                        help='DNI del operador en los campos creado_por_dni / instalado_por_dni')
    args = parser.parse_args()

    db = conectar()

    print('=' * 70)
    print('CARGA INICIAL DE CUBIERTAS LEGACY')
    print(f'Modo: {"DRY-RUN (no escribe)" if args.dry_run else "APPLY (escribe a Firestore)"}')
    print(f'Operador (DNI): {args.operador_dni}')
    print('=' * 70)

    # === 1. Catálogo legacy. ===
    creados_cat = crear_catalogo_legacy(db, args.dry_run)
    if creados_cat:
        print(f'\nCatálogo a crear ({len(creados_cat)} docs):')
        for c in creados_cat:
            print(f'  + {c}')
    else:
        print('\nCatálogo legacy ya existía en Firestore.')

    # === 2. Iterar VEHICULOS y crear cubiertas por posición. ===
    vehiculos = list(db.collection('VEHICULOS').stream())
    print(f'\n{len(vehiculos)} unidades en VEHICULOS\n')

    total_creadas = 0
    total_saltadas = 0
    total_errores = 0
    total_warnings = 0

    for v in sorted(vehiculos, key=lambda d: d.id):
        data = v.to_dict() or {}
        patente = v.id
        clasificacion, warning = clasificar_unidad(patente, data)

        marca = (data.get('MARCA') or '?').strip().upper()
        tipo_db = (data.get('TIPO') or '?').strip().upper()
        km = data.get('KM_ACTUAL', '—')

        if clasificacion is None:
            print(f'⚠️  {patente}  TIPO={tipo_db} MARCA={marca}  → SALTADO ({warning})')
            total_warnings += 1
            continue

        prefijo = '🚛' if clasificacion == 'TRACTOR' else '🚚'
        km_label = f'KM={km}' if clasificacion == 'TRACTOR' else 'KM=N/A'
        print(f'{prefijo} {patente}  TIPO={tipo_db} MARCA={marca}  → {clasificacion}  {km_label}')
        if warning:
            print(f'    ⚠️  {warning}')
            total_warnings += 1

        c, s, e = importar_unidad(
            db, patente, data, clasificacion, args.operador_dni, args.dry_run)
        if c or e:
            print(f'    creadas={c}, saltadas={s}, errores={e}')
        total_creadas += c
        total_saltadas += s
        total_errores += e

    # === 3. Resumen. ===
    print('\n' + '=' * 70)
    print('RESUMEN')
    print('=' * 70)
    if args.dry_run:
        print(f'  Cubiertas que SE CREARÍAN: {total_creadas}')
        print(f'  Posiciones ya ocupadas (se saltarían): {total_saltadas}')
    else:
        print(f'  Cubiertas creadas: {total_creadas}')
        print(f'  Posiciones ya ocupadas (saltadas): {total_saltadas}')
    print(f'  Errores: {total_errores}')
    print(f'  Warnings (clasificación dudosa): {total_warnings}')
    if args.dry_run:
        print('\nNada se escribió. Para aplicar: agregá --apply en lugar de --dry-run')
    else:
        print('\nListo. Las posiciones aparecen ocupadas en la pantalla de Gomería.')


if __name__ == '__main__':
    main()

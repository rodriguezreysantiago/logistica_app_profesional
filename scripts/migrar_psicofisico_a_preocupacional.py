"""
Migración: rename PSICOFISICO → PREOCUPACIONAL en Firestore.

Renombra los campos:
  EMPLEADOS/<dni>:
    VENCIMIENTO_PSICOFISICO  →  VENCIMIENTO_PREOCUPACIONAL
    ARCHIVO_PSICOFISICO      →  ARCHIVO_PREOCUPACIONAL

  AVISOS_VENCIMIENTOS/<id>:
    campo_base == 'PSICOFISICO'  →  'PREOCUPACIONAL'

Es **idempotente**: si ya migró un doc, lo detecta y skipea.

Uso:
    # Primero probar con dry-run (no escribe nada):
    python scripts/migrar_psicofisico_a_preocupacional.py --dry-run

    # Si el resumen se ve bien, correr de verdad:
    python scripts/migrar_psicofisico_a_preocupacional.py

Requiere `serviceAccountKey.json` en el root del proyecto (en .gitignore).
"""

import sys
import argparse
import firebase_admin
from firebase_admin import credentials, firestore
from google.cloud.firestore_v1.base_query import FieldFilter


def conectar():
    try:
        cred = credentials.Certificate("serviceAccountKey.json")
        firebase_admin.initialize_app(cred)
        db = firestore.client()
        print("✅ Conexión a Firebase OK.")
        return db
    except Exception as e:
        print(f"❌ Error de conexión: {e}")
        sys.exit(1)


def migrar_empleados(db, dry_run: bool):
    """
    Para cada empleado: si tiene VENCIMIENTO_PSICOFISICO o
    ARCHIVO_PSICOFISICO, los copia a los campos nuevos y borra los
    viejos. Si ya tiene los nuevos, skipea.
    """
    print("\n=== EMPLEADOS ===")
    docs = db.collection("EMPLEADOS").stream()
    total = 0
    migrados = 0
    ya_migrados = 0
    sin_campos = 0

    for doc in docs:
        total += 1
        data = doc.to_dict() or {}

        tiene_viejo_fecha = "VENCIMIENTO_PSICOFISICO" in data
        tiene_viejo_archivo = "ARCHIVO_PSICOFISICO" in data
        tiene_nuevo_fecha = "VENCIMIENTO_PREOCUPACIONAL" in data
        tiene_nuevo_archivo = "ARCHIVO_PREOCUPACIONAL" in data

        if not tiene_viejo_fecha and not tiene_viejo_archivo:
            if tiene_nuevo_fecha or tiene_nuevo_archivo:
                ya_migrados += 1
            else:
                sin_campos += 1
            continue

        updates = {}
        if tiene_viejo_fecha and not tiene_nuevo_fecha:
            updates["VENCIMIENTO_PREOCUPACIONAL"] = data["VENCIMIENTO_PSICOFISICO"]
        if tiene_viejo_archivo and not tiene_nuevo_archivo:
            updates["ARCHIVO_PREOCUPACIONAL"] = data["ARCHIVO_PSICOFISICO"]

        # Marcamos los viejos para borrar (Firestore acepta DELETE_FIELD).
        if tiene_viejo_fecha:
            updates["VENCIMIENTO_PSICOFISICO"] = firestore.DELETE_FIELD
        if tiene_viejo_archivo:
            updates["ARCHIVO_PSICOFISICO"] = firestore.DELETE_FIELD

        accion = "DRY-RUN" if dry_run else "OK"
        print(
            f"  [{accion}] EMPLEADOS/{doc.id} → "
            f"{', '.join(k for k in updates if 'PREOCUPACIONAL' in k) or '(solo borra viejos)'}"
        )
        if not dry_run:
            doc.reference.update(updates)
        migrados += 1

    print(
        f"\nResumen EMPLEADOS: total={total}, "
        f"migrados={migrados}, ya estaban migrados={ya_migrados}, "
        f"sin el campo={sin_campos}"
    )


def migrar_avisos(db, dry_run: bool):
    """
    En AVISOS_VENCIMIENTOS: cambiar campo_base de 'PSICOFISICO' a
    'PREOCUPACIONAL' para que el historial de avisos viejos siga
    apareciendo cuando el admin abre la pantalla del nuevo nombre.
    """
    print("\n=== AVISOS_VENCIMIENTOS ===")
    docs = (
        db.collection("AVISOS_VENCIMIENTOS")
        .where(filter=FieldFilter("campo_base", "==", "PSICOFISICO"))
        .stream()
    )
    total = 0
    for doc in docs:
        total += 1
        accion = "DRY-RUN" if dry_run else "OK"
        print(f"  [{accion}] AVISOS_VENCIMIENTOS/{doc.id} → campo_base=PREOCUPACIONAL")
        if not dry_run:
            doc.reference.update({"campo_base": "PREOCUPACIONAL"})

    print(f"\nResumen AVISOS_VENCIMIENTOS: actualizados={total}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="No escribe en Firestore, solo muestra qué haría.",
    )
    args = parser.parse_args()

    if args.dry_run:
        print("🔍 MODO DRY-RUN — no se va a escribir nada.\n")
    else:
        print("⚠️  MODO REAL — se van a modificar documentos en Firestore.\n")
        confirm = input("¿Confirmás? (escribí SI para continuar): ").strip()
        if confirm != "SI":
            print("Cancelado.")
            sys.exit(0)

    db = conectar()
    migrar_empleados(db, args.dry_run)
    migrar_avisos(db, args.dry_run)

    print("\n--- PROCESO FINALIZADO ---")
    if args.dry_run:
        print("Si el resumen se ve bien, corré sin --dry-run para aplicar.")


if __name__ == "__main__":
    main()

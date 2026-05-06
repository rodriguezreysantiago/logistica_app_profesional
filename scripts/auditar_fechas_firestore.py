"""
Auditoría: detectar formato de fechas guardadas en Firestore.

Recorre EMPLEADOS y VEHICULOS y reporta, para cada campo de fecha
calendario, qué formato tiene cada valor:

  - YYYY-MM-DD       → ✅ correcto (convención del proyecto)
  - DD/MM/YYYY       → ❌ incorrecto (formato de display, no storage)
  - DD-MM-YYYY       → ❌ incorrecto
  - MM/DD/YYYY       → ❌ incorrecto (ambiguo con DD/MM)
  - ISO con T        → ⚠️  legacy (ej. 2026-03-15T00:00:00.000)
  - Timestamp        → ⚠️  no debería usarse para fechas calendario
  - vacío/None       → ok
  - otro             → 🔍 inspección manual

Output:
  1. Resumen por colección + campo (cuántos en cada formato).
  2. Ejemplos de los formatos malos (docId + valor) — máx 5 por tipo.

Es SOLO LECTURA. No modifica nada en Firestore.

Uso:
    python scripts/auditar_fechas_firestore.py

Requiere serviceAccountKey.json en root.
"""

import re
import sys
from collections import defaultdict

import firebase_admin
from firebase_admin import credentials, firestore


# Regex para detectar formatos.
RE_ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
RE_ISO_DATETIME = re.compile(r"^\d{4}-\d{2}-\d{2}T")
RE_DDMM_SLASH = re.compile(r"^\d{2}/\d{2}/\d{4}$")
RE_DDMM_DASH = re.compile(r"^\d{2}-\d{2}-\d{4}$")


# Campos de fecha calendario por colección.
CAMPOS_POR_COLECCION = {
    "EMPLEADOS": [
        "VENCIMIENTO_LICENCIA",
        "VENCIMIENTO_PREOCUPACIONAL",
        "VENCIMIENTO_PSICOFISICO",  # legacy, por las dudas
        "VENCIMIENTO_ART",
        "VENCIMIENTO_MANEJO_DEFENSIVO",
        "VENCIMIENTO_F931",
        "VENCIMIENTO_SEGURO_VIDA",
        "VENCIMIENTO_SINDICATO",
        "FECHA_NACIMIENTO",
        "FECHA_INGRESO",
    ],
    "VEHICULOS": [
        "VENCIMIENTO_RTO",
        "VENCIMIENTO_SEGURO",
        "VENCIMIENTO_EXTINTOR_CABINA",
        "VENCIMIENTO_EXTINTOR_EXTERIOR",
        "ULTIMO_SERVICE_FECHA",
    ],
}


def clasificar_valor(valor):
    """Devuelve el tipo de formato detectado para un valor de fecha."""
    if valor is None or valor == "":
        return "vacío"
    if hasattr(valor, "isoformat"):
        # Es un Timestamp de Firestore (DatetimeWithNanoseconds) o datetime.
        return "Timestamp"
    if not isinstance(valor, str):
        return f"otro ({type(valor).__name__})"
    s = valor.strip()
    if RE_ISO_DATE.match(s):
        return "YYYY-MM-DD ✅"
    if RE_ISO_DATETIME.match(s):
        return "ISO con T ⚠️"
    if RE_DDMM_SLASH.match(s):
        # Heurística: si los 2 primeros dígitos son > 12 sabemos que es DD/MM.
        # Si <= 12 y los 2 segundos > 12, es MM/DD. Si ambos <=12, ambiguo.
        d, m = int(s[:2]), int(s[3:5])
        if d > 12:
            return "DD/MM/YYYY ❌"
        if m > 12:
            return "MM/DD/YYYY ❌"
        return "DD-o-MM/DD ambiguo ❌"
    if RE_DDMM_DASH.match(s):
        d, m = int(s[:2]), int(s[3:5])
        if d > 12:
            return "DD-MM-YYYY ❌"
        if m > 12:
            return "MM-DD-YYYY ❌"
        return "DD-o-MM-DD ambiguo ❌"
    return f"otro string ('{s[:30]}')"


def conectar():
    try:
        cred = credentials.Certificate("serviceAccountKey.json")
        firebase_admin.initialize_app(cred)
        db = firestore.client()
        print("Conectado a Firestore.\n")
        return db
    except Exception as e:
        print(f"Error de conexion: {e}")
        sys.exit(1)


def auditar_coleccion(db, coleccion, campos):
    print(f"=== {coleccion} ===")
    docs = list(db.collection(coleccion).stream())
    print(f"  total docs: {len(docs)}")
    # Por campo, contador de formatos + lista de ejemplos por formato.
    por_campo = defaultdict(lambda: {"counts": defaultdict(int), "ejemplos": defaultdict(list)})

    for doc in docs:
        data = doc.to_dict() or {}
        for campo in campos:
            if campo not in data:
                por_campo[campo]["counts"]["faltante"] += 1
                continue
            valor = data[campo]
            tipo = clasificar_valor(valor)
            por_campo[campo]["counts"][tipo] += 1
            if "❌" in tipo or "⚠️" in tipo or tipo.startswith("otro"):
                if len(por_campo[campo]["ejemplos"][tipo]) < 5:
                    por_campo[campo]["ejemplos"][tipo].append(
                        (doc.id, repr(valor))
                    )

    # Reporte
    for campo in campos:
        info = por_campo[campo]
        if not info["counts"]:
            continue
        # ¿Solo "faltante" o "vacío"? Skip (nadie lo usa).
        relevantes = {k: v for k, v in info["counts"].items() if k not in ("faltante", "vacío")}
        if not relevantes:
            continue
        print(f"\n  [{campo}]")
        for tipo, count in sorted(info["counts"].items(), key=lambda x: -x[1]):
            marca = ""
            if "❌" in tipo:
                marca = " ← ARREGLAR"
            elif "⚠️" in tipo:
                marca = " ← legacy"
            print(f"    {count:5d}  {tipo}{marca}")
        for tipo, ejs in info["ejemplos"].items():
            if ejs:
                print(f"    Ejemplos {tipo}:")
                for doc_id, val in ejs:
                    print(f"      - {doc_id}: {val}")
    print()


def main():
    db = conectar()
    for coleccion, campos in CAMPOS_POR_COLECCION.items():
        auditar_coleccion(db, coleccion, campos)
    print("Fin de auditoria.")


if __name__ == "__main__":
    main()

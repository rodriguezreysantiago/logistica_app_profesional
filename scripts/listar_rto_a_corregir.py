"""
Lista todos los VEHICULOS cuyo VENCIMIENTO_RTO NO esté en formato
YYYY-MM-DD, ordenados por patente. Para corrección manual desde
Firebase Console.

Output:
  - Tabla en consola.
  - CSV en `fechas_rto_a_corregir.csv` (compatible con Excel — separador
    coma, encoding utf-8-sig para que Excel reconozca acentos).

Sólo lectura de Firestore.

Uso:
    python scripts/listar_rto_a_corregir.py

Requiere serviceAccountKey.json en root.
"""

import csv
import re
import sys

import firebase_admin
from firebase_admin import credentials, firestore


RE_ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
RE_DDMM_LIKE = re.compile(r"^(\d{1,2})/(\d{1,2})/(\d{4})$")
RE_DDMM_DASH = re.compile(r"^(\d{1,2})-(\d{1,2})-(\d{4})$")


def conectar():
    try:
        cred = credentials.Certificate("serviceAccountKey.json")
        firebase_admin.initialize_app(cred)
        return firestore.client()
    except Exception as e:
        print(f"Error de conexion: {e}")
        sys.exit(1)


def diagnostico(valor):
    """
    Para un valor de string como '10/03/2026', '23/12/2026', '5/1/2027',
    devuelve un dict con interpretaciones DD/MM y MM/DD para que el user
    decida.
    """
    if not isinstance(valor, str):
        return {"tipo": "no-string", "raw": repr(valor)}
    s = valor.strip()
    if RE_ISO_DATE.match(s):
        return None  # ya está bien, no listar
    m = RE_DDMM_LIKE.match(s) or RE_DDMM_DASH.match(s)
    if not m:
        return {"tipo": "raro", "raw": s, "nota": "formato no reconocido"}

    n1, n2, year = int(m.group(1)), int(m.group(2)), int(m.group(3))

    # Inequívoco DD/MM: primer número > 12.
    if n1 > 12:
        return {
            "tipo": "DD/MM (inequivoco)",
            "raw": s,
            "interpretacion": f"{year:04d}-{n2:02d}-{n1:02d}",
        }
    # Inequívoco MM/DD: segundo número > 12 (raro en este dataset).
    if n2 > 12:
        return {
            "tipo": "MM/DD (inequivoco)",
            "raw": s,
            "interpretacion": f"{year:04d}-{n1:02d}-{n2:02d}",
        }
    # Ambos ≤ 12 → ambiguo.
    return {
        "tipo": "AMBIGUO",
        "raw": s,
        "interp_si_DDMM": f"{year:04d}-{n2:02d}-{n1:02d}",
        "interp_si_MMDD": f"{year:04d}-{n1:02d}-{n2:02d}",
    }


def main():
    db = conectar()
    rows = []
    for doc in db.collection("VEHICULOS").stream():
        data = doc.to_dict() or {}
        valor = data.get("VENCIMIENTO_RTO")
        if valor is None or valor == "":
            continue
        diag = diagnostico(valor)
        if diag is None:
            continue
        rows.append({"patente": doc.id, **diag})

    rows.sort(key=lambda r: r["patente"])

    # Consola
    print(f"\n{len(rows)} vehiculos con VENCIMIENTO_RTO problematico:\n")
    print(f"{'PATENTE':<10} {'VALOR':<14} {'TIPO':<22} {'PROPUESTA / NOTA'}")
    print("-" * 90)
    for r in rows:
        if r["tipo"] == "AMBIGUO":
            propuesta = f"DD/MM={r['interp_si_DDMM']}  o  MM/DD={r['interp_si_MMDD']}"
        elif "interpretacion" in r:
            propuesta = r["interpretacion"]
        else:
            propuesta = r.get("nota", "")
        print(f"{r['patente']:<10} {r['raw']:<14} {r['tipo']:<22} {propuesta}")

    # CSV
    out_path = "fechas_rto_a_corregir.csv"
    with open(out_path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["PATENTE", "VALOR_ACTUAL", "TIPO",
                    "INTERPRETACION_SI_DDMM", "INTERPRETACION_SI_MMDD",
                    "VALOR_CORRECTO_YYYY_MM_DD"])
        for r in rows:
            ddmm = r.get("interp_si_DDMM") or r.get("interpretacion") or ""
            mmdd = r.get("interp_si_MMDD") or ""
            # Si es inequivoco, ya tenemos la respuesta — la dejamos en
            # la columna VALOR_CORRECTO. Si es ambiguo, queda vacio
            # para que el user lo complete.
            if r["tipo"].startswith("DD/MM (inequivoco)") or r["tipo"].startswith("MM/DD (inequivoco)"):
                correcto = r["interpretacion"]
            else:
                correcto = ""
            w.writerow([r["patente"], r["raw"], r["tipo"], ddmm, mmdd, correcto])
    print(f"\nCSV escrito en: {out_path}")
    print("Abrilo en Excel, completa la columna VALOR_CORRECTO_YYYY_MM_DD")
    print("para los AMBIGUOS, y despues lo usas para corregir en Firestore.")


if __name__ == "__main__":
    main()

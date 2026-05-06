import re

import pandas as pd
import firebase_admin
from firebase_admin import credentials, firestore

# 1. Conexión con Firebase
try:
    cred = credentials.Certificate("serviceAccountKey.json")
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    print("✅ Conexión a Firebase OK.")
except Exception as e:
    print(f"❌ Error de conexión: {e}")
    exit()


# --- Helper de parseo de fechas ---
# La convención del proyecto es STORAGE en YYYY-MM-DD (string ISO).
# Si el CSV viene con formato AR (DD/MM/YYYY) o variantes con 1 dígito
# (D/M/YYYY), normalizamos. Si es ambiguo (ambos números ≤ 12) asumimos
# DD/MM (regla AR default) — el script imprime warning para que el
# operator pueda revisar a mano si hace falta.
#
# Sin este parseo el script copiaba el string crudo y dejaba en
# Firestore valores como '5/1/2027' o '23/12/2026' mezclados. Diagnosticado
# 2026-05-06 (ver scripts/listar_rto_a_corregir.py).
def parsear_fecha_a_iso(valor, contexto="?"):
    """Devuelve YYYY-MM-DD a partir de un valor de fecha en formato libre.
    Acepta YYYY-MM-DD, DD/MM/YYYY, D/M/YYYY, DD-MM-YYYY (con dashes).
    Si el valor está vacío/NaN devuelve "". Si no se puede parsear
    levanta ValueError (rompe el load — preferible a guardar basura)."""
    if valor is None or (isinstance(valor, float) and pd.isna(valor)):
        return ""
    s = str(valor).strip()
    if s == "" or s.lower() == "nan":
        return ""
    # Ya en YYYY-MM-DD (con o sin padding).
    m = re.match(r"^(\d{4})-(\d{1,2})-(\d{1,2})$", s)
    if m:
        y, mth, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
        return f"{y:04d}-{mth:02d}-{d:02d}"
    # D[D]/[/-]M[M]/[/-]YYYY.
    m = re.match(r"^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$", s)
    if m:
        n1, n2, year = int(m.group(1)), int(m.group(2)), int(m.group(3))
        if n1 > 12:
            day, month = n1, n2
        elif n2 > 12:
            day, month = n2, n1
            print(f"⚠️ [{contexto}] '{s}' interpretado como MM/DD ({day:02d}/{month:02d}/{year}). Verificar.")
        else:
            day, month = n1, n2  # default AR DD/MM
            print(f"⚠️ [{contexto}] '{s}' es AMBIGUO (ambos ≤12). Asumido DD/MM = {day:02d}/{month:02d}/{year}. Verificar.")
        if 1 <= day <= 31 and 1 <= month <= 12:
            return f"{year:04d}-{month:02d}-{day:02d}"
    raise ValueError(f"Formato de fecha no reconocido en {contexto}: {valor!r}")

def cargar_datos():
    file_path = 'vehiculos.csv'
    
    try:
        # El motor 'python' y sep=None detectan si es coma, punto y coma o tabulación
        df = pd.read_csv(file_path, encoding='utf-8-sig', sep=None, engine='python')
        print(f"✅ Archivo detectado. Columnas encontradas: {len(df.columns)}")
        print(f"Filas totales: {len(df)}")
    except Exception as e:
        print(f"❌ Error al abrir el archivo: {e}")
        return

    for index, row in df.iterrows():
        try:
            # Aseguramos que el dominio sea la primera columna disponible
            dominio = str(row.iloc[0]).strip().upper()
            
            if dominio == "" or dominio == "NAN" or "DOMINIO" in dominio:
                continue

            # Creamos el diccionario de datos de forma SEGURA
            # Si el archivo tiene menos columnas de las esperadas, pone "---"
            datos = {
                'DOMINIO': dominio,
                'TIPO': str(row.iloc[1]) if len(row) > 1 else "---",
                'MARCA': str(row.iloc[2]) if len(row) > 2 else "---",
                'MODELO': str(row.iloc[3]) if len(row) > 3 else "---",
                'AÑO': str(row.iloc[4]) if len(row) > 4 else "---",
                'TIPIFICADA': str(row.iloc[5]) if len(row) > 5 else "---",
                'RTO_NRO': str(row.iloc[6]) if len(row) > 6 else "---",
                'VENCIMIENTO_RTO': parsear_fecha_a_iso(row.iloc[7], f"{dominio}/RTO") if len(row) > 7 else "",
                'POLIZA_NRO': str(row.iloc[8]) if len(row) > 8 else "---",
                'VENCIMIENTO_POLIZA': parsear_fecha_a_iso(row.iloc[9], f"{dominio}/POLIZA") if len(row) > 9 else "",
                'EMPRESA': str(row.iloc[10]) if len(row) > 10 else "---",
            }

            # Limpiamos los textos de "nan" que pone Python por defecto
            for k, v in datos.items():
                if str(v).lower() == "nan": datos[k] = "---"

            db.collection('VEHICULOS').document(dominio).set(datos)
            print("🚀 [" + str(index + 1) + "] Cargado: " + dominio)

        except Exception as e:
            print("⚠️ Error en fila " + str(index + 1) + ": " + str(e))

    print("\n--- PROCESO FINALIZADO ---")

if __name__ == "__main__":
    cargar_datos()
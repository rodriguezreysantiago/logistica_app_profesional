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
                'VENCIMIENTO_RTO': str(row.iloc[7]) if len(row) > 7 else "---",
                'POLIZA_NRO': str(row.iloc[8]) if len(row) > 8 else "---",
                'VENCIMIENTO_POLIZA': str(row.iloc[9]) if len(row) > 9 else "---",
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
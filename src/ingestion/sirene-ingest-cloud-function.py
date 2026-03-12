import functions_framework
import requests
from google.cloud import storage
from datetime import datetime

BUCKET_NAME = "datatalent-dev-cartographie-data-engineer-raw"
URL_UNITE_LEGALE = "https://object.files.data.gouv.fr/data-pipeline-open/siren/stock/StockUniteLegale_utf8.parquet"

# Point d'entrée HTTP pour Cloud Function
@functions_framework.http
def ingest_sirene(request):
    now = datetime.now()
    gcs_path = f"raw/sirene-data/{now.year}/{now.month:02d}/StockUniteLegale_utf8.parquet"
    stream_to_gcs(URL_UNITE_LEGALE, gcs_path)
    return "OK", 200

def stream_to_gcs(url, gcs_path):
    client = storage.Client()
    bucket = client.bucket(BUCKET_NAME)
    blob = bucket.blob(gcs_path)

    with requests.get(url, stream=True) as r:
        r.raise_for_status()
        total = int(r.headers.get("content-length", 0))
        downloaded = 0
        with blob.open("wb") as f:
            for chunk in r.iter_content(chunk_size=8 * 1024 * 1024):
                f.write(chunk)
                downloaded += len(chunk)
                if total:
                    print(f"{downloaded // 1024 // 1024} Mo / {total // 1024 // 1024} Mo")

    print(f"✅ Déposé dans gs://{BUCKET_NAME}/{gcs_path}")




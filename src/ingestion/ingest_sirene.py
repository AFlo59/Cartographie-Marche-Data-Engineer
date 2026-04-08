import os
from datetime import datetime

import requests
from google.cloud import storage
import logging

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

URLS = {
    "StockUniteLegale": "https://object.files.data.gouv.fr/data-pipeline-open/siren/stock/StockUniteLegale_utf8.parquet",
    "StockEtablissement": "https://object.files.data.gouv.fr/data-pipeline-open/siren/stock/StockEtablissement_utf8.parquet",
}

# BUCKET_NAME = os.environ["INGESTION_RAW_BUCKET"]
# SIRENE_PREFIX = os.environ.get("INGESTION_SIRENE_PREFIX", "raw/sirene/")
BUCKET_NAME = os.environ.get("TF_VAR_raw_bucket_name")
SIRENE_PREFIX = os.environ.get("TF_VAR_ingestion_sirene_prefix", "raw/sirene/")


def stream_to_gcs(url: str, gcs_path: str) -> None:
    if not BUCKET_NAME:
        raise ValueError("Le nom du bucket GCS doit être défini dans la variable d'environnement INGESTION_RAW_BUCKET")
    client = storage.Client()
    bucket = client.bucket(BUCKET_NAME)
    blob = bucket.blob(gcs_path)

    print(f"⬇️ Téléchargement depuis {url}")

    with requests.get(url, stream=True, timeout=60) as response:
        response.raise_for_status()
        total = int(response.headers.get("content-length", 0))
        downloaded = 0

        with blob.open("wb") as file_obj:
            for chunk in response.iter_content(chunk_size=8 * 1024 * 1024):
                if not chunk:
                    continue

                file_obj.write(chunk)
                downloaded += len(chunk)

                if total:
                    print(
                        f"\r  {downloaded // 1024 // 1024} Mo / {total // 1024 // 1024} Mo",
                        end="",
                        flush=True,
                    )

    print(f"\n✅ Déposé dans gs://{BUCKET_NAME}/{gcs_path}")


def ingest_sirene() -> None:
    """fonction principale d'ingestion de la source Sirene"""
    log.info("🚀 Démarrage de l'ingestion de la source Sirene")
    now = datetime.now()

    for name, url in URLS.items():
        gcs_path = f"{SIRENE_PREFIX}{now.year}/{now.month:02d}/{name}.parquet"
        stream_to_gcs(url, gcs_path)

    log.info("✅ Ingestion de la source Sirene terminée")
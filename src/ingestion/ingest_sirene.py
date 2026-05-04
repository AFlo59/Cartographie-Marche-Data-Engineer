import os
import sys
from datetime import datetime

import requests

sys.path.insert(0, os.path.dirname(__file__))

from utils.config import Config  # noqa: E402
from utils.gcs import stream_upload_to_gcs  # noqa: E402
from utils.logging_config import get_logger  # noqa: E402

logger = get_logger("ingest_sirene")

_URLS = {
    "StockUniteLegale": (
        "https://object.files.data.gouv.fr/data-pipeline-open/siren/stock/"
        "StockUniteLegale_utf8.parquet"
    ),
    "StockEtablissement": (
        "https://object.files.data.gouv.fr/data-pipeline-open/siren/stock/"
        "StockEtablissement_utf8.parquet"
    ),
}


def ingest_sirene() -> None:
    """Ingestion des fichiers Sirene (StockUniteLegale + StockEtablissement)."""
    if not Config.RAW_BUCKET:
        raise ValueError("INGESTION_RAW_BUCKET est requis pour l'ingestion Sirene.")

    logger.info("Démarrage de l'ingestion de la source Sirene")
    now = datetime.now()

    for name, url in _URLS.items():
        gcs_path = (
            f"{Config.SIRENE_PREFIX.rstrip('/')}/{now.strftime('%Y-%m')}/{name}.parquet"
        )
        logger.info(f"Téléchargement {name} depuis {url}")
        with requests.get(url, stream=True, timeout=120) as response:
            response.raise_for_status()
            stream_upload_to_gcs(response, Config.RAW_BUCKET, gcs_path)

    logger.info("Ingestion de la source Sirene terminée")

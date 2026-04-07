#!/usr/bin/env python3
"""
Ingestion — Stock Sirene INSEE (via data.gouv.fr)
Sources    : StockEtablissement + StockUniteLegale (fichiers Parquet mensuels)
Schedule   : mensuel — 0 3 1 * *
Output     : raw/sirene/YYYY-MM/StockEtablissement.parquet
             raw/sirene/YYYY-MM/StockUniteLegale.parquet
Idempotent : écrasement mensuel (même chemin GCS)

Stratégie :
  - Interroge l'API data.gouv.fr pour trouver les URLs des fichiers Parquet du mois
  - Téléchargement en streaming → upload GCS resumable (aucun chargement en mémoire)
  - Retry avec backoff exponentiel sur erreurs réseau / HTTP 5xx
"""

import os
import sys
import time

import requests

sys.path.insert(0, os.path.dirname(__file__))

from utils.config import Config  # noqa: E402
from utils.gcs import stream_upload_to_gcs  # noqa: E402
from utils.logging_config import get_logger  # noqa: E402

logger = get_logger("ingest_sirene")

# ---------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------
_DATAGOUV_API = "https://www.data.gouv.fr/api/1/datasets"
_MAX_RETRIES = 3
_BACKOFF_BASE = 5  # secondes

# Mots-clés identifiant chaque fichier cible dans la liste des ressources
_TARGETS = {
    "StockEtablissement": "StockEtablissement",
    "StockUniteLegale": "StockUniteLegale",
}


# ---------------------------------------------------------------------------
# Découverte des URLs via l'API data.gouv.fr
# ---------------------------------------------------------------------------
def get_dataset_resources() -> list[dict]:
    url = f"{_DATAGOUV_API}/{Config.SIRENE_DATASET_SLUG}/"
    resp = requests.get(url, timeout=30)
    resp.raise_for_status()
    resources: list[dict] = resp.json().get("resources", [])
    logger.info(
        f"data.gouv.fr : {len(resources)} ressources trouvées pour le dataset Sirene"
    )
    return resources


def find_parquet_urls(resources: list[dict]) -> dict[str, str]:
    """
    Retourne un dict {nom_cible: url_download} pour chaque fichier Parquet cible.
    Privilégie les ressources au format Parquet. Si plusieurs versions existent,
    prend la plus récente (tri par last_modified desc).
    """
    found: dict[str, list[dict]] = {k: [] for k in _TARGETS}

    for res in resources:
        fmt = (res.get("format") or "").lower()
        title = res.get("title") or res.get("url", "")
        if fmt not in ("parquet", "application/parquet"):
            continue
        for target_key, keyword in _TARGETS.items():
            if keyword.lower() in title.lower():
                found[target_key].append(res)

    result: dict[str, str] = {}
    for target_key, candidates in found.items():
        if not candidates:
            logger.warning(f"Aucun fichier Parquet trouvé pour {target_key}")
            continue
        # Plus récent en premier
        candidates.sort(key=lambda r: r.get("last_modified", ""), reverse=True)
        url = candidates[0]["url"]
        logger.info(f"{target_key} → {url}")
        result[target_key] = url

    return result


# ---------------------------------------------------------------------------
# Téléchargement streaming avec retry
# ---------------------------------------------------------------------------
def download_and_upload(url: str, bucket: str, blob_path: str) -> None:
    headers: dict[str, str] = {}
    api_key = Config.datagouv_api_key()
    if api_key:
        headers["X-API-KEY"] = api_key

    for attempt in range(_MAX_RETRIES):
        try:
            resp = requests.get(url, headers=headers, stream=True, timeout=120)
            resp.raise_for_status()
            stream_upload_to_gcs(resp, bucket, blob_path)
            return
        except (requests.RequestException, Exception) as exc:
            wait = _BACKOFF_BASE * (2**attempt)
            if attempt < _MAX_RETRIES - 1:
                logger.warning(f"Erreur téléchargement ({exc}) — retry dans {wait}s")
                time.sleep(wait)
            else:
                logger.error(f"Abandon après {_MAX_RETRIES} tentatives pour {url}")
                raise


# ---------------------------------------------------------------------------
# Point d'entrée
# ---------------------------------------------------------------------------
def main() -> None:
    from datetime import datetime, timezone

    partition = datetime.now(timezone.utc).strftime("%Y-%m")
    prefix = Config.SIRENE_PREFIX.rstrip("/")

    resources = get_dataset_resources()
    parquet_urls = find_parquet_urls(resources)

    if not parquet_urls:
        logger.error("Aucune URL Parquet Sirene trouvée — ingestion annulée.")
        raise RuntimeError("Aucun fichier Parquet Sirene disponible sur data.gouv.fr")

    for target_name, url in parquet_urls.items():
        blob_path = f"{prefix}/{partition}/{target_name}.parquet"
        logger.info(
            f"Téléchargement {target_name} → gs://{Config.RAW_BUCKET}/{blob_path}"
        )
        download_and_upload(url, Config.RAW_BUCKET, blob_path)

    logger.info("Ingestion Sirene terminée.")


if __name__ == "__main__":
    main()

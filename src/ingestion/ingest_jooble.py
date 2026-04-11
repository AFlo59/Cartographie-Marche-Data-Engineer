#!/usr/bin/env python3
from __future__ import annotations

"""
Ingestion — Jooble offres d'emploi via API REST
Source    : POST https://fr.jooble.org/api/{api_key}
Schedule  : hebdomadaire — 0 8 * * 1 (lundi 8h)
Output    : raw/jooble/dt=YYYY-MM-DD/offres.parquet
Idempotent : écrasement du fichier du jour (même chemin GCS)

Stratégie :
  - Pagination via le champ `page` du body POST.
  - Filtre côté client sur le champ `updated` : seules les offres
    des LOOKBACK_DAYS derniers jours sont conservées.
  - Aucun stockage persistant dans le conteneur ; upload direct BytesIO → GCS.
"""

import html
import http.client
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone

import pandas as pd

# Ajout du path pour les imports relatifs si exécuté en script direct
sys.path.insert(0, os.path.dirname(__file__))

from utils.config import Config  # noqa: E402
from utils.gcs import upload_dataframe_as_parquet  # noqa: E402
from utils.logging_config import get_logger  # noqa: E402

logger = get_logger("ingest_jooble")

_LOOKBACK_DAYS = 8  # Pour couvrir une semaine complète + marge


def _fetch_jobs_page(page: int) -> dict:
    """Appelle l'API Jooble pour une page de résultats."""
    api_key = Config.jooble_api_key()
    if not api_key:
        raise ValueError(
            "La clé API Jooble doit être définie (env JOOBLE_API_KEY ou Secret Manager)"
        )

    body = json.dumps({"keywords": "data engineer", "location": "France", "page": page})

    headers = {"Content-type": "application/json"}
    connection = http.client.HTTPSConnection(Config.JOOBLE_HOST)
    connection.request("POST", f"/api/{api_key}", body, headers)
    response = connection.getresponse()

    if response.status != 200:
        raise ValueError(f"Erreur API Jooble : {response.status} {response.reason}")

    data = json.loads(response.read())
    connection.close()
    return data


def _clean_snippet(text: str) -> str:
    """Nettoie le HTML du snippet Jooble."""
    if not text:
        return ""
    text = html.unescape(text)
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def _parse_date(updated_str: str) -> datetime | None:
    """Parse la date au format ISO Jooble."""
    try:
        updated_str_clean = updated_str[:26]
        return datetime.fromisoformat(updated_str_clean).replace(tzinfo=timezone.utc)
    except Exception as e:
        logger.warning(f"Impossible de parser la date '{updated_str}' : {e}")
        return None


def main() -> None:
    """Fonction principale d'ingestion de la source Jooble."""
    if not Config.RAW_BUCKET:
        raise ValueError("INGESTION_RAW_BUCKET est requis pour l'ingestion Jooble.")

    logger.info("Démarrage de l'ingestion de la source Jooble")

    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(days=_LOOKBACK_DAYS)
    logger.info(f"Filtre : offres publiées après le {cutoff.strftime('%Y-%m-%d')}")

    all_jobs = []
    page = 1

    while True:
        logger.info(f"Récupération de la page {page}...")
        result = _fetch_jobs_page(page=page)

        jobs = result.get("jobs", [])
        total = result.get("totalCount", 0)

        if not jobs:
            logger.info("Plus de résultats, fin de la pagination")
            break

        recent_jobs = []
        for j in jobs:
            updated_dt = _parse_date(j.get("updated", ""))
            if updated_dt and updated_dt >= cutoff:
                j["updated_dt"] = updated_dt
                j["snippet"] = _clean_snippet(j.get("snippet", ""))
                recent_jobs.append(j)

        old_jobs_count = len(jobs) - len(recent_jobs)
        all_jobs.extend(recent_jobs)

        logger.info(
            f"  → {len(recent_jobs)} offres récentes gardées, "
            f"{old_jobs_count} trop anciennes ignorées "
            f"({len(all_jobs)} au total)"
        )

        if len(recent_jobs) == 0:
            logger.info("Page entière trop ancienne ou vide, arrêt de la pagination")
            break

        if len(all_jobs) >= total:
            break

        page += 1

    if not all_jobs:
        logger.info("Aucune offre récente trouvée, rien à sauvegarder")
        return

    df = pd.DataFrame(all_jobs)

    df["scraped_at"] = now
    df["source_name"] = "jooble"

    if "id" in df.columns:
        df = df.rename(columns={"id": "jooble_id"})

    partition = now.strftime("%Y-%m-%d")
    blob_path = f"{Config.JOOBLE_PREFIX.rstrip('/')}/dt={partition}/offres.parquet"

    upload_dataframe_as_parquet(df, Config.RAW_BUCKET, blob_path)

    logger.info(
        f"Ingestion Jooble terminée — "
        f"{len(df)} offres sauvegardées dans gs://{Config.RAW_BUCKET}/{blob_path}"
    )


if __name__ == "__main__":
    main()

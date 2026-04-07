#!/usr/bin/env python3
"""
Ingestion — API Géo (geo.api.gouv.fr)
Sources  : régions, départements, communes françaises
Schedule : mensuel — 0 4 1 * *
Output   : raw/geo/YYYY-MM/{regions,departements,communes}.parquet
Idempotent : écrasement mensuel (même chemin GCS)
"""
import os
import sys
from datetime import datetime, timezone

import pandas as pd
import requests
from typing import Optional

sys.path.insert(0, os.path.dirname(__file__))

from utils.config import Config
from utils.gcs import upload_dataframe_as_parquet
from utils.logging_config import get_logger

logger = get_logger("ingest_geo")

_COMMUNES_FIELDS = "code,nom,codeRegion,codeDepartement,codesPostaux,population,centre"
_PAGE_SIZE = 1000


def _get(url: str, params: Optional[dict] = None) -> list:
    resp = requests.get(url, params=params, timeout=30)
    resp.raise_for_status()
    return resp.json()


def fetch_regions() -> pd.DataFrame:
    data = _get(f"{Config.GEO_API_BASE}/regions")
    df = pd.DataFrame(data)
    logger.info(f"Régions : {len(df)} lignes")
    return df


def fetch_departements() -> pd.DataFrame:
    data = _get(f"{Config.GEO_API_BASE}/departements")
    df = pd.DataFrame(data)
    logger.info(f"Départements : {len(df)} lignes")
    return df


def fetch_communes() -> pd.DataFrame:
    rows: list[dict] = []
    offset = 0
    while True:
        batch = _get(
            f"{Config.GEO_API_BASE}/communes",
            params={"fields": _COMMUNES_FIELDS, "limit": _PAGE_SIZE, "offset": offset},
        )
        if not batch:
            break
        rows.extend(batch)
        logger.info(f"Communes : {len(rows):,} récupérées (offset={offset})")
        if len(batch) < _PAGE_SIZE:
            break
        offset += _PAGE_SIZE

    df = pd.json_normalize(rows)

    # Extraire latitude/longitude depuis centre.coordinates [lon, lat]
    if "centre.coordinates" in df.columns:
        df["longitude"] = df["centre.coordinates"].apply(
            lambda x: x[0] if isinstance(x, list) and len(x) == 2 else None
        )
        df["latitude"] = df["centre.coordinates"].apply(
            lambda x: x[1] if isinstance(x, list) and len(x) == 2 else None
        )
        df.drop(columns=["centre.coordinates", "centre.type"], errors="ignore", inplace=True)

    # codesPostaux est une liste — on la sérialise en string CSV
    if "codesPostaux" in df.columns:
        df["codesPostaux"] = df["codesPostaux"].apply(
            lambda x: ",".join(x) if isinstance(x, list) else x
        )

    logger.info(f"Communes total : {len(df):,} lignes")
    return df


def main() -> None:
    partition = datetime.now(timezone.utc).strftime("%Y-%m")
    prefix = Config.GEO_PREFIX.rstrip("/")

    datasets: dict[str, pd.DataFrame] = {
        "regions": fetch_regions(),
        "departements": fetch_departements(),
        "communes": fetch_communes(),
    }

    for name, df in datasets.items():
        blob_path = f"{prefix}/{partition}/{name}.parquet"
        upload_dataframe_as_parquet(df, Config.RAW_BUCKET, blob_path)

    logger.info("Ingestion Geo terminée.")


if __name__ == "__main__":
    main()

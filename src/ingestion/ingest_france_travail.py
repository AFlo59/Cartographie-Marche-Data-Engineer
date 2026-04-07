#!/usr/bin/env python3
"""
Ingestion — API France Travail (offres d'emploi)
Source    : https://api.francetravail.io/partenaire/offresdemploi/v2/offres/search
Schedule  : quotidien — 0 6 * * *
Output    : raw/france_travail/dt=YYYY-MM-DD/offres.parquet
Idempotent : écrasement du fichier du jour (même chemin GCS)

Stratégie de collecte :
  - Boucle sur 101 départements × 3 codes ROME (M1811, M1805, M1810)
  - Pagination via paramètre `range` (max 150/page, plafond API 3 000/combo)
  - Token OAuth2 obtenu une fois, réutilisé pour toute la session
  - Retry exponentiel sur 429 / 5xx
  - Déduplication finale par id d'offre
"""
import os
import sys
import time
from datetime import datetime, timezone

import pandas as pd
import requests
from typing import Optional

sys.path.insert(0, os.path.dirname(__file__))

from utils.config import Config
from utils.gcs import upload_dataframe_as_parquet
from utils.logging_config import get_logger

logger = get_logger("ingest_france_travail")

# ---------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------
_TOKEN_URL = (
    "https://entreprise.francetravail.fr/connexion/oauth2/access_token"
    "?realm=/partenaire"
)
_SEARCH_URL = f"{Config.FT_API_BASE}/offres/search"
_SCOPE = "api_offresdemploiv2 o2dsoffre"

_ROME_CODES = ["M1811", "M1805", "M1810"]

_DEPARTEMENTS = (
    [f"{i:02d}" for i in range(1, 20)]
    + ["2A", "2B"]
    + [f"{i:02d}" for i in range(21, 96)]
    + ["971", "972", "973", "974", "976"]
)

_PAGE_SIZE = 150       # max autorisé par l'API
_MAX_RETRIES = 3
_BACKOFF_BASE = 2      # secondes, exponentiel
_RATE_LIMIT_PAUSE = 1  # pause minimale entre requêtes (secondes)

# Champs à conserver depuis la réponse API
_FIELDS = [
    "id",
    "intitule",
    "description",
    "dateCreation",
    "lieuTravail.codePostal",
    "lieuTravail.commune",
    "lieuTravail.libelle",
    "entreprise.nom",
    "entreprise.numeroSiret",
    "salaire.libelle",
    "salaire.complement1",
    "typeContrat",
    "typeContratLibelle",
    "codeROME",
    "appellationlibelle",
    "experienceExige",
    "qualificationCode",
]


# ---------------------------------------------------------------------------
# OAuth2
# ---------------------------------------------------------------------------
def get_token() -> str:
    resp = requests.post(
        _TOKEN_URL,
        data={
            "grant_type": "client_credentials",
            "client_id": Config.ft_client_id(),
            "client_secret": Config.ft_client_secret(),
            "scope": _SCOPE,
        },
        timeout=30,
    )
    resp.raise_for_status()
    token = resp.json()["access_token"]
    logger.info("Token OAuth2 France Travail obtenu.")
    return token


# ---------------------------------------------------------------------------
# Requête avec retry
# ---------------------------------------------------------------------------
def _request_with_retry(
    session: requests.Session, url: str, params: dict
) -> Optional[requests.Response]:
    for attempt in range(_MAX_RETRIES):
        resp = session.get(url, params=params, timeout=30)

        # Lecture du rate limiting
        remaining = resp.headers.get("X-RateLimit-Remaining")
        if remaining is not None and int(remaining) < 5:
            logger.warning(f"Rate limit bas ({remaining} restantes) — pause 10s")
            time.sleep(10)

        if resp.status_code in (200, 206):
            return resp
        if resp.status_code == 204:
            return None  # aucun résultat
        if resp.status_code in (429, 500, 502, 503, 504):
            wait = _BACKOFF_BASE ** attempt
            logger.warning(
                f"HTTP {resp.status_code} — retry {attempt + 1}/{_MAX_RETRIES} dans {wait}s"
            )
            time.sleep(wait)
            continue
        # 400 / 401 / autres : pas la peine de retry
        logger.error(f"HTTP {resp.status_code} sur {url} params={params}: {resp.text[:200]}")
        return None

    logger.error(f"Abandon après {_MAX_RETRIES} tentatives : {url} params={params}")
    return None


# ---------------------------------------------------------------------------
# Collecte par département + ROME
# ---------------------------------------------------------------------------
def fetch_offres_for_combo(
    session: requests.Session, departement: str, rome: str
) -> list[dict]:
    results: list[dict] = []
    start = 0

    while True:
        end = start + _PAGE_SIZE - 1
        params = {
            "departement": departement,
            "codeROME": rome,
            "range": f"{start}-{end}",
        }
        resp = _request_with_retry(session, _SEARCH_URL, params)
        time.sleep(_RATE_LIMIT_PAUSE)

        if resp is None:
            break

        data = resp.json()
        batch = data.get("resultats", [])
        if not batch:
            break

        results.extend(batch)

        # Content-Range: offres 0-149/350
        content_range = resp.headers.get("Content-Range", "")
        try:
            total = int(content_range.split("/")[-1])
        except (ValueError, IndexError):
            total = len(results)

        if start + _PAGE_SIZE >= total or len(batch) < _PAGE_SIZE:
            break
        start += _PAGE_SIZE

    return results


# ---------------------------------------------------------------------------
# Normalisation d'un enregistrement
# ---------------------------------------------------------------------------
def _flatten(offre: dict) -> dict:
    flat: dict = {}
    for field in _FIELDS:
        parts = field.split(".")
        val = offre
        for p in parts:
            val = val.get(p) if isinstance(val, dict) else None
        flat[field.replace(".", "_")] = val
    return flat


# ---------------------------------------------------------------------------
# Point d'entrée
# ---------------------------------------------------------------------------
def main() -> None:
    token = get_token()
    session = requests.Session()
    session.headers.update({"Authorization": f"Bearer {token}"})

    all_offres: list[dict] = []
    total_combos = len(_DEPARTEMENTS) * len(_ROME_CODES)
    combo_idx = 0

    for dept in _DEPARTEMENTS:
        for rome in _ROME_CODES:
            combo_idx += 1
            offres = fetch_offres_for_combo(session, dept, rome)
            logger.info(
                f"[{combo_idx}/{total_combos}] dept={dept} rome={rome} → {len(offres)} offres"
            )
            all_offres.extend(offres)

    if not all_offres:
        logger.warning("Aucune offre récupérée — fichier Parquet non créé.")
        return

    # Normalisation + déduplication par id
    df = pd.DataFrame([_flatten(o) for o in all_offres])
    before = len(df)
    df.drop_duplicates(subset=["id"], keep="first", inplace=True)
    logger.info(f"Total : {before:,} offres → {len(df):,} après déduplication")

    # Typage
    df["dateCreation"] = pd.to_datetime(df["dateCreation"], errors="coerce", utc=True)

    partition = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    blob_path = f"{Config.FT_PREFIX.rstrip('/')}/dt={partition}/offres.parquet"
    upload_dataframe_as_parquet(df, Config.RAW_BUCKET, blob_path)

    logger.info(f"Ingestion France Travail terminée — {len(df):,} offres.")


if __name__ == "__main__":
    main()

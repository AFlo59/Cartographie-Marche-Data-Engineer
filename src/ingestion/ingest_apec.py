#!/usr/bin/env python3
from __future__ import annotations

"""
Ingestion — APEC offres d'emploi via API JSON interne
Source    : POST https://www.apec.fr/cms/webservices/rechercheOffre
Schedule  : hebdomadaire — récupère les offres publiées sur les 7 derniers jours
Output    : raw/apec/dt=YYYY-MM-DD/offres.parquet
Idempotent : écrasement du fichier du jour (même chemin GCS)

Stratégie :
  - L'API JSON interne APEC (Angular frontend) retourne des données structurées sans scraping HTML.
  - Pagination via le champ `startIndex` du body POST.
  - Aucun stockage persistant dans le conteneur ; upload direct BytesIO → GCS.
"""

import math
import os
import random
import re
import sys
import time
from datetime import datetime, timezone
from urllib.parse import urljoin

import pandas as pd
import requests

sys.path.insert(0, os.path.dirname(__file__))

from utils.config import Config  # noqa: E402
from utils.gcs import upload_dataframe_as_parquet  # noqa: E402
from utils.logging_config import get_logger  # noqa: E402

logger = get_logger("ingest_apec")

# ── Endpoints ────────────────────────────────────────────────────────────────
_API_SEARCH = "/cms/webservices/rechercheOffre"
_DETAIL_PATH_PREFIX = "/candidat/recherche-emploi.html/emploi/detail-offre/"

# ── Filtres de recherche ──────────────────────────────────────────────────────
_DEFAULT_TYPES_CONVENTION = [143684, 143685, 143686, 143687]
_DEFAULT_SECTEUR = 101753          # Activités informatiques
_DEFAULT_ANCIENNETE = 101851       # 7 derniers jours
_DEFAULT_SALAIRE_MIN = 20          # k€
_DEFAULT_SALAIRE_MAX = 200         # k€
_DEFAULT_PAGE_SIZE = 50            # max 50 par page via l'API
_DEFAULT_SORT_TYPE = "DATE"
_DEFAULT_SORT_DIR = "DESCENDING"

# ── Nomenclature typeContrat (extraite du bundle Angular APEC) ────────────────
_TYPE_CONTRAT: dict[int, str] = {
    101887: "CDD",
    101888: "CDI",
    597171: "Stage",
    101930: "Intérim",
    20053: "Alternance",
    101889: "Mission intérim",
    597141: "CDI intérimaire",
    597137: "CDD alternance / apprentissage",
}

# ── HTTP ──────────────────────────────────────────────────────────────────────
_MAX_RETRIES = 4
_BACKOFF_BASE = 2
_PAGE_DELAY_SECONDS = (0.3, 0.8)   # délai inter-pages : API JSON, pas de HTML à parser
_REQUEST_TIMEOUT = 30

_USER_AGENTS = [
    (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/135.0.0.0 Safari/537.36"
    ),
    (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/134.0.0.0 Safari/537.36"
    ),
    (
        "Mozilla/5.0 (X11; Linux x86_64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/134.0.0.0 Safari/537.36"
    ),
]


def _sleep(interval: tuple[float, float]) -> None:
    time.sleep(random.uniform(*interval))


def _new_session() -> requests.Session:
    """Session avec headers JSON réalistes + warm-up homepage pour obtenir les cookies."""
    session = requests.Session()
    session.headers.update(
        {
            "User-Agent": random.choice(_USER_AGENTS),
            "Accept-Language": "fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7",
            "Accept-Encoding": "gzip, deflate, br",
            "Connection": "keep-alive",
        }
    )

    # Warm-up : visite homepage pour établir les cookies de session
    try:
        session.headers["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        r = session.get(Config.APEC_BASE_URL, timeout=_REQUEST_TIMEOUT)
        if r.status_code == 200:
            logger.debug("Warm-up homepage OK (cookies: %s)", list(session.cookies.keys()))
        else:
            logger.warning("Warm-up homepage HTTP %s", r.status_code)
    except requests.RequestException as exc:
        logger.warning("Warm-up homepage failed (%s) — continuing", exc)

    _sleep((0.5, 1.5))

    # Bascule vers headers XHR pour les appels API JSON
    session.headers.update(
        {
            "Accept": "application/json, text/plain, */*",
            "Content-Type": "application/json",
            "Referer": urljoin(Config.APEC_BASE_URL, "/candidat/recherche-emploi.html/emploi"),
            "Origin": Config.APEC_BASE_URL,
            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "cors",
            "sec-fetch-site": "same-origin",
        }
    )
    return session


def _post_with_retry(
    session: requests.Session,
    path: str,
    body: dict,
) -> dict | None:
    url = urljoin(Config.APEC_BASE_URL, path)

    for attempt in range(_MAX_RETRIES):
        try:
            response = session.post(url, json=body, timeout=_REQUEST_TIMEOUT)
        except requests.RequestException as exc:
            wait = _BACKOFF_BASE ** attempt
            logger.warning(
                "APEC API request error (%s) attempt %s/%s; retry in %ss",
                exc, attempt + 1, _MAX_RETRIES, wait,
            )
            time.sleep(wait)
            continue

        if response.status_code == 200:
            try:
                data = response.json()
                _sleep(_PAGE_DELAY_SECONDS)
                return data
            except ValueError as exc:
                logger.error("APEC API non-JSON response on %s: %s", url, exc)
                return None

        if response.status_code in {429, 500, 502, 503, 504}:
            jitter = random.uniform(0.5, 1.5)
            wait = (_BACKOFF_BASE ** attempt) * jitter
            if response.status_code == 429:
                wait = max(wait, 10.0)
            session.headers["User-Agent"] = random.choice(_USER_AGENTS)
            logger.warning(
                "HTTP %s on %s attempt %s/%s; retry in %.1fs",
                response.status_code, url, attempt + 1, _MAX_RETRIES, wait,
            )
            time.sleep(wait)
            continue

        logger.error(
            "HTTP %s on %s body=%s: %s",
            response.status_code, url, body, response.text[:300],
        )
        return None

    logger.error("Abandon after %s attempts on %s", _MAX_RETRIES, url)
    return None


def _build_body(start_index: int) -> dict:
    return {
        "typeClient": "CADRE",
        "typesConvention": _DEFAULT_TYPES_CONVENTION,
        "secteursActivite": [_DEFAULT_SECTEUR],
        "anciennetePublication": _DEFAULT_ANCIENNETE,
        "salaireMinimum": _DEFAULT_SALAIRE_MIN,
        "salaireMaximum": _DEFAULT_SALAIRE_MAX,
        "sorts": [{"type": _DEFAULT_SORT_TYPE, "direction": _DEFAULT_SORT_DIR}],
        "pagination": {"range": _DEFAULT_PAGE_SIZE, "startIndex": start_index},
        "activeFiltre": True,
    }


def _clean_text(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = re.sub(r"\s+", " ", str(value).replace("\xa0", " ")).strip()
    return normalized or None


def _parse_date(value: str | None) -> pd.Timestamp:
    if not value:
        return pd.NaT
    return pd.to_datetime(value, errors="coerce", utc=True)


def _split_location(location_text: str | None) -> tuple[str | None, str | None]:
    cleaned = _clean_text(location_text)
    if not cleaned:
        return None, None
    match = re.match(r"(?P<commune>.+?)\s*-\s*(?P<departement>[0-9]{2,3}[A-Z]?)$", cleaned)
    if not match:
        return cleaned, None
    return match.group("commune"), match.group("departement")


def _parse_offer(raw: dict) -> dict:
    """Transforme un item brut de l'API APEC en dict normalisé."""
    offre_id = str(raw.get("numeroOffre") or raw.get("id") or "")
    commune, departement = _split_location(raw.get("lieuTexte"))
    type_contrat_id = raw.get("typeContrat")
    return {
        "apec_id": offre_id or None,
        "detail_url": urljoin(
            Config.APEC_BASE_URL,
            _DETAIL_PATH_PREFIX + offre_id,
        ) if offre_id else None,
        "job_title": _clean_text(raw.get("intitule")),
        "company_name": _clean_text(raw.get("nomCommercial")),
        "salary_text": _clean_text(raw.get("salaireTexte")),
        "contract_type": _TYPE_CONTRAT.get(type_contrat_id, str(type_contrat_id) if type_contrat_id else None),
        "location_text": _clean_text(raw.get("lieuTexte")),
        "commune": commune,
        "departement": departement,
        "latitude": raw.get("latitude"),
        "longitude": raw.get("longitude"),
        "published_at_text": raw.get("datePublication"),
        "published_at": _parse_date(raw.get("datePublication")),
        "validated_at": _parse_date(raw.get("dateValidation")),
        "job_description_preview": _clean_text(raw.get("texteOffre")),
        "logo_url": (
            urljoin(Config.APEC_BASE_URL, raw["urlLogo"])
            if raw.get("urlLogo")
            else None
        ),
        "secteur_activite_id": raw.get("secteurActivite"),
        "secteur_activite_parent_id": raw.get("secteurActiviteParent"),
        "oqa": raw.get("indicateurOqa"),
        "confidentielle": raw.get("offreConfidentielle"),
        "faible_candidature": raw.get("indicateurFaibleCandidature"),
    }


def _collect_offers(session: requests.Session) -> list[dict]:
    """Collecte toutes les offres en paginant via l'API JSON."""
    # Première page : détermine le total
    data = _post_with_retry(session, _API_SEARCH, _build_body(0))
    if not data:
        logger.warning("Aucune réponse de l'API APEC sur la première page.")
        return []

    total_count = data.get("totalCount", 0)
    raw_results = data.get("resultats") or []
    if not raw_results:
        logger.warning("API APEC : aucun résultat sur la première page.")
        return []

    total_pages = max(1, math.ceil(total_count / _DEFAULT_PAGE_SIZE))
    logger.info(
        "APEC page 1/%s — %s offres reçues, total annoncé %s",
        total_pages, len(raw_results), total_count,
    )

    offers = [_parse_offer(r) for r in raw_results]
    seen_ids = {o["apec_id"] for o in offers if o["apec_id"]}

    for page in range(1, total_pages):
        start_index = page * _DEFAULT_PAGE_SIZE
        data = _post_with_retry(session, _API_SEARCH, _build_body(start_index))
        if not data:
            logger.warning("Page APEC %s vide (pas de réponse); arrêt.", page)
            break

        raw_results = data.get("resultats") or []
        if not raw_results:
            logger.warning("Page APEC %s sans résultats; arrêt.", page)
            break

        added = 0
        for raw in raw_results:
            parsed = _parse_offer(raw)
            offer_id = parsed.get("apec_id")
            if offer_id and offer_id in seen_ids:
                continue
            if offer_id:
                seen_ids.add(offer_id)
            offers.append(parsed)
            added += 1

        logger.info(
            "APEC page %s/%s — %s reçues, %s nouvelles, cumul=%s",
            page + 1, total_pages, len(raw_results), added, len(offers),
        )

        if added == 0:
            logger.warning("Plus aucune nouvelle offre page %s; arrêt anticipé.", page)
            break

    return offers


def _build_dataframe(offers: list[dict]) -> pd.DataFrame:
    scraped_at = datetime.now(timezone.utc)
    df = pd.DataFrame(offers)
    if df.empty:
        return df

    if "apec_id" in df.columns:
        df.drop_duplicates(subset=["apec_id"], keep="first", inplace=True)

    for col in ("published_at", "validated_at"):
        if col in df.columns:
            df[col] = pd.to_datetime(df[col], errors="coerce", utc=True)

    df["scraped_at"] = scraped_at
    df["source_name"] = "apec"
    df["search_url"] = urljoin(Config.APEC_BASE_URL, _API_SEARCH)
    df["filters_types_convention"] = ",".join(str(v) for v in _DEFAULT_TYPES_CONVENTION)
    df["filters_secteur_activite"] = _DEFAULT_SECTEUR
    df["filters_anciennete_publication"] = _DEFAULT_ANCIENNETE
    df["filters_salaire_min"] = _DEFAULT_SALAIRE_MIN
    df["filters_salaire_max"] = _DEFAULT_SALAIRE_MAX

    ordered_columns = [
        "apec_id",
        "job_title",
        "company_name",
        "salary_text",
        "contract_type",
        "commune",
        "departement",
        "location_text",
        "latitude",
        "longitude",
        "published_at",
        "validated_at",
        "job_description_preview",
        "detail_url",
        "logo_url",
        "secteur_activite_id",
        "secteur_activite_parent_id",
        "oqa",
        "confidentielle",
        "faible_candidature",
        "source_name",
        "search_url",
        "filters_types_convention",
        "filters_secteur_activite",
        "filters_anciennete_publication",
        "filters_salaire_min",
        "filters_salaire_max",
        "scraped_at",
    ]
    remaining = [c for c in df.columns if c not in ordered_columns]
    return df[[c for c in ordered_columns if c in df.columns] + remaining]


def main() -> None:
    if not Config.RAW_BUCKET:
        raise ValueError("INGESTION_RAW_BUCKET est requis pour l'ingestion APEC.")

    session = _new_session()
    offers = _collect_offers(session)
    if not offers:
        logger.warning("Aucune offre APEC récupérée — fichier Parquet non créé.")
        return

    df = _build_dataframe(offers)
    if df.empty:
        logger.warning("DataFrame APEC vide après normalisation — fichier Parquet non créé.")
        return

    partition = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    blob_path = f"{Config.APEC_PREFIX.rstrip('/')}/dt={partition}/offres.parquet"
    upload_dataframe_as_parquet(df, Config.RAW_BUCKET, blob_path)
    logger.info("Ingestion APEC terminée — %s offres.", len(df))


if __name__ == "__main__":
    main()

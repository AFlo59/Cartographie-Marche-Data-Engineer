"""
Configuration et résolution des secrets.
Priorité : variable d'environnement → Secret Manager (Cloud Run).

En local : charge automatiquement le .env trouvé dans le répertoire courant
ou dans les parents (sans effet si les vars sont déjà injectées par Cloud Run).
"""

import os
from pathlib import Path
from typing import Optional

# Chargement .env local — silencieux si python-dotenv absent ou .env introuvable
try:
    from dotenv import load_dotenv

    # Cherche src/ingestion/.env d'abord, puis remonte jusqu'au .env racine
    _env_file = next(
        (
            p / ".env"
            for p in [
                Path(__file__).parent.parent,
                Path(__file__).parent.parent.parent.parent,
            ]
            if (p / ".env").is_file()
        ),
        None,
    )
    if _env_file:
        load_dotenv(
            _env_file, override=False
        )  # override=False : les vars déjà présentes priment
except ImportError:
    pass

from utils.logging_config import get_logger

logger = get_logger(__name__)


def _get_secret(secret_id: str) -> str:
    # import tardif — évite l'initialisation si inutile
    from google.cloud import secretmanager

    project_id = (
        os.getenv("GCP_PROJECT_ID", "").strip()
        or os.getenv("GOOGLE_CLOUD_PROJECT", "").strip()
    )
    if not project_id:
        raise ValueError(
            "GCP_PROJECT_ID (ou GOOGLE_CLOUD_PROJECT) est requis pour lire Secret Manager."
        )

    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8").strip()


def resolve(env_var: str, secret_name_env: Optional[str] = None) -> str:
    """Retourne la valeur de env_var, ou lit le secret correspondant si vide."""
    value = os.getenv(env_var, "").strip()
    if value:
        return value
    secret_id = os.getenv(secret_name_env, env_var) if secret_name_env else env_var
    logger.info(f"{env_var} absent des env vars — lecture Secret Manager ({secret_id})")
    return _get_secret(secret_id)


class Config:
    GCP_PROJECT_ID: str = (
        os.getenv("GCP_PROJECT_ID", "").strip()
        or os.getenv("GOOGLE_CLOUD_PROJECT", "").strip()
    )
    GCP_REGION: str = os.getenv("GCP_REGION", "europe-west1")

    RAW_BUCKET: str = os.getenv("INGESTION_RAW_BUCKET", "").strip()
    FT_PREFIX: str = os.getenv("INGESTION_FRANCE_TRAVAIL_PREFIX", "raw/france_travail/")
    SIRENE_PREFIX: str = os.getenv("INGESTION_SIRENE_PREFIX", "raw/sirene/")
    GEO_PREFIX: str = os.getenv("INGESTION_GEO_PREFIX", "raw/geo/")
    APEC_PREFIX: str = os.getenv("INGESTION_APEC_PREFIX", "raw/apec/")

    FT_API_BASE: str = os.getenv(
        "FRANCE_TRAVAIL_API_BASE_URL",
        "https://api.francetravail.io/partenaire/offresdemploi/v2",
    )
    GEO_API_BASE: str = os.getenv("GEO_API_BASE_URL", "https://geo.api.gouv.fr")
    APEC_BASE_URL: str = os.getenv("APEC_BASE_URL", "https://www.apec.fr")
    SIRENE_DATASET_SLUG: str = (
        "base-sirene-des-entreprises-et-de-leurs-etablissements-siren-siret"
    )

    @staticmethod
    def ft_client_id() -> str:
        return resolve("FT_CLIENT_ID", "FT_CLIENT_ID_SECRET_NAME")

    @staticmethod
    def ft_client_secret() -> str:
        return resolve("FT_CLIENT_SECRET", "FT_CLIENT_SECRET_SECRET_NAME")

    @staticmethod
    def datagouv_api_key() -> str:
        return resolve("DATAGOUV_API_KEY", "DATAGOUV_API_KEY_SECRET_NAME")

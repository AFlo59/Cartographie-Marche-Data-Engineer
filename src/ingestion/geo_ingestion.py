import json
import os
from datetime import datetime, timezone

import pandas as pd
import requests
from google.cloud import storage
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

GEO_API_BASE_URL = os.environ.get("GEO_API_BASE_URL", "https://geo.api.gouv.fr").rstrip("/")

BUCKET_NAME = os.environ.get("TF_VAR_raw_bucket_name")
GEO_PREFIX = os.environ.get("TF_VAR_ingestion_geo_prefix", "raw/geo/")

REQUEST_TIMEOUT = int(os.environ.get("GEO_API_TIMEOUT_SECONDS", "60"))

REGIONS_FIELDS = "code,nom"
DEPARTEMENTS_FIELDS = "code,nom,codeRegion"
COMMUNES_FIELDS = "code,nom,codeDepartement,codeRegion,codesPostaux,population,centre"


def build_session() -> requests.Session:
    session = requests.Session()

    retry = Retry(
        total=5,
        connect=5,
        read=5,
        backoff_factor=1.5,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["GET"],
        raise_on_status=False,
    )

    adapter = HTTPAdapter(max_retries=retry)
    session.mount("https://", adapter)
    session.mount("http://", adapter)
    return session


def fetch_json(session: requests.Session, endpoint: str, params: dict | None = None) -> list[dict]:
    url = f"{GEO_API_BASE_URL}{endpoint}"
    print(f"⬇️ Requête API Géo: {url} | params={params}")

    response = session.get(url, params=params, timeout=REQUEST_TIMEOUT)
    response.raise_for_status()

    data = response.json()
    if not isinstance(data, list):
        raise ValueError(f"Réponse inattendue pour {url}: type={type(data)}")
    return data


def normalize_prefix(prefix: str) -> str:
    return prefix if prefix.endswith("/") else f"{prefix}/"


def extract_lon_lat(centre: dict | None) -> tuple[float | None, float | None]:
    if not centre or not isinstance(centre, dict):
        return None, None

    coordinates = centre.get("coordinates")
    if not coordinates or not isinstance(coordinates, list) or len(coordinates) < 2:
        return None, None

    return coordinates[0], coordinates[1]


def to_dataframe_regions(regions: list[dict]) -> pd.DataFrame:
    return pd.DataFrame(regions)


def to_dataframe_departements(departements: list[dict]) -> pd.DataFrame:
    return pd.DataFrame(departements)


def to_dataframe_communes(communes: list[dict]) -> pd.DataFrame:
    df = pd.DataFrame(communes)

    if "centre" in df.columns:
        lon_lat = df["centre"].apply(extract_lon_lat)
        df["longitude"] = lon_lat.apply(lambda x: x[0])
        df["latitude"] = lon_lat.apply(lambda x: x[1])
        df = df.drop(columns=["centre"])

    return df


def upload_dataframe_to_gcs_parquet(bucket_name: str, gcs_path: str, dataframe: pd.DataFrame) -> None:
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(gcs_path)

    local_tmp_path = f"/tmp/{os.path.basename(gcs_path)}"
    dataframe.to_parquet(local_tmp_path, index=False)

    blob.upload_from_filename(local_tmp_path, content_type="application/octet-stream")
    os.remove(local_tmp_path)

    print(f"✅ Déposé dans gs://{bucket_name}/{gcs_path}")


def upload_manifest_to_gcs(bucket_name: str, gcs_path: str, payload: dict) -> None:
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(gcs_path)

    body = json.dumps(payload, ensure_ascii=False, indent=2)
    blob.upload_from_string(body, content_type="application/json; charset=utf-8")

    print(f"✅ Manifest déposé dans gs://{bucket_name}/{gcs_path}")


def ingest_geo() -> None:
    if not BUCKET_NAME:
        raise ValueError(
            "Le nom du bucket GCS doit être défini dans la variable d'environnement TF_VAR_raw_bucket_name"
        )

    session = build_session()
    prefix = normalize_prefix(GEO_PREFIX)

    now = datetime.now(timezone.utc)
    year = now.strftime("%Y")
    month = now.strftime("%m")
    day = now.strftime("%d")
    timestamp = now.strftime("%Y%m%dT%H%M%SZ")

    base_path = f"{prefix}{year}/{month}/{day}/"

    regions_raw = fetch_json(
        session,
        "/regions",
        params={"fields": REGIONS_FIELDS},
    )
    departements_raw = fetch_json(
        session,
        "/departements",
        params={"fields": DEPARTEMENTS_FIELDS},
    )
    communes_raw = fetch_json(
        session,
        "/communes",
        params={"fields": COMMUNES_FIELDS},
    )

    regions_df = to_dataframe_regions(regions_raw)
    departements_df = to_dataframe_departements(departements_raw)
    communes_df = to_dataframe_communes(communes_raw)

    regions_path = f"{base_path}regions_{timestamp}.parquet"
    departements_path = f"{base_path}departements_{timestamp}.parquet"
    communes_path = f"{base_path}communes_{timestamp}.parquet"
    manifest_path = f"{base_path}manifest_{timestamp}.json"

    upload_dataframe_to_gcs_parquet(BUCKET_NAME, regions_path, regions_df)
    upload_dataframe_to_gcs_parquet(BUCKET_NAME, departements_path, departements_df)
    upload_dataframe_to_gcs_parquet(BUCKET_NAME, communes_path, communes_df)

    manifest = {
        "source": "geo.api.gouv.fr",
        "base_url": GEO_API_BASE_URL,
        "ingested_at_utc": now.isoformat(),
        "bucket": BUCKET_NAME,
        "prefix": prefix,
        "format": "parquet",
        "files": {
            "regions": {
                "path": regions_path,
                "records": len(regions_df),
                "endpoint": "/regions",
                "fields": list(regions_df.columns),
            },
            "departements": {
                "path": departements_path,
                "records": len(departements_df),
                "endpoint": "/departements",
                "fields": list(departements_df.columns),
            },
            "communes": {
                "path": communes_path,
                "records": len(communes_df),
                "endpoint": "/communes",
                "fields": list(communes_df.columns),
            },
        },
    }

    upload_manifest_to_gcs(BUCKET_NAME, manifest_path, manifest)

    print("🎯 Ingestion API Géo terminée")
    print(f"   Régions      : {len(regions_df)}")
    print(f"   Départements : {len(departements_df)}")
    print(f"   Communes     : {len(communes_df)}")


if __name__ == "__main__":
    ingest_geo()
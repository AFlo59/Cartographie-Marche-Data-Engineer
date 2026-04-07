"""
Helpers d'upload vers GCS.
"""

import io

import pandas as pd
import requests
from google.cloud import storage

from utils.logging_config import get_logger

logger = get_logger(__name__)


def upload_dataframe_as_parquet(
    df: pd.DataFrame, bucket_name: str, blob_path: str
) -> None:
    """Sérialise un DataFrame en Parquet et l'écrase sur GCS (idempotent)."""
    client = storage.Client()
    blob = client.bucket(bucket_name).blob(blob_path)
    buffer = io.BytesIO()
    df.to_parquet(buffer, index=False, engine="pyarrow")
    buffer.seek(0)
    blob.upload_from_file(buffer, content_type="application/octet-stream")
    logger.info(f"Uploaded {len(df):,} rows → gs://{bucket_name}/{blob_path}")


def stream_upload_to_gcs(
    response: requests.Response,
    bucket_name: str,
    blob_path: str,
    chunk_size: int = 256 * 1024 * 1024,  # 256 Mo
) -> int:
    """
    Stream un requests.Response vers GCS sans charger le contenu en mémoire.
    Utilise un upload resumable (blob.open). Retourne le nombre d'octets transférés.
    """
    client = storage.Client()
    blob = client.bucket(bucket_name).blob(blob_path)
    total = 0
    with blob.open("wb", chunk_size=chunk_size) as gcs_file:
        for chunk in response.iter_content(chunk_size=chunk_size):
            if chunk:
                gcs_file.write(chunk)
                total += len(chunk)
    logger.info(f"Streamed {total / 1e6:.1f} MB → gs://{bucket_name}/{blob_path}")
    return total

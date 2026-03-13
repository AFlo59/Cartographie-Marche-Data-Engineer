import argparse
import sys

from .sirene_ingestion import ingest_sirene
from .geo_ingestion import ingest_geo


def main():
    parser = argparse.ArgumentParser(
        description="Lance l'ingestion pour une source de données spécifique"
    )
    parser.add_argument(
        "--source",
        type=str,
        required=True,
        help="Nom de la source à ingérer (ex: sirene, geo)",
    )
    args = parser.parse_args()

    source = args.source.lower()

    if source == "sirene":
        ingest_sirene()
    elif source == "geo":
        ingest_geo()
    else:
        print(f"Source inconnue : {args.source}")
        print("Sources supportées : sirene, geo")
        sys.exit(1)


if __name__ == "__main__":
    main()
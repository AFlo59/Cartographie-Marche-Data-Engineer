import argparse
import sys

from sirene_ingestion import ingest_sirene
from geo_ingestion import ingest_geo
from ingest_france_travail import main as ingest_france_travail


def main():
    parser = argparse.ArgumentParser(
        description="Lance l'ingestion pour une source de données spécifique"
    )
    parser.add_argument(
        "--source",
        type=str,
        required=True,
        help="Nom de la source à ingérer (ex: sirene, geo, france_travail)",
    )
    args = parser.parse_args()

    source = args.source.lower()

    if source == "sirene":
        ingest_sirene()
    elif source == "geo":
        ingest_geo()
    elif source == "france_travail":
        ingest_france_travail()
    else:
        print(f"Source inconnue : {args.source}")
        print("Sources supportées : sirene, geo, france_travail")
        sys.exit(1)


if __name__ == "__main__":
    main()
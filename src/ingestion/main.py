import argparse
import sys

try:
    from .ingest_france_travail import main as ingest_france_travail
    from .ingest_geo import main as ingest_geo
    from .ingest_sirene import ingest_sirene
except ImportError:
    from ingest_france_travail import main as ingest_france_travail
    from ingest_geo import main as ingest_geo
    from ingest_sirene import ingest_sirene


def main():
    parser = argparse.ArgumentParser(
        description="Lance l'ingestion pour une source de données spécifique"
    )
    parser.add_argument(
        "--source",
        type=str,
        required=True,
        help="Nom de la source à ingérer (ex: sirene, geo, france_travail, all)",
    )
    args = parser.parse_args()

    source = args.source.lower()

    if source == "sirene":
        ingest_sirene()
    elif source == "geo":
        ingest_geo()
    elif source == "france_travail":
        ingest_france_travail()
    elif source == "all":
        print("Lancement de toutes les ingestions...")
        ingest_sirene()
        ingest_geo()
        ingest_france_travail()
        print("Toutes les ingestions sont terminées.")
    else:
        print(f"Source inconnue : {args.source}")
        print("Sources supportées : sirene, geo, france_travail, all")
        sys.exit(1)


if __name__ == "__main__":
    main()

import argparse
import sys


def _run_source(source: str) -> None:
    if source == "sirene":
        try:
            from .ingest_sirene import ingest_sirene
        except ImportError:
            from ingest_sirene import ingest_sirene

        ingest_sirene()
        return

    if source == "geo":
        try:
            from .ingest_geo import main as ingest_geo
        except ImportError:
            from ingest_geo import main as ingest_geo

        ingest_geo()
        return

    if source == "france_travail":
        try:
            from .ingest_france_travail import main as ingest_france_travail
        except ImportError:
            from ingest_france_travail import main as ingest_france_travail

        ingest_france_travail()
        return

    if source == "all":
        print("Lancement de toutes les ingestions...")
        _run_source("sirene")
        _run_source("geo")
        _run_source("france_travail")
        print("Toutes les ingestions sont terminées.")
        return

    print(f"Source inconnue : {source}")
    print("Sources supportées : sirene, geo, france_travail, all")
    sys.exit(1)


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

    _run_source(source)


if __name__ == "__main__":
    main()

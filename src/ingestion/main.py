#launch ingestion for 3 sources - fornow only sirene
import argparse
import sys

from .sirene_ingestion import ingest_sirene

def main():
    parser = argparse.ArgumentParser(description="Lance l'ingestion pour une source de données spécifique")
    parser.add_argument("--source", type=str, required=True, help="Nom de la source à ingérer (ex: sirene)")
    args = parser.parse_args()

    if args.source == "sirene":
        ingest_sirene()
    else:
        print(f"Source inconnue : {args.source}")
        sys.exit(1)

if __name__ == "__main__":
    main()
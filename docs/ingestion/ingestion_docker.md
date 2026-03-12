# Guide commande docker pour script ingestion

Ce document contient des exemples pour lancer manuellement les scripts d'ingestion des données des api.

## Build le projet
```bash
docker compose build --no-cache ingestion-jobs
```

## Exécution des scripts

Attention aux noms des fichiers

```bash
docker compose run --rm ingestion-jobs python src/ingestion/ingestion_api_Geo.py
docker compose run --rm ingestion-jobs python src/ingestion/ingestion_api_France_Travail.py
docker compose run --rm ingestion-jobs python src/ingestion/ingestion_api_Sirene.py
```
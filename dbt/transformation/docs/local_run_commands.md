# Run dbt en local (sans Docker)

Ce guide couvre l'execution dbt depuis votre machine avec Python local.

## Prerequis

- Python 3.11+
- acces GCP configure (voir `gcp_manual_setup.md`)
- variables `.env` disponibles dans votre shell

## 1. Se placer dans le dossier dbt

```bash
cd dbt/transformation
```

## 2. Creer un environnement Python local

```bash
python -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

Sur Windows PowerShell :

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
```

## 3. Exporter les variables d'environnement

Option simple : charger manuellement les variables du `.env` racine dans votre terminal.

Variables minimales :

- `GCP_PROJECT_ID`
- `GCP_LOCATION`
- `DBT_BIGQUERY_DATASET`
- `DBT_TARGET`

Variable optionnelle :

- `DBT_BIGQUERY_PROJECT` (si vous voulez surcharger `GCP_PROJECT_ID`)

## 4. Verifier dbt

```bash
dbt --version
dbt debug --profiles-dir .
dbt parse --profiles-dir .
```

## 5. Executer les transformations

```bash
dbt run --profiles-dir .
dbt test --profiles-dir .
```

## 6. Documentation dbt

```bash
dbt docs generate --profiles-dir .
dbt docs serve --profiles-dir . --port 8080
```
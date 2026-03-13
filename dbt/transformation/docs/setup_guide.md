# Guide de setup dbt - point d'entree unique

Ce document est le point d'entree principal pour preparer et executer dbt (BigQuery) sans se perdre entre plusieurs fichiers.

## Objectif

Obtenir un projet dbt operationnel avec un ordre clair :

- setup manuel GCP une seule fois,
- setup du projet local,
- execution dbt en local,
- execution dbt via Docker.

## Regle d'usage

- Le dossier dbt est `dbt/transformation`.
- Les variables sont lues depuis le `.env` racine via Docker Compose.
- En execution locale, exporter les memes variables d'environnement avant de lancer dbt.
- Le profil dbt est dans `dbt/transformation/profiles.yml` et lit les variables avec `env_var()`.

## Ordre recommande

### 1. Setup manuel GCP en amont (one-shot)

Faire l'authentification et verifier l'acces BigQuery.

Guide : `gcp_manual_setup.md`

### 2. Setup du projet local

Verifier les fichiers dbt et variables du projet.

Points de controle :

- `dbt/transformation/dbt_project.yml`
- `dbt/transformation/profiles.yml`
- `.env` racine complete a partir de `.env.example`

### 3. Run dbt en local (sans Docker)

Utiliser un environnement Python local et executer dbt directement.

Guide : `local_run_commands.md`

### 4. Run dbt via Docker Compose

Utiliser le service `dbt` de `docker-compose.yml`.

Guide : `docker_run_commands.md`

## Parcours rapides

### Premier setup complet

1. `gcp_manual_setup.md`
2. verifier `.env` racine
3. `local_run_commands.md` (validation rapide)
4. `docker_run_commands.md` (execution reproductible)

### Developpement quotidien

1. synchroniser les variables `.env`
2. lancer `dbt parse` puis `dbt run` et `dbt test`
3. preferer Docker si vous voulez un environnement stable entre machines

## Cartographie des docs

- `setup_guide.md` : point d'entree et ordre global
- `gcp_manual_setup.md` : prerequis manuels cote GCP
- `local_run_commands.md` : commandes dbt sans Docker
- `docker_run_commands.md` : commandes dbt avec Docker Compose
- `dbt_setup.md` : resume rapide

## Regle de maintenance documentaire

- Les prerequis GCP one-shot restent dans `gcp_manual_setup.md`.
- Les commandes recurrentes locales restent dans `local_run_commands.md`.
- Les commandes recurrentes Docker restent dans `docker_run_commands.md`.
- Toute evolution de `profiles.yml` ou `dbt_project.yml` doit etre reportee ici.
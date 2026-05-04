# Guide de setup dbt — point d'entrée unique

Ce document est le point d'entrée principal pour préparer et exécuter dbt (BigQuery) sans se perdre entre plusieurs fichiers.

## Objectif

Obtenir un projet dbt opérationnel avec un ordre clair :

- setup manuel GCP une seule fois,
- setup du projet local,
- exécution dbt en local,
- exécution dbt via Docker.

## Règle d'usage

- Le dossier dbt est `dbt/transformation`.
- Les variables sont lues depuis le `.env` racine via Docker Compose.
- En exécution locale, exporter les mêmes variables d'environnement avant de lancer dbt.
- Le profil dbt est dans `dbt/transformation/profiles.yml` et lit les variables avec `env_var()`.
- Convention de target : `DBT_TARGET=dev` en local (machine/Docker local) et `DBT_TARGET=ci` dans GitHub Actions.

## Ordre recommandé

### 1. Setup manuel GCP en amont (one-shot)

Faire l'authentification et vérifier l'accès BigQuery.

Guide : `gcp_manual_setup.md`

### 2. Setup du projet local

Vérifier les fichiers dbt et variables du projet.

Points de contrôle :

- `dbt/transformation/dbt_project.yml`
- `dbt/transformation/profiles.yml`
- `.env` racine complété à partir de `.env.example`

### 3. Run dbt en local (sans Docker)

Utiliser un environnement Python local et exécuter dbt directement.

Guide : `local_run_commands.md`

### 4. Run dbt via Docker Compose

Utiliser le service `dbt` de `docker-compose.yml`.

Guide : `docker_run_commands.md`

## Parcours rapides

### Premier setup complet

1. `gcp_manual_setup.md`
2. vérifier `.env` racine
3. `local_run_commands.md` (validation rapide)
4. `docker_run_commands.md` (exécution reproductible)

### Développement quotidien

1. synchroniser les variables `.env`
2. lancer `dbt parse` puis `dbt run` et `dbt test`
3. préférer Docker si vous voulez un environnement stable entre machines

## Cartographie des docs

- `setup_guide.md` : point d'entrée et ordre global
- `gcp_manual_setup.md` : prérequis manuels côté GCP
- `local_run_commands.md` : commandes dbt sans Docker
- `docker_run_commands.md` : commandes dbt avec Docker Compose
- `dbt_setup.md` : résumé rapide

## Règle de maintenance documentaire

- Les prérequis GCP one-shot restent dans `gcp_manual_setup.md`.
- Les commandes récurrentes locales restent dans `local_run_commands.md`.
- Les commandes récurrentes Docker restent dans `docker_run_commands.md`.
- Toute évolution de `profiles.yml` ou `dbt_project.yml` doit être reportée ici.

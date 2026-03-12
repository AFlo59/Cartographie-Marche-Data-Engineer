# Guide de setup — point d'entrée unique

Ce document est le point d'entrée principal pour monter l'infrastructure du projet sans se perdre entre plusieurs fichiers.

## Objectif

Obtenir un projet GCP prêt, une exécution Terraform opérationnelle, puis un mode de déploiement clair selon le contexte :

- setup manuel GCP une seule fois,
- exécution infra via Docker,
- ou exécution infra en installation locale,
- avec des guides séparés pour les options avancées.

## Règle d'usage

- **Chemin principal de release/déploiement dans le périmètre infra actuel** : GitHub Actions via merge sur `main` pour `terraform plan/apply`.
- **Docker et terminal local** : utilisés surtout pour le développement, la validation, le debug et les tests manuels avant ouverture de PR.
- **Cloud Shell / setup GCP manuel** : utilisé pour les opérations one-shot d'initialisation et d'administration.

Note de périmètre :
- ce guide couvre l'infrastructure GCP actuelle (`storage`, `warehouse`, `compute`, `scheduler`, `secrets`, IAM associé),
- il ne remplace pas le backlog complet INFRA-09 côté qualité Python et dbt, encore partiellement à compléter.
- côté structure repo, le futur projet dbt est désormais attendu dans `dbt/transformation/` plutôt qu'avec un dossier racine `models/`.

## Ordre recommandé

### 1. Préparer GCP une seule fois

Commencer par le setup manuel GCP dans Cloud Shell :
- activation des APIs,
- création des service accounts,
- droits du compte de déploiement Terraform,
- vérifications de base.

Guide : [docs/platform/gcp_terminal_setup.md](docs/platform/gcp_terminal_setup.md)

### 2. Vérifier les rôles IAM

Pour savoir quel compte reçoit quel rôle, ce qui est déjà géré par Terraform, et ce qui doit rester manuel :

Guide : [docs/infra/iam_roles.md](docs/infra/iam_roles.md)

### 3. Charger les secrets runtime

Terraform crée les conteneurs Secret Manager, mais les valeurs réelles des secrets sont ajoutées manuellement.

Guide : [docs/platform/secret_manager_setup.md](docs/platform/secret_manager_setup.md)

### 4. Choisir un mode d'exécution Terraform

#### Option A — Docker recommandé

À privilégier si vous ne voulez pas installer Terraform et gcloud localement.

Guide : [docs/infra/docker_run_commands.md](docs/infra/docker_run_commands.md)

#### Option B — Installation locale

À utiliser si Terraform, gcloud et les dépendances sont déjà installés sur votre poste.

Guide : [docs/infra/manual_commands.md](docs/infra/manual_commands.md)

### 5. Configurer le déploiement CI GitHub Actions

Pour l'authentification GitHub vers GCP sans clé JSON, utiliser WIF. C'est le chemin cible de release et de déploiement automatique **de l'infrastructure Terraform** dans le périmètre actuel.

Guide : [docs/cicd/github_wif_setup.md](docs/cicd/github_wif_setup.md)

## Parcours rapides

### Premier setup complet

1. [Setup GCP manuel](docs/platform/gcp_terminal_setup.md)
2. [Revue IAM](docs/infra/iam_roles.md)
3. [Setup Secret Manager](docs/platform/secret_manager_setup.md)
4. [Exécution Docker](docs/infra/docker_run_commands.md)
5. [Setup WIF GitHub](docs/cicd/github_wif_setup.md)

### Travailler en local au quotidien

1. Vérifier `.env`
2. Choisir Docker ou installation locale
3. Lancer `validate` → `plan` → `apply`
4. Vérifier les ressources créées
5. En cas d'erreur `409 already exists`, suivre la section dédiée "Gérer une erreur 409" du guide local

Voir :
- [docs/infra/docker_run_commands.md](docs/infra/docker_run_commands.md)
- [docs/infra/manual_commands.md](docs/infra/manual_commands.md)

### Préparer la CI

1. Vérifier les rôles de `terraform-deployer-sa`
2. Vérifier le binding `iam.serviceAccountUser`
3. Configurer WIF
4. Vérifier le workflow GitHub Actions

Voir :
- [docs/infra/iam_roles.md](docs/infra/iam_roles.md)
- [docs/cicd/github_wif_setup.md](docs/cicd/github_wif_setup.md)

## Cartographie des docs

- [docs/setup_guide.md](docs/setup_guide.md) : point d'entrée et ordre global
- [docs/platform/gcp_terminal_setup.md](docs/platform/gcp_terminal_setup.md) : setup manuel GCP one-shot
- [docs/infra/docker_run_commands.md](docs/infra/docker_run_commands.md) : exécution Terraform via Docker
- [docs/infra/manual_commands.md](docs/infra/manual_commands.md) : exécution Terraform avec outils installés localement
- [docs/platform/secret_manager_setup.md](docs/platform/secret_manager_setup.md) : création et alimentation des secrets
- [docs/cicd/github_wif_setup.md](docs/cicd/github_wif_setup.md) : CI GitHub ↔ GCP via WIF
- [docs/infra/iam_roles.md](docs/infra/iam_roles.md) : matrice des rôles et permissions
- [docs/cicd/deployment_orchestration.md](docs/cicd/deployment_orchestration.md) : vue d'ensemble de l'enchaînement infra → ingestion → dbt → dashboard
- [docs/infra/infra_epic4_status.md](docs/infra/infra_epic4_status.md) : état d'avancement des tickets infra

## Structure repo retenue pour la suite

- `src/ingestion/` pour l'EPIC ingestion,
- `dbt/transformation/` pour le futur projet dbt et son conteneur dédié,
- `infra/` pour Terraform,
- `docs/` pour la documentation opérationnelle.

## Règle de maintenance documentaire

Pour éviter les doublons :
- les commandes one-shot GCP restent dans [docs/platform/gcp_terminal_setup.md](docs/platform/gcp_terminal_setup.md),
- les commandes récurrentes Docker restent dans [docs/infra/docker_run_commands.md](docs/infra/docker_run_commands.md),
- les commandes récurrentes sans Docker restent dans [docs/infra/manual_commands.md](docs/infra/manual_commands.md),
- les options avancées ou sensibles ont leur sous-guide dédié.

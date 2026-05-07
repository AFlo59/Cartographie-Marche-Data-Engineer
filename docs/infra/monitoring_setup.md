# Guide — Monitoring & Alertes pipeline (INFRA-11)

Ce guide couvre la mise en place des alertes email sur les Cloud Run Jobs ingestion et dbt via Cloud Monitoring.

Prérequis déjà documentés ailleurs :

- setup GCP one-shot : [docs/platform/gcp_terminal_setup.md](../platform/gcp_terminal_setup.md)
- matrice complète des rôles : [docs/infra/iam_roles.md](../infra/iam_roles.md)
- déploiement Terraform : [docs/infra/infrastructure_flow.md](../infra/infrastructure_flow.md)

> **Conventions** :
> - ✅ **Géré par Terraform** — appliqué automatiquement via `terraform apply` sur merge `main`
> - 🔧 **Manuel (gcloud / GitHub UI)** — commande one-shot à exécuter une seule fois
> - ❌ **Non fait** — à réaliser

---

## Ce que ce guide déploie

| Ressource | Type | Gestion |
|-----------|------|---------|
| Canal email × N destinataires | `google_monitoring_notification_channel` | ✅ Terraform |
| Alert policy — Cloud Run Job ingestion | `google_monitoring_alert_policy` | ✅ Terraform |
| Alert policy — Cloud Run Job dbt | `google_monitoring_alert_policy` | ✅ Terraform |
| Permission `roles/monitoring.admin` sur terraform-deployer-sa | IAM | 🔧 Manuel |
| Variable GitHub Actions `ALERT_EMAILS` | GitHub repo settings | 🔧 Manuel |

---

## Variables

Définir ces variables **une seule fois** avant d'exécuter les commandes de ce guide :

```bash
# ═══════════════════════════════════════════════════════════════
# Variables — adapter à votre projet avant d'exécuter ce guide
# ═══════════════════════════════════════════════════════════════
GCP_PROJECT_ID="$(gcloud config get project)"

TERRAFORM_DEPLOYER_SA="terraform-deployer-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
```

---

## Étape 1 — Activer l'API Cloud Monitoring

🔧 Manuel (one-shot, Cloud Shell)

```bash
GCP_PROJECT_ID="$(gcloud config get project)"

gcloud services enable monitoring.googleapis.com \
  --project=${GCP_PROJECT_ID}
```

Vérification :

```bash
gcloud services list --enabled \
  --filter="name:monitoring.googleapis.com" \
  --project=${GCP_PROJECT_ID}
```

Résultat attendu : `monitoring.googleapis.com` apparaît dans la liste.

---

## Étape 2 — Accorder `roles/monitoring.admin` au terraform-deployer-sa

🔧 Manuel (one-shot, Cloud Shell)

Requis pour que Terraform puisse créer les alert policies et les notification channels.

```bash
GCP_PROJECT_ID="$(gcloud config get project)"
TERRAFORM_DEPLOYER_SA="terraform-deployer-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
  --member="serviceAccount:${TERRAFORM_DEPLOYER_SA}" \
  --role="roles/monitoring.admin"
```

Vérification :

```bash
gcloud projects get-iam-policy ${GCP_PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:${TERRAFORM_DEPLOYER_SA} AND bindings.role:roles/monitoring.admin" \
  --format="table(bindings.role,bindings.members)"
```

Résultat attendu : une ligne avec `roles/monitoring.admin` et l'email du SA.

---

## Étape 3 — Configurer la variable GitHub Actions `ALERT_EMAILS`

🔧 Manuel (GitHub UI)

**Chemin** : `Repository → Settings → Secrets and variables → Actions → onglet Variables → New repository variable`

| Champ | Valeur |
|-------|--------|
| **Name** | `ALERT_EMAILS` |
| **Value** | JSON array des destinataires (voir format ci-dessous) |

### Format de la valeur

Un seul destinataire :

```
["prenom.nom@exemple.com"]
```

Plusieurs destinataires :

```
["prenom.nom@exemple.com","collaborateur1@exemple.com","collaborateur2@exemple.com"]
```

> Pas d'espace entre les éléments. Guillemets doubles obligatoires. Terraform parse ce JSON automatiquement via `TF_VAR_alert_emails`.

---

## Étape 4 — Déploiement Terraform

✅ Automatique sur merge `main`

Le CI (`infra-deploy.yml`) injecte :

```yaml
TF_VAR_create_monitoring: "true"
TF_VAR_alert_emails: ${{ vars.ALERT_EMAILS }}
```

Terraform crée :
- Un `google_monitoring_notification_channel` de type `email` par destinataire
- Une `google_monitoring_alert_policy` pour le job ingestion (`datatalent-ingestion-job`)
- Une `google_monitoring_alert_policy` pour le job dbt (`datatalent-dbt-job`)

Chaque alert policy se déclenche sur `severity>=ERROR` dans les logs Cloud Run du job concerné, avec un délai minimum de 5 minutes entre deux notifications.

---

## Étape 5 — Vérifications post-déploiement

### 5.1 Vérifier les canaux de notification

```bash
GCP_PROJECT_ID="$(gcloud config get project)"

gcloud alpha monitoring channels list \
  --project=${GCP_PROJECT_ID}
```

Résultat attendu : autant de canaux `email` que de destinataires configurés dans `ALERT_EMAILS`.

### 5.2 Vérifier les alert policies

```bash
gcloud alpha monitoring policies list \
  --project=${GCP_PROJECT_ID}
```

Résultat attendu : deux policies — `Cloud Run Job Failure — datatalent-ingestion-job` et `Cloud Run Job Failure — datatalent-dbt-job`.

### 5.3 Confirmer la réception email

GCP envoie un email de confirmation à chaque destinataire lors de la création du canal. Chaque destinataire doit **cliquer sur le lien de confirmation** dans cet email pour activer la réception des alertes.

> Si le lien n'est pas cliqué, l'alert policy est active mais l'email ne sera pas envoyé à ce destinataire.

---

## Étape 6 — Modifier les destinataires

Pour ajouter ou retirer un destinataire, mettre à jour la variable GitHub Actions `ALERT_EMAILS` et relancer le workflow `infra-deploy.yml` (ou attendre le prochain merge sur `main`).

Aucune modification de code nécessaire.

---

## Erreurs fréquentes

### `PERMISSION_DENIED` lors du `terraform apply`

Le SA `terraform-deployer-sa` n'a pas `roles/monitoring.admin`. Reprendre l'étape 2.

### `API [monitoring.googleapis.com] not enabled`

L'API Cloud Monitoring n'est pas activée. Reprendre l'étape 1.

### Alert policy créée mais pas d'email reçu

Cause probable : le destinataire n'a pas confirmé son canal (voir étape 5.3).

Vérification de l'état du canal :

```bash
GCP_PROJECT_ID="$(gcloud config get project)"

gcloud alpha monitoring channels list \
  --project=${GCP_PROJECT_ID} \
  --format="table(displayName,type,verificationStatus)"
```

Résultat attendu : `verificationStatus = VERIFIED` pour chaque canal actif.

### `TF_VAR_alert_emails` non reconnu

Vérifier que la variable GitHub Actions `ALERT_EMAILS` est bien créée en tant que **Variable** (pas Secret) et que sa valeur est un JSON array valide sans espace : `["email1@x.com","email2@x.com"]`.

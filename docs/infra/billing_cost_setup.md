# Guide — Monitoring des coûts GCP (INFRA-12)

Ce guide couvre la mise en place du suivi des coûts GCP via l'export billing BigQuery et les modèles dbt dédiés.

Prérequis déjà documentés ailleurs :

- setup GCP one-shot : [docs/platform/gcp_terminal_setup.md](../platform/gcp_terminal_setup.md)
- matrice complète des rôles : [docs/infra/iam_roles.md](../infra/iam_roles.md)
- déploiement Terraform : [docs/infra/infrastructure_flow.md](../infra/infrastructure_flow.md)
- modèles dbt : [docs/dbt/setup_guide.md](../dbt/setup_guide.md)

> **Conventions** :
> - ✅ **Géré par Terraform** — appliqué automatiquement via `terraform apply` sur merge `main`
> - 🔧 **Manuel (GCP Console / gcloud)** — action one-shot à exécuter une seule fois
> - ❌ **Non fait** — à réaliser

---

## Ce que ce guide déploie

| Ressource | Type | Gestion |
|-----------|------|---------|
| Export billing → dataset `billing_export` | GCP Console | 🔧 Manuel |
| `roles/bigquery.dataViewer` dbt-sa sur `billing_export` | `google_bigquery_dataset_iam_member` | ✅ Terraform |
| Vue mensuelle `mart_couts__mensuel` | modèle dbt | ✅ dbt (Cloud Run Job) |
| Vue annuelle `mart_couts__annuel` | modèle dbt | ✅ dbt (Cloud Run Job) |

---

## Variables

Définir ces variables **une seule fois** avant d'exécuter les commandes de ce guide :

```bash
# ═══════════════════════════════════════════════════════════════
# Variables — adapter à votre projet avant d'exécuter ce guide
# ═══════════════════════════════════════════════════════════════
GCP_PROJECT_ID="$(gcloud config get project)"

DBT_SA="dbt-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
BILLING_DATASET="billing_export"

# ID du billing account GCP (format : XXXXXX-XXXXXX-XXXXXX → remplacer les - par _)
# Visible dans : Console GCP → Facturation → Gérer les comptes de facturation
BILLING_ACCOUNT_ID="XXXXXX_XXXXXX_XXXXXX"
BILLING_TABLE="gcp_billing_export_v1_${BILLING_ACCOUNT_ID}"
```

---

## Étape 1 — Activer l'export billing vers BigQuery

🔧 Manuel (GCP Console — one-shot)

**Chemin** : `Console GCP → Facturation → Exportation des données de facturation → Coût détaillé d'utilisation → Modifier les paramètres`

| Champ | Valeur |
|-------|--------|
| **Projet** | `${GCP_PROJECT_ID}` |
| **Nom du dataset** | `billing_export` |
| **Localisation** | `us-central1` (ou la région de votre choix) |

Cliquer sur **Enregistrer**.

> GCP crée automatiquement le dataset `billing_export` et commence à alimenter la table.
> **Latence initiale : 24 à 48h** — le dataset est vide jusqu'au premier export automatique.
> L'export n'est **pas rétroactif** : seules les données postérieures à l'activation sont disponibles.

---

## Étape 2 — Permission dbt-sa sur billing_export

✅ Géré par Terraform — appliqué sur merge `main`

Le module warehouse crée automatiquement le binding :

```hcl
resource "google_bigquery_dataset_iam_member" "dbt_billing_viewer" {
  dataset_id = "billing_export"
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:dbt-sa@..."
}
```

Vérification post-apply :

```bash
GCP_PROJECT_ID="$(gcloud config get project)"

gcloud projects get-iam-policy ${GCP_PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:dbt-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
  --format="table(bindings.role)"
```

Résultat attendu : `roles/bigquery.dataViewer` présent dans la liste (binding dataset, pas projet).

> ⚠️ Ne pas utiliser `gcloud projects add-iam-policy-binding` avec `roles/bigquery.dataViewer` pour ce besoin — cela accorderait le droit en lecture sur **tous** les datasets du projet. Terraform gère un binding ciblé au niveau dataset uniquement.

---

## Étape 3 — Vérifier la table billing créée par GCP

🔧 Manuel (Cloud Shell — après 24-48h)

```bash
GCP_PROJECT_ID="$(gcloud config get project)"

bq ls --project_id=${GCP_PROJECT_ID} billing_export
```

Résultat attendu (exemple) :

```
tableId                                    Type
------------------------------------------ -------
gcp_billing_export_v1_XXXXXX_XXXXXX_XXXXXX TABLE
```

Relever le nom exact de la table — il correspond à `gcp_billing_export_v1_${BILLING_ACCOUNT_ID}`.

> Si le nom de la table diffère de la valeur de `${BILLING_TABLE}`, mettre à jour
> [dbt/transformation/models/sources/billing.yml](../../dbt/transformation/models/sources/billing.yml)
> avec le nom exact trouvé.

---

## Étape 4 — Modèles dbt disponibles dans marts

✅ Automatique — créés au prochain run dbt (Cloud Run Job défini dans `var.dbt_job_name`)

| Modèle | Dataset | Description |
|--------|---------|-------------|
| `mart_couts__mensuel` | `marts` | Coûts par service, SKU, ressource, région — grain mensuel |
| `mart_couts__annuel` | `marts` | Même granularité — grain annuel |

### Dimensions disponibles pour le filtrage BI

| Colonne | Exemples de valeurs |
|---------|-------------------|
| `service` | Cloud Run, BigQuery, Cloud Storage, Artifact Registry |
| `sku` | Jobs CPU in europe-west1, Standard Storage Belgium |
| `ressource_nom` | datatalent-ingestion-job, datatalent-dbt-job |
| `ressource_type` | cloud_run_job, bigquery_dataset |
| `region` | europe-west1, us-central1, null (global) |
| `pays` | BE, US |
| `type_cout` | regular, tax, adjustment, rounding_error |
| `mois` | 2026-04-01, 2026-05-01, … |
| `trimestre` | 1, 2, 3, 4 |
| `annee` | 2026, 2027, … |
| `cout_net_eur` | Coût final après crédits |

---

## Étape 5 — Tester les modèles avec une table stub (optionnel)

🔧 Manuel — uniquement pour valider le dbt avant que les vraies données arrivent

```bash
GCP_PROJECT_ID="$(gcloud config get project)"
BILLING_ACCOUNT_ID="XXXXXX_XXXXXX_XXXXXX"   # adapter
BILLING_TABLE="gcp_billing_export_v1_${BILLING_ACCOUNT_ID}"

bq mk \
  --table \
  --project_id=${GCP_PROJECT_ID} \
  ${GCP_PROJECT_ID}:billing_export.${BILLING_TABLE} \
  "service:RECORD,usage_start_time:TIMESTAMP,usage_end_time:TIMESTAMP,\
project:RECORD,sku:RECORD,resource:RECORD,location:RECORD,\
cost:FLOAT,credits:RECORD,cost_type:STRING"
```

> Cette table stub est vide et sert uniquement à valider la compilation dbt.
> Elle sera remplacée automatiquement par la vraie table GCP billing dès le premier export.

---

## Étape 6 — Utiliser les vues dans Google Sheets (dashboard gratuit)

Une fois les données présentes dans `marts` :

1. Ouvrir Google Sheets
2. **Données → Connecteur de données → BigQuery**
3. Projet `${GCP_PROJECT_ID}` → Dataset `marts` → Table `mart_couts__mensuel`
4. Créer des graphiques avec les colonnes `mois`, `service`, `cout_net_eur`

> Alternative : accéder directement via l'interface BigQuery Console pour explorer les données.

---

## Erreurs fréquentes

### `Table not found: billing_export.gcp_billing_export_v1_*` dans dbt

L'export billing n'a pas encore alimenté la table. Attendre 24-48h après activation de l'étape 1,
ou créer la table stub (étape 5) pour valider la compilation.

### `Access Denied: bigquery.tables.get` dans dbt

Le dbt-sa n'a pas encore `roles/bigquery.dataViewer` sur `billing_export`.
Vérifier que le Terraform apply s'est bien exécuté (merge sur `main` requis).

### Le dataset `billing_export` n'existe pas

L'export n'a pas encore été activé. Reprendre l'étape 1.

### `bq add-iam-policy-binding` retourne `This feature requires allowlisting`

Comportement normal sur ce compte. Le binding est géré par Terraform — ne pas utiliser la commande `bq` pour cette opération.

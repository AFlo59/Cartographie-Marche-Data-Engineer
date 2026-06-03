-- Modèle de DÉMONSTRATION du déploiement CI/CD (GitHub Actions → terraform apply →
-- Cloud Run Job dbt sur GCP).
--
-- Vue 100 % autonome : aucune source, aucun ref(), aucune dépendance externe.
-- Elle ne peut donc rien casser dans le pipeline (compile et run toujours).
--
-- Usage démo : bump la constante `version` ci-dessous, merge sur `main`, puis
-- observer la nouvelle valeur dans BigQuery `marts.mart_demo__deploiement` après le
-- run du Cloud Run Job dbt.

select
  cast('cartographie-marche-data-engineer' as string)                  as pipeline_nom,
  cast('1.0.0' as string)                                              as version,
  cast('{{ target.name }}' as string)                                  as environnement_dbt,
  cast(5 as int64)                                                     as nb_sources_ingerees,
  cast(current_timestamp() as timestamp)                               as genere_a,
  cast('Demo deploiement GitHub Actions + Cloud Run Job dbt' as string) as message

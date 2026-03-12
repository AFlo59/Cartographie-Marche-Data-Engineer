#pour explorer le parquet, on évite d'utiliser pandas avec read_parquet car va charger tout dans la ram
# on peut utiliser pyarrow pour lire les métadonnées et un échantillon de lignes
import pyarrow.parquet as pq

chemin = "StockUniteLegale_utf8.parquet"

# Ouvre le fichier sans le charger en mémoire
parquet_file = pq.ParquetFile(chemin)

# Affiche le schéma (colonnes + types) sans charger les données
print("📊 Colonnes disponibles :")
print(parquet_file.schema)

# Lit seulement les 5 premières lignes
premier_batch = next(parquet_file.iter_batches(batch_size=5))
df = premier_batch.to_pandas()

print(f"\n5 premières lignes :")
print(df.to_string())

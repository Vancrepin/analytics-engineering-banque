"""
Script de chargement des données CSV vers PostgreSQL (couche RAW)
Utilise SQLAlchemy pour une connexion robuste
"""

import os
import numpy as np
import pandas as pd
from sqlalchemy import create_engine, text
from dotenv import load_dotenv
from tqdm import tqdm

# Charger les variables d'environnement
load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), "..", ".env"))

# Configuration de la connexion PostgreSQL
DB_USER = os.getenv('POSTGRES_USER', 'analytics_user')
DB_PASSWORD = os.getenv('POSTGRES_PASSWORD', 'analytics_password')
DB_HOST = 'localhost'  # Car on accède depuis l'extérieur de Docker
DB_PORT = os.getenv('POSTGRES_PORT', '5432')
DB_NAME = os.getenv('POSTGRES_DB', 'analytics_warehouse')

# URL de connexion
DATABASE_URL = f"postgresql+psycopg://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"


def verifier_connexion(engine):
    """Vérifie que la connexion à PostgreSQL fonctionne"""
    try:
        with engine.connect() as conn:
            result = conn.execute(text("SELECT version();"))
            version = result.fetchone()[0]
            print(f"✅ Connexion PostgreSQL réussie !")
            print(f"📊 Version: {version[:50]}...")
            return True
    except Exception as e:
        print(f"❌ Erreur de connexion : {e}")
        return False


def normalize_df_for_pg(df: pd.DataFrame) -> pd.DataFrame:
    """
    Normalise les types pour éviter les erreurs de cast Postgres/SQLAlchemy.
    - '' -> NaN
    - dates -> date
    - timestamps -> datetime
    - NaT/NaN -> None
    """
    df = df.copy()

    # 1) Remplacer les chaînes vides / espaces par NaN (sinon ''::timestamp plante)
    df = df.replace(r'^\s*$', np.nan, regex=True)

    # 2) Colonnes TIME (heure_*)
    time_columns = [c for c in df.columns if 'heure' in c.lower()]
    for col in time_columns:
        # Supporte "HH:MM" ou "HH:MM:SS"
        df[col] = pd.to_datetime(df[col], errors='coerce').dt.time

    # 3) Colonnes TIMESTAMP : loaded_at + *_at + celles qui contiennent "datetime"
    timestamp_columns = [c for c in df.columns if c.lower().endswith('_at') or 'datetime' in c.lower()]
    if 'loaded_at' in df.columns and 'loaded_at' not in timestamp_columns:
        timestamp_columns.append('loaded_at')

    for col in timestamp_columns:
        if col in df.columns:
            df[col] = pd.to_datetime(df[col], errors='coerce')

    # 4) Colonnes DATE : toutes celles qui contiennent "date" SAUF celles déjà traitées comme timestamp
    date_columns = [c for c in df.columns if 'date' in c.lower() and c not in timestamp_columns]
    for col in date_columns:
        df[col] = pd.to_datetime(df[col], errors='coerce').dt.date

    # 5) Colonnes numériques (évite les 'nan' strings)
    numeric_candidates = {
        "montant", "montant_prime", "prime_mensuelle", "capital_assure", "franchise",
        "montant_declare", "montant_indemnise", "score_credit", "delai_traitement_jours"
    }
    for col in df.columns:
        if col in numeric_candidates:
            df[col] = pd.to_numeric(df[col], errors='coerce')

    # 6) NaN/NaT -> None (psycopg2/psycopg préfère None)
    df = df.where(pd.notnull(df), None)

    return df


def charger_table(engine, nom_table, chemin_csv):
    """
    Charge un fichier CSV dans une table PostgreSQL

    Args:
        engine: SQLAlchemy engine
        nom_table: Nom de la table (ex: 'clients')
        chemin_csv: Chemin du fichier CSV
    """
    print(f"\n📤 Chargement de {nom_table}...")

    try:
        # Lire le CSV (keep_default_na=True par défaut, mais on sécurise)
        df = pd.read_csv(chemin_csv, keep_default_na=True)
        print(f"   📊 {len(df):,} lignes lues depuis {chemin_csv}")

        # Normalisation robuste des types
        df = normalize_df_for_pg(df)

        # Vider la table avant chargement (mode TRUNCATE)
        with engine.connect() as conn:
            conn.execute(text(f"TRUNCATE TABLE raw.{nom_table} CASCADE;"))
            conn.commit()
            print(f"   🗑️  Table raw.{nom_table} vidée")

        # Charger les données avec barre de progression
        chunk_size = 1000

        with tqdm(total=len(df), desc=f"   Insertion {nom_table}") as pbar:
            for i in range(0, len(df), chunk_size):
                chunk = df.iloc[i:i + chunk_size]

                chunk.to_sql(
                    name=nom_table,
                    con=engine,
                    schema='raw',
                    if_exists='append',
                    index=False,
                    method='multi',
                    chunksize=chunk_size
                )
                pbar.update(len(chunk))

        # Vérifier le nombre de lignes chargées
        with engine.connect() as conn:
            result = conn.execute(text(f"SELECT COUNT(*) FROM raw.{nom_table};"))
            count = result.fetchone()[0]
            print(f"   ✅ {count:,} lignes insérées dans raw.{nom_table}")

        return True

    except Exception as e:
        print(f"   ❌ Erreur lors du chargement de {nom_table}: {e}")
        return False


def afficher_stats(engine):
    """Affiche des statistiques sur les données chargées"""
    print("\n" + "=" * 60)
    print("📊 STATISTIQUES DES DONNÉES CHARGÉES")
    print("=" * 60)

    tables = ['clients', 'transactions', 'contrats', 'sinistres', 'primes']

    with engine.connect() as conn:
        for table in tables:
            result = conn.execute(text(f"SELECT COUNT(*) FROM raw.{table};"))
            count = result.fetchone()[0]
            print(f"  • {table.capitalize():15} : {count:>10,} lignes")

        print("\n📈 Statistiques métier :")

        result = conn.execute(text("""
            SELECT AVG(nb_trans)::INTEGER as avg_trans
            FROM (
                SELECT client_id, COUNT(*) as nb_trans
                FROM raw.transactions
                GROUP BY client_id
            ) sub;
        """))
        avg_trans = result.fetchone()[0]
        print(f"  • Transactions par client (moy) : {avg_trans}")

        result = conn.execute(text("""
            SELECT AVG(montant)::NUMERIC(10,2) as avg_montant
            FROM raw.transactions;
        """))
        avg_montant = result.fetchone()[0]
        print(f"  • Montant moyen transaction     : {avg_montant} EUR")

        result = conn.execute(text("""
            SELECT COUNT(*) FROM raw.contrats WHERE statut = 'Actif';
        """))
        contrats_actifs = result.fetchone()[0]
        print(f"  • Contrats actifs               : {contrats_actifs:,}")

        result = conn.execute(text("""
    SELECT
        (COUNT(DISTINCT s.contrat_id)::FLOAT
         / NULLIF(COUNT(DISTINCT c.contrat_id), 0) * 100)::NUMERIC(5,2) AS ratio
    FROM raw.contrats c
    LEFT JOIN raw.sinistres s
      ON s.contrat_id = c.contrat_id;
"""))

        ratio = result.fetchone()[0]
        print(f"  • Taux de sinistralité          : {ratio}%")


def main():
    print("=" * 60)
    print("📥 CHARGEMENT DES DONNÉES DANS POSTGRESQL")
    print("=" * 60)

    print(f"\n🔌 Connexion à {DB_HOST}:{DB_PORT}/{DB_NAME}...")
    engine = create_engine(DATABASE_URL)

    if not verifier_connexion(engine):
        print("\n❌ Impossible de se connecter à PostgreSQL.")
        print("Vérifiez que Docker est lancé : docker-compose ps")
        return

    tables_config = [
        ('clients', './data/raw/clients.csv'),
        ('transactions', './data/raw/transactions.csv'),
        ('contrats', './data/raw/contrats.csv'),
        ('sinistres', './data/raw/sinistres.csv'),
        ('primes', './data/raw/primes.csv'),
    ]

    success_count = 0
    for nom_table, chemin_csv in tables_config:
        if charger_table(engine, nom_table, chemin_csv):
            success_count += 1

    if success_count == len(tables_config):
        afficher_stats(engine)
        print("\n" + "=" * 60)
        print("✅ CHARGEMENT TERMINÉ AVEC SUCCÈS !")
        print("=" * 60)
        print("\n💡 Prochaine étape : Configuration de dbt")
    else:
        print(f"\n⚠️  {success_count}/{len(tables_config)} tables chargées")

    engine.dispose()


if __name__ == "__main__":
    main()

"""
DAG Airflow : Ingestion des données sources
Charge les fichiers CSV dans PostgreSQL (couche RAW)
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from airflow.utils.dates import days_ago
import pandas as pd
from sqlalchemy import create_engine
import os

# Configuration
default_args = {
    'owner': 'data_engineering',
    'depends_on_past': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'data_ingestion_daily',
    default_args=default_args,
    description='Chargement quotidien des données sources dans PostgreSQL',
    schedule_interval='0 2 * * *',  # Tous les jours à 2h du matin (avant dbt)
    start_date=days_ago(1),
    catchup=False,
    tags=['ingestion', 'raw', 'daily'],
)

# Configuration PostgreSQL
DATABASE_URL = "postgresql://analytics_user:analytics_password@postgres:5432/analytics_warehouse"

def load_csv_to_postgres(table_name, csv_path):
    """
    Charge un fichier CSV dans une table PostgreSQL
    """
    print(f"📥 Chargement de {table_name}...")
    
    # Créer la connexion
    engine = create_engine(DATABASE_URL)
    
    # Lire le CSV
    df = pd.read_csv(csv_path)
    print(f"   📊 {len(df):,} lignes lues depuis {csv_path}")
    
    # Convertir les colonnes de dates
    date_columns = [col for col in df.columns if 'date' in col.lower()]
    for col in date_columns:
        df[col] = pd.to_datetime(df[col], errors='coerce')
    
    # Vider la table
    with engine.connect() as conn:
        conn.execute(f"TRUNCATE TABLE raw.{table_name} CASCADE;")
        conn.commit()
    
    # Charger les données
    df.to_sql(
        name=table_name,
        con=engine,
        schema='raw',
        if_exists='append',
        index=False,
        method='multi'
    )
    
    print(f"   ✅ {len(df):,} lignes chargées dans raw.{table_name}")
    engine.dispose()

# Tâches de chargement
load_clients = PythonOperator(
    task_id='load_clients',
    python_callable=load_csv_to_postgres,
    op_kwargs={
        'table_name': 'clients',
        'csv_path': '/opt/airflow/data/raw/clients.csv'
    },
    dag=dag,
)

load_transactions = PythonOperator(
    task_id='load_transactions',
    python_callable=load_csv_to_postgres,
    op_kwargs={
        'table_name': 'transactions',
        'csv_path': '/opt/airflow/data/raw/transactions.csv'
    },
    dag=dag,
)

load_contrats = PythonOperator(
    task_id='load_contrats',
    python_callable=load_csv_to_postgres,
    op_kwargs={
        'table_name': 'contrats',
        'csv_path': '/opt/airflow/data/raw/contrats.csv'
    },
    dag=dag,
)

load_sinistres = PythonOperator(
    task_id='load_sinistres',
    python_callable=load_csv_to_postgres,
    op_kwargs={
        'table_name': 'sinistres',
        'csv_path': '/opt/airflow/data/raw/sinistres.csv'
    },
    dag=dag,
)

load_primes = PythonOperator(
    task_id='load_primes',
    python_callable=load_csv_to_postgres,
    op_kwargs={
        'table_name': 'primes',
        'csv_path': '/opt/airflow/data/raw/primes.csv'
    },
    dag=dag,
)

# Notification
def notify_ingestion_complete(**context):
    print("✅ Ingestion des données terminée avec succès !")
    print(f"Tables chargées : clients, transactions, contrats, sinistres, primes")

notify = PythonOperator(
    task_id='notify_completion',
    python_callable=notify_ingestion_complete,
    dag=dag,
)

# Dépendances : charger clients d'abord (clé étrangère), puis le reste en parallèle
load_clients >> [load_transactions, load_contrats]
load_contrats >> [load_sinistres, load_primes]
[load_transactions, load_sinistres, load_primes] >> notify
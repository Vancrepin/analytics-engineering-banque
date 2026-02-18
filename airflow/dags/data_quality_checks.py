"""
DAG Airflow : Contrôles qualité des données
Vérifie l'intégrité et la qualité des données transformées
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.postgres.operators.postgres import PostgresOperator
from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.utils.dates import days_ago

default_args = {
    'owner': 'data_quality',
    'depends_on_past': False,
    'retries': 1,
}

dag = DAG(
    'data_quality_checks',
    default_args=default_args,
    description='Contrôles qualité quotidiens',
    schedule_interval='0 6 * * *',  # Tous les jours à 6h (après dbt)
    start_date=days_ago(1),
    catchup=False,
    tags=['quality', 'monitoring'],
)

def check_row_counts(**context):
    """
    Vérifie que les tables contiennent des données
    """
    hook = PostgresHook(postgres_conn_id='postgres_default')
    
    tables_to_check = [
        ('raw', 'clients'),
        ('raw', 'transactions'),
        ('staging', 'stg_clients'),
        ('staging', 'stg_transactions'),
        ('marts', 'fct_anomalies_transactions'),
        ('marts', 'fct_churn_predictions'),
    ]
    
    print("\n📊 Vérification du nombre de lignes :")
    print("=" * 60)
    
    for schema, table in tables_to_check:
        result = hook.get_first(f"SELECT COUNT(*) FROM {schema}.{table}")
        count = result[0] if result else 0
        print(f"  • {schema}.{table:30} : {count:>10,} lignes")
        
        if count == 0:
            raise ValueError(f"❌ Table {schema}.{table} est vide !")
    
    print("=" * 60)
    print("✅ Tous les contrôles de volumétrie sont OK")

def check_anomalies_detected(**context):
    """
    Vérifie qu'au moins quelques anomalies ont été détectées
    """
    hook = PostgresHook(postgres_conn_id='postgres_default')
    
    result = hook.get_first("""
        SELECT 
            COUNT(*) as total,
            COUNT(CASE WHEN niveau_severite = 'Critique' THEN 1 END) as critiques
        FROM marts.fct_anomalies_transactions
    """)
    
    total, critiques = result
    
    print(f"\n🔍 Anomalies détectées :")
    print(f"  • Total : {total}")
    print(f"  • Critiques : {critiques}")
    
    if total == 0:
        print("⚠️  Aucune anomalie détectée (cela peut être normal)")

def check_churn_predictions(**context):
    """
    Vérifie la distribution des scores de churn
    """
    hook = PostgresHook(postgres_conn_id='postgres_default')
    
    result = hook.get_records("""
        SELECT 
            segment_risque,
            COUNT(*) as nb_clients
        FROM marts.fct_churn_predictions
        GROUP BY segment_risque
        ORDER BY nb_clients DESC
    """)
    
    print(f"\n📈 Distribution des risques de churn :")
    for segment, count in result:
        print(f"  • {segment:15} : {count:>6,} clients")

def check_data_freshness(**context):
    """
    Vérifie la fraîcheur des données (loaded_at, updated_at)
    """
    hook = PostgresHook(postgres_conn_id='postgres_default')
    
    result = hook.get_first("""
        SELECT MAX(loaded_at) 
        FROM raw.transactions
    """)
    
    last_load = result[0] if result else None
    
    print(f"\n🕐 Fraîcheur des données :")
    print(f"  • Dernière charge (raw.transactions) : {last_load}")
    
    if last_load:
        age_hours = (datetime.now() - last_load).total_seconds() / 3600
        print(f"  • Ancienneté : {age_hours:.1f} heures")
        
        if age_hours > 48:
            print("⚠️  Données de plus de 48h !")

# Tâches
check_counts = PythonOperator(
    task_id='check_row_counts',
    python_callable=check_row_counts,
    dag=dag,
)

check_anomalies = PythonOperator(
    task_id='check_anomalies',
    python_callable=check_anomalies_detected,
    dag=dag,
)

check_churn = PythonOperator(
    task_id='check_churn_distribution',
    python_callable=check_churn_predictions,
    dag=dag,
)

check_freshness = PythonOperator(
    task_id='check_data_freshness',
    python_callable=check_data_freshness,
    dag=dag,
)

# Exécution en parallèle
check_counts >> [check_anomalies, check_churn, check_freshness]
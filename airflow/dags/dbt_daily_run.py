"""
DAG Airflow : Transformation dbt quotidienne
Exécute toutes les transformations dbt (staging → intermediate → marts)
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator
from airflow.utils.dates import days_ago

# Configuration par défaut du DAG
default_args = {
    'owner': 'analytics_team',
    'depends_on_past': False,
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

# Définition du DAG
dag = DAG(
    'dbt_daily_transformation',
    default_args=default_args,
    description='Transformation quotidienne des données avec dbt',
    schedule_interval='0 4 * * *',  # Tous les jours à 4h du matin
    start_date=days_ago(1),
    catchup=False,
    tags=['dbt', 'transformation', 'daily'],
)

# Chemin vers le projet dbt (dans le conteneur)
DBT_PROJECT_DIR = '/opt/airflow/dbt'
DBT_PROFILES_DIR = '/opt/airflow/dbt'

# =============================================
# TÂCHES
# =============================================

# Tâche 1 : Vérifier la connexion dbt
test_connection = BashOperator(
    task_id='test_dbt_connection',
    bash_command=f'cd {DBT_PROJECT_DIR} && dbt debug --profiles-dir {DBT_PROFILES_DIR}',
    dag=dag,
)

# Tâche 2 : Installer les dépendances dbt
install_deps = BashOperator(
    task_id='install_dbt_deps',
    bash_command=f'cd {DBT_PROJECT_DIR} && dbt deps --profiles-dir {DBT_PROFILES_DIR}',
    dag=dag,
)

# Tâche 3 : Exécuter les modèles STAGING
run_staging = BashOperator(
    task_id='run_staging_models',
    bash_command=f'cd {DBT_PROJECT_DIR} && dbt run --select staging --profiles-dir {DBT_PROFILES_DIR}',
    dag=dag,
)

# Tâche 4 : Tester les modèles STAGING
test_staging = BashOperator(
    task_id='test_staging_models',
    bash_command=f'cd {DBT_PROJECT_DIR} && dbt test --select staging --profiles-dir {DBT_PROFILES_DIR}',
    dag=dag,
)

# Tâche 5 : Exécuter les modèles INTERMEDIATE
run_intermediate = BashOperator(
    task_id='run_intermediate_models',
    bash_command=f'cd {DBT_PROJECT_DIR} && dbt run --select intermediate --profiles-dir {DBT_PROFILES_DIR}',
    dag=dag,
)

# Tâche 6 : Tester les modèles INTERMEDIATE
test_intermediate = BashOperator(
    task_id='test_intermediate_models',
    bash_command=f'cd {DBT_PROJECT_DIR} && dbt test --select intermediate --profiles-dir {DBT_PROFILES_DIR}',
    dag=dag,
)

# Tâche 7 : Exécuter les modèles MARTS
run_marts = BashOperator(
    task_id='run_marts_models',
    bash_command=f'cd {DBT_PROJECT_DIR} && dbt run --select marts --profiles-dir {DBT_PROFILES_DIR}',
    dag=dag,
)

# Tâche 8 : Tester les modèles MARTS
test_marts = BashOperator(
    task_id='test_marts_models',
    bash_command=f'cd {DBT_PROJECT_DIR} && dbt test --select marts --profiles-dir {DBT_PROFILES_DIR}',
    dag=dag,
)

# Tâche 9 : Générer la documentation
generate_docs = BashOperator(
    task_id='generate_dbt_docs',
    bash_command=f'cd {DBT_PROJECT_DIR} && dbt docs generate --profiles-dir {DBT_PROFILES_DIR}',
    dag=dag,
)

# Tâche 10 : Notification de succès (fonction Python)
def notify_success(**context):
    """
    Fonction appelée en cas de succès
    """
    print("✅ Pipeline dbt exécuté avec succès !")
    print(f"Date d'exécution : {context['execution_date']}")
    print(f"Durée : {context['dag_run'].end_date - context['dag_run'].start_date}")
    # Ici, vous pourriez envoyer un email, un message Slack, etc.

success_notification = PythonOperator(
    task_id='notify_success',
    python_callable=notify_success,
    provide_context=True,
    dag=dag,
)

# =============================================
# DÉFINITION DES DÉPENDANCES (ordre d'exécution)
# =============================================

# Flux linéaire :
test_connection >> install_deps >> run_staging >> test_staging
test_staging >> run_intermediate >> test_intermediate
test_intermediate >> run_marts >> test_marts
test_marts >> generate_docs >> success_notification
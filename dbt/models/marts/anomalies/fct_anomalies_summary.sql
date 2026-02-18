{{
    config(
        materialized='table',
        tags=['marts', 'anomalies', 'summary']
    )
}}

/*
    Vue agrégée des anomalies par jour et type
*/

WITH anomalies AS (
    SELECT * FROM {{ ref('fct_anomalies_transactions') }}
)

SELECT
    date_detection AS date,
    type_anomalie_principal AS type_anomalie,
    niveau_severite,
    
    -- Comptages
    COUNT(DISTINCT anomalie_key) AS nb_anomalies_detectees,
    COUNT(DISTINCT client_key) AS nb_clients_concernes,
    
    -- Montants
    SUM(montant_eur) AS montant_total_suspect,
    AVG(montant_eur) AS montant_moyen_suspect,
    
    -- Scores
    AVG(score_anomalie) AS score_moyen,
    MAX(score_anomalie) AS score_max,
    
    -- Métadonnées
    CURRENT_TIMESTAMP AS calculated_at
    
FROM anomalies
GROUP BY date_detection, type_anomalie_principal, niveau_severite
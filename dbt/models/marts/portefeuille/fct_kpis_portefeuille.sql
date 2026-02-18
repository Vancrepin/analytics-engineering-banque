{{
    config(
        materialized='table',
        tags=['marts', 'portefeuille', 'kpis']
    )
}}

/*
    KPIs globaux du portefeuille
*/

WITH clients AS (
    SELECT * FROM {{ ref('stg_clients') }}
),

contrats AS (
    SELECT * FROM {{ ref('stg_contrats') }}
),

sinistres AS (
    SELECT * FROM {{ ref('stg_sinistres') }}
),

primes AS (
    SELECT * FROM {{ ref('stg_primes') }}
),

churn_data AS (
    SELECT * FROM {{ ref('fct_churn_predictions') }}
)

SELECT
    {{ dbt_utils.generate_surrogate_key(["CAST(CURRENT_DATE AS TEXT)"]) }}
 AS kpi_key,
    CURRENT_DATE AS date,
    
    -- Volumes globaux
    COUNT(DISTINCT c.client_id) AS nb_clients_actifs,
    COUNT(DISTINCT CASE WHEN ct.is_actif THEN ct.contrat_id END) AS nb_contrats_actifs,
    COUNT(DISTINCT CASE 
        WHEN c.is_nouveau_client THEN c.client_id 
    END) AS nb_nouveaux_clients,
    COUNT(DISTINCT CASE 
        WHEN ct.is_resilie THEN ct.contrat_id 
    END) AS nb_contrats_resilies,
    
    -- Valeurs financières
    SUM(CASE WHEN p.is_paye THEN p.montant_prime ELSE 0 END) AS total_primes_collectees,
    SUM(s.montant_indemnise) AS total_sinistres_payes,
    SUM(CASE WHEN ct.is_actif THEN ct.capital_assure ELSE 0 END) AS encours_total,
    
    -- Performance globale
    (SUM(s.montant_indemnise) / 
     NULLIF(SUM(CASE WHEN p.is_paye THEN p.montant_prime ELSE 0 END), 0) * 100) AS ratio_sp_global,
    
    (SUM(CASE WHEN p.is_paye THEN p.montant_prime ELSE 0 END) - 
     SUM(s.montant_indemnise)) AS marge_nette,
    
    AVG(ch.ltv_estimee_3ans) AS ltv_moyenne_client,
    
    -- Acquisition (simplifié - normalement coût marketing/nb clients)
    100 AS acquisition_cost_moyen,  -- Placeholder
    
    AVG(ch.ltv_estimee_3ans) AS customer_lifetime_value,
    
    -- Satisfaction (placeholder - normalement enquêtes)
    75 AS nps_score,
    
    -- Rétention
    (COUNT(DISTINCT CASE WHEN ct.is_actif THEN c.client_id END)::FLOAT / 
     NULLIF(COUNT(DISTINCT c.client_id), 0) * 100) AS taux_retention,
    
    (COUNT(DISTINCT CASE WHEN ch.score_churn >= 70 THEN c.client_id END)::FLOAT / 
     NULLIF(COUNT(DISTINCT c.client_id), 0) * 100) AS taux_churn,
    
    -- Métadonnées
    CURRENT_TIMESTAMP AS calculated_at
    
FROM clients c
LEFT JOIN contrats ct ON c.client_key = ct.client_key
LEFT JOIN sinistres s ON ct.contrat_key = s.contrat_key
LEFT JOIN primes p ON ct.contrat_key = p.contrat_key
LEFT JOIN churn_data ch ON c.client_key = ch.client_key
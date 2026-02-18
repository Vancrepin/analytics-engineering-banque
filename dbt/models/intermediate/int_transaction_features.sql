{{
    config(
        materialized='view',
        tags=['intermediate', 'transactions', 'anomalies']
    )
}}

/*
    Modèle INTERMEDIATE : Features pour détection d'anomalies
    
    Objectif :
    - Calculer des statistiques par client pour chaque transaction
    - Calculer des z-scores pour identifier les valeurs anormales
    - Préparer les features pour le modèle d'anomalies
    
    Source : stg_transactions
*/

WITH transactions AS (
    SELECT * FROM {{ ref('stg_transactions') }}
),

-- Statistiques par client sur les 30 derniers jours (fenêtre glissante)
client_stats AS (
    SELECT
        client_key,
        -- Moyenne et écart-type du montant (30 derniers jours)
        AVG(montant_eur) AS avg_montant_30j,
        STDDEV(montant_eur) AS std_montant_30j,
        
        -- Nombre de transactions par jour moyen
        COUNT(DISTINCT transaction_id)::FLOAT / 
        NULLIF(COUNT(DISTINCT date_transaction), 0) AS avg_trans_par_jour,
        
        -- Montant maximum historique
        MAX(montant_eur) AS max_montant_historique,
        
        -- Nombre de transactions internationales (historique)
        COUNT(CASE WHEN is_international THEN 1 END)::FLOAT / 
        NULLIF(COUNT(*), 0) AS taux_trans_internationales
        
    FROM transactions
    WHERE date_transaction >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY client_key
),

-- Statistiques par pays bénéficiaire pour le client
client_pays_stats AS (
    SELECT
        client_key,
        pays_beneficiaire,
        COUNT(*) AS nb_trans_pays
    FROM transactions
    GROUP BY client_key, pays_beneficiaire
),

-- Pour chaque transaction, calculer les features
enriched_transactions AS (
    SELECT
        t.transaction_key,
        t.transaction_id,
        t.client_key,
        t.client_id,
        t.date_transaction,
        t.heure_transaction,
        t.timestamp_transaction,
        t.montant_eur,
        t.type_transaction_std,
        t.canal_std,
        t.categorie_std,
        t.pays_beneficiaire,
        t.is_international,
        t.is_nocturne,
        t.is_weekend,
        t.plage_horaire,
        
        -- Statistiques du client
        cs.avg_montant_30j,
        cs.std_montant_30j,
        cs.avg_trans_par_jour,
        cs.max_montant_historique,
        cs.taux_trans_internationales,
        
        -- Z-score du montant (écart à la moyenne en nombre d'écarts-types)
        CASE 
            WHEN cs.std_montant_30j > 0 
            THEN (t.montant_eur - cs.avg_montant_30j) / cs.std_montant_30j
            ELSE 0 
        END AS z_score_montant,
        
        -- Ratio vs moyenne du client
        CASE 
            WHEN cs.avg_montant_30j > 0 
            THEN t.montant_eur / cs.avg_montant_30j
            ELSE 1 
        END AS ratio_vs_moyenne_client,
        
        -- Nombre de transactions du même client le même jour
        COUNT(*) OVER (
            PARTITION BY t.client_key, t.date_transaction
        ) AS nb_transactions_client_jour,
        
        -- Délai depuis la transaction précédente (en secondes)
        EXTRACT(EPOCH FROM (
            t.timestamp_transaction - 
            LAG(t.timestamp_transaction) OVER (
                PARTITION BY t.client_key 
                ORDER BY t.timestamp_transaction
            )
        )) AS delai_depuis_derniere_sec,
        
        -- La transaction est-elle dans un pays inhabituel ?
        CASE 
            WHEN cps.nb_trans_pays IS NULL OR cps.nb_trans_pays = 1 
            THEN TRUE 
            ELSE FALSE 
        END AS is_pays_inhabituel,
        
        -- Calcul du rang de la transaction par montant pour ce client
        PERCENT_RANK() OVER (
            PARTITION BY t.client_key 
            ORDER BY t.montant_eur
        ) AS percentile_montant_client,
        
        -- Métadonnées
        CURRENT_TIMESTAMP AS calculated_at
        
    FROM transactions t
    LEFT JOIN client_stats cs ON t.client_key = cs.client_key
    LEFT JOIN client_pays_stats cps 
        ON t.client_key = cps.client_key 
        AND t.pays_beneficiaire = cps.pays_beneficiaire
)

SELECT * FROM enriched_transactions
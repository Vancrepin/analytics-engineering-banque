{{
    config(
        materialized='table',
        tags=['marts', 'anomalies']
    )
}}

/*
    Modèle MART : Détection d'anomalies de transactions
    
    Objectif :
    - Identifier les transactions suspectes
    - Calculer un score d'anomalie (0-100)
    - Classifier par type et niveau de sévérité
    
    Source : int_transaction_features
*/

WITH features AS (
    SELECT * FROM {{ ref('int_transaction_features') }}
),

-- Seuils de détection (configurables via variables dbt)
anomaly_detection AS (
    SELECT
        transaction_key,
        transaction_id,
        client_key,
        client_id,
        date_transaction,
        timestamp_transaction,
        montant_eur,
        type_transaction_std,
        canal_std,
        pays_beneficiaire,
        
        -- Features utilisées pour la détection
        z_score_montant,
        ratio_vs_moyenne_client,
        nb_transactions_client_jour,
        is_nocturne,
        is_weekend,
        is_international,
        is_pays_inhabituel,
        delai_depuis_derniere_sec,
        
        -- ===============================
        -- DÉTECTION PAR TYPE D'ANOMALIE
        -- ===============================
        
        -- 1. Anomalie de MONTANT (z-score > 3)
        CASE 
            WHEN ABS(z_score_montant) > {{ var('anomaly_z_score_threshold', 3) }} 
            THEN TRUE 
            ELSE FALSE 
        END AS is_anomalie_montant,
        
        -- 2. Anomalie de FRÉQUENCE (trop de transactions)
        CASE 
            WHEN nb_transactions_client_jour > {{ var('anomaly_frequency_threshold', 5) }} 
            THEN TRUE 
            ELSE FALSE 
        END AS is_anomalie_frequence,
        
        -- 3. Anomalie GÉOGRAPHIQUE (pays inhabituel)
        CASE 
            WHEN is_international AND is_pays_inhabituel 
            THEN TRUE 
            ELSE FALSE 
        END AS is_anomalie_geographique,
        
        -- 4. Anomalie HORAIRE (nocturne + montant élevé)
        CASE 
            WHEN is_nocturne AND montant_eur > 1000 
            THEN TRUE 
            ELSE FALSE 
        END AS is_anomalie_horaire,
        
        -- 5. Anomalie COMPORTEMENTALE (délai suspect entre transactions)
        CASE 
            WHEN delai_depuis_derniere_sec IS NOT NULL 
                 AND delai_depuis_derniere_sec < 60  -- Moins d'1 minute
                 AND montant_eur > 500
            THEN TRUE 
            ELSE FALSE 
        END AS is_anomalie_comportementale,
        
        -- ===============================
        -- CALCUL DU SCORE D'ANOMALIE (0-100)
        -- ===============================
        LEAST(100, 
            -- Score basé sur le z-score (max 40 points)
            (CASE 
                WHEN ABS(z_score_montant) > 5 THEN 40
                WHEN ABS(z_score_montant) > 4 THEN 30
                WHEN ABS(z_score_montant) > 3 THEN 20
                ELSE ABS(z_score_montant) * 5
            END) +
            
            -- Score fréquence (max 20 points)
            (CASE 
                WHEN nb_transactions_client_jour > 10 THEN 20
                WHEN nb_transactions_client_jour > 7 THEN 15
                WHEN nb_transactions_client_jour > 5 THEN 10
                ELSE 0
            END) +
            
            -- Score géographique (max 20 points)
            (CASE 
                WHEN is_international AND is_pays_inhabituel THEN 20
                WHEN is_international THEN 10
                ELSE 0
            END) +
            
            -- Score horaire (max 10 points)
            (CASE 
                WHEN is_nocturne THEN 10
                WHEN is_weekend THEN 5
                ELSE 0
            END) +
            
            -- Score comportement (max 10 points)
            (CASE 
                WHEN delai_depuis_derniere_sec IS NOT NULL 
                     AND delai_depuis_derniere_sec < 60 THEN 10
                WHEN delai_depuis_derniere_sec IS NOT NULL 
                     AND delai_depuis_derniere_sec < 300 THEN 5
                ELSE 0
            END)
        ) AS score_anomalie
        
    FROM features
),

-- Classification finale
classified AS (
    SELECT
        -- Génération d'une clé unique pour l'anomalie
        {{ dbt_utils.generate_surrogate_key(['transaction_key']) }} AS anomalie_key,
        
        transaction_key,
        transaction_id,
        client_key,
        client_id,
        date_transaction,
        timestamp_transaction,
        montant_eur,
        type_transaction_std,
        canal_std,
        pays_beneficiaire,
        
        -- Indicateurs d'anomalie
        is_anomalie_montant,
        is_anomalie_frequence,
        is_anomalie_geographique,
        is_anomalie_horaire,
        is_anomalie_comportementale,
        
        -- Score et features
        score_anomalie,
        z_score_montant,
        ratio_vs_moyenne_client,
        nb_transactions_client_jour,
        is_nocturne,
        is_international,
        
        -- Type d'anomalie principal
        CASE 
            WHEN is_anomalie_montant THEN 'Montant'
            WHEN is_anomalie_frequence THEN 'Frequence'
            WHEN is_anomalie_geographique THEN 'Geographique'
            WHEN is_anomalie_horaire THEN 'Horaire'
            WHEN is_anomalie_comportementale THEN 'Comportement'
            ELSE 'Normal'
        END AS type_anomalie_principal,
        
        -- Niveau de sévérité
        CASE 
            WHEN score_anomalie >= 80 THEN 'Critique'
            WHEN score_anomalie >= 60 THEN 'Eleve'
            WHEN score_anomalie >= 40 THEN 'Moyen'
            WHEN score_anomalie >= 20 THEN 'Faible'
            ELSE 'Normal'
        END AS niveau_severite,
        
        -- Statut d'investigation (à enrichir manuellement)
        'Nouveau' AS statut_investigation,
        
        -- Flag : est-ce une anomalie ?
        CASE 
            WHEN score_anomalie >= 20 THEN TRUE 
            ELSE FALSE 
        END AS is_anomalie,
        
        -- Métadonnées
        CURRENT_DATE AS date_detection,
        CURRENT_TIMESTAMP AS detected_at
        
    FROM anomaly_detection
)

-- Filtrer uniquement les anomalies (score >= 20)
SELECT * 
FROM classified
WHERE is_anomalie = TRUE
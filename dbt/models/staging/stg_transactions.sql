{{
    config(
        materialized='view',
        tags=['staging', 'transactions']
    )
}}

/*
    Modèle STAGING : Transactions
    
    Objectif :
    - Standardiser les transactions bancaires
    - Enrichir avec des indicateurs temporels
    - Normaliser les montants et devises
    - Préparer pour la détection d'anomalies
    
    Source : raw.transactions
*/

WITH source AS (
    SELECT * FROM {{ source('raw', 'transactions') }}
),

cleaned AS (
    SELECT
        -- Clés
        {{ dbt_utils.generate_surrogate_key(['transaction_id']) }} AS transaction_key,
        transaction_id,
        {{ dbt_utils.generate_surrogate_key(['client_id']) }} AS client_key,
        client_id,
        
        -- Dates et heures
        date_transaction,
        heure_transaction,
        date_transaction + heure_transaction AS timestamp_transaction,
        
        -- Montants (tous convertis en EUR pour uniformité)
        montant AS montant_eur,
        montant AS montant_original,  -- Pour l'instant pas de conversion
        UPPER(TRIM(devise)) AS devise,
        
        -- Normalisation des types et canaux
        CASE 
            WHEN UPPER(type_transaction) LIKE '%VIREMENT%' THEN 'Virement'
            WHEN UPPER(type_transaction) LIKE '%PRELEVEMENT%' THEN 'Prélèvement'
            WHEN UPPER(type_transaction) LIKE '%CARTE%' THEN 'Carte'
            WHEN UPPER(type_transaction) LIKE '%CHEQUE%' THEN 'Chèque'
            WHEN UPPER(type_transaction) LIKE '%ESPECE%' THEN 'Espèces'
            ELSE 'Autre'
        END AS type_transaction_std,
        
        CASE 
            WHEN UPPER(canal) LIKE '%WEB%' THEN 'Web'
            WHEN UPPER(canal) LIKE '%MOBILE%' OR UPPER(canal) LIKE '%APP%' THEN 'Mobile'
            WHEN UPPER(canal) LIKE '%AGENCE%' OR UPPER(canal) LIKE '%GUICHET%' THEN 'Agence'
            WHEN UPPER(canal) LIKE '%ATM%' OR UPPER(canal) LIKE '%DAB%' THEN 'ATM'
            ELSE 'Autre'
        END AS canal_std,
        
        TRIM(categorie) AS categorie_std,
        
        -- Indicateurs géographiques
        UPPER(TRIM(pays_beneficiaire)) AS pays_beneficiaire,
        CASE WHEN UPPER(pays_beneficiaire) != 'FRANCE' THEN TRUE ELSE FALSE END AS is_international,
        
        -- Indicateurs temporels
        EXTRACT(HOUR FROM heure_transaction) AS heure,
        EXTRACT(DOW FROM date_transaction) AS jour_semaine,  -- 0=Dimanche, 6=Samedi
        
        CASE 
            WHEN EXTRACT(HOUR FROM heure_transaction) BETWEEN 8 AND 18 THEN 'Heures_Ouverture'
            WHEN EXTRACT(HOUR FROM heure_transaction) BETWEEN 19 AND 22 THEN 'Soiree'
            WHEN EXTRACT(HOUR FROM heure_transaction) BETWEEN 22 AND 23 
                 OR EXTRACT(HOUR FROM heure_transaction) BETWEEN 0 AND 6 THEN 'Nuit'
            ELSE 'Matin'
        END AS plage_horaire,
        
        CASE 
            WHEN EXTRACT(DOW FROM date_transaction) IN (0, 6) THEN TRUE 
            ELSE FALSE 
        END AS is_weekend,
        
        CASE 
            WHEN EXTRACT(HOUR FROM heure_transaction) BETWEEN 22 AND 6 THEN TRUE 
            ELSE FALSE 
        END AS is_nocturne,
        
        -- Indicateurs de risque (à affiner avec les modèles intermediate)
        CASE 
            WHEN montant > 5000 THEN TRUE 
            ELSE FALSE 
        END AS is_montant_eleve,
        
        -- Statut
        UPPER(TRIM(statut)) AS statut,
        
        -- Placeholder pour score d'anomalie (sera calculé plus tard)
        NULL::NUMERIC AS score_anomalie,
        
        -- Métadonnées
        loaded_at,
        CURRENT_TIMESTAMP AS updated_at
        
    FROM source
    
    WHERE transaction_id IS NOT NULL
      AND client_id IS NOT NULL
      AND date_transaction IS NOT NULL
      AND montant IS NOT NULL
)

SELECT * FROM cleaned
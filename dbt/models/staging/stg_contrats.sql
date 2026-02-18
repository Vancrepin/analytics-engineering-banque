{{
    config(
        materialized='view',
        tags=['staging', 'contrats']
    )
}}

/*
    Modèle STAGING : Contrats d'assurance
    
    Objectif :
    - Standardiser les contrats
    - Calculer la durée et l'ancienneté
    - Normaliser les types de produits
    - Préparer pour les calculs de performance
    
    Source : raw.contrats
*/

WITH source AS (
    SELECT * FROM {{ source('raw', 'contrats') }}
),

cleaned AS (
    SELECT
        -- Clés
        {{ dbt_utils.generate_surrogate_key(['contrat_id']) }} AS contrat_key,
        contrat_id,
        {{ dbt_utils.generate_surrogate_key(['client_id']) }} AS client_key,
        client_id,
        
        -- Produit
        produit_id,
        TRIM(type_produit) AS type_produit_std,
        
        -- Dates
        date_souscription,
        date_effet,
        date_echeance,
        
        -- Calculs de durée
        EXTRACT(YEAR FROM AGE(date_echeance, date_effet)) * 12 + 
        EXTRACT(MONTH FROM AGE(date_echeance, date_effet)) AS duree_mois,
        
        EXTRACT(YEAR FROM AGE(CURRENT_DATE, date_effet)) * 12 + 
        EXTRACT(MONTH FROM AGE(CURRENT_DATE, date_effet)) AS anciennete_mois,
        
        CURRENT_DATE - date_effet AS anciennete_jours,
        
        -- Montants financiers
        prime_mensuelle,
        prime_mensuelle * 12 AS prime_annuelle,
        capital_assure,
        franchise,
        
        -- Ratio capital/prime (indicateur de valeur)
        CASE 
            WHEN prime_mensuelle > 0 
            THEN capital_assure / (prime_mensuelle * 12)
            ELSE NULL 
        END AS ratio_capital_prime,
        
        -- Statut
        UPPER(TRIM(statut)) AS statut,
        CASE 
            WHEN UPPER(statut) = 'ACTIF' AND date_echeance >= CURRENT_DATE THEN TRUE
            ELSE FALSE
        END AS is_actif,
        
        CASE 
            WHEN UPPER(statut) = 'RÉSILIÉ' 
                 OR UPPER(statut) = 'RESILIE' THEN TRUE
            ELSE FALSE
        END AS is_resilie,
        
        CASE 
            WHEN date_echeance < CURRENT_DATE THEN TRUE
            ELSE FALSE
        END AS is_echu,
        
        -- Mode de paiement
        TRIM(mode_paiement) AS mode_paiement,
        
        -- Segmentation produit
        CASE 
            WHEN type_produit IN ('Auto', 'Habitation') THEN 'IARD'
            WHEN type_produit IN ('Vie', 'Épargne') THEN 'Vie_Epargne'
            WHEN type_produit = 'Santé' THEN 'Sante'
            ELSE 'Autre'
        END AS categorie_produit,
        
        -- Indicateurs de rentabilité potentielle
        CASE 
            WHEN prime_mensuelle > 100 AND capital_assure > 50000 THEN 'Premium'
            WHEN prime_mensuelle > 50 THEN 'Standard'
            ELSE 'Basique'
        END AS segment_valeur,
        
        -- Métadonnées
        loaded_at,
        CURRENT_TIMESTAMP AS updated_at
        
    FROM source
    
    WHERE contrat_id IS NOT NULL
      AND client_id IS NOT NULL
      AND date_souscription IS NOT NULL
)

SELECT * FROM cleaned
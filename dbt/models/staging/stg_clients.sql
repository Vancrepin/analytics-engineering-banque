{{
    config(
        materialized='view',
        tags=['staging', 'clients']
    )
}}

/*
    Modèle STAGING : Clients
    
    Objectif :
    - Nettoyer et standardiser les données clients
    - Créer une clé surrogate (hash stable)
    - Calculer des métriques utiles (âge, ancienneté)
    - Normaliser les formats (email, ville)
    
    Source : raw.clients
*/

WITH source AS (
    SELECT * FROM {{ source('raw', 'clients') }}
),

cleaned AS (
    SELECT
        -- Clé technique (surrogate key) - hash stable du client_id
        {{ dbt_utils.generate_surrogate_key(['client_id']) }} AS client_key,
        
        -- Identifiants
        client_id,
        
        -- Dates
        date_creation,
        date_naissance,
        
        -- Informations personnelles nettoyées
        TRIM(UPPER(nom)) AS nom,
        TRIM(INITCAP(prenom)) AS prenom,
        TRIM(nom) || ' ' || TRIM(prenom) AS nom_complet,
        
        -- Email normalisé (lowercase)
        LOWER(TRIM(email)) AS email_normalise,
        REPLACE(REPLACE(telephone, ' ', ''), '.', '') AS telephone_normalise,
        
        -- Adresse
        TRIM(adresse) AS adresse,
        code_postal,
        TRIM(INITCAP(ville)) AS ville_normalise,
        UPPER(TRIM(pays)) AS pays_code,
        
        -- Segmentation
        segment_client,
        score_credit,
        
        -- Catégorisation du score crédit
        CASE 
            WHEN score_credit >= 750 THEN 'Excellent'
            WHEN score_credit >= 650 THEN 'Bon'
            WHEN score_credit >= 550 THEN 'Moyen'
            ELSE 'Faible'
        END AS score_credit_categorie,
        
        -- Calculs métier
        EXTRACT(YEAR FROM AGE(CURRENT_DATE, date_naissance)) AS age,
        DATE_PART('year', AGE(CURRENT_DATE, date_creation)) * 12 + 
        DATE_PART('month', AGE(CURRENT_DATE, date_creation)) AS anciennete_mois,
        CURRENT_DATE - date_creation::DATE AS anciennete_jours,
        
        -- Indicateurs booléens
        CASE WHEN CURRENT_DATE <= date_creation::DATE + INTERVAL '90 days' 
             THEN TRUE ELSE FALSE 
        END AS is_nouveau_client,
        
        TRUE AS is_active,  -- Tous actifs pour l'instant
        
        -- Métadonnées
        loaded_at,
        CURRENT_TIMESTAMP AS updated_at
        
    FROM source
    
    -- Filtres de qualité
    WHERE client_id IS NOT NULL
      AND email IS NOT NULL
      AND date_creation IS NOT NULL
)

SELECT * FROM cleaned